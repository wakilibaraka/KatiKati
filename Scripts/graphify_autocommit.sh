#!/bin/bash
# Commits graphify-out/ after the graphify post-commit hook has rebuilt it, so generated
# graph output never sits in the working tree as stray work. CLAUDE.md keeps a committed
# graph.json (a whole-file rewrite per build is expected, not churn), so the fix is to
# commit it, not to stop tracking it.
#
#   Scripts/graphify_autocommit.sh            wait for a rebuild to settle, then commit
#   Scripts/graphify_autocommit.sh install    make the post-commit hook launch it (idempotent;
#                                             re-run after `graphify hook install` overwrites)
#   Scripts/graphify_autocommit.sh selftest   prove the commit / no-commit guards
set -uo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${GRAPHIFY_AUTOCOMMIT_ROOT:-$ROOT}"
HOOK="$ROOT/.git/hooks/post-commit"
MARKER="# graphify-autocommit"
QUIET="${GRAPHIFY_AUTOCOMMIT_QUIET:-2}"
TIMEOUT="${GRAPHIFY_AUTOCOMMIT_TIMEOUT:-600}"

launch_block() {
    cat <<'EOF'

# graphify-autocommit: commit the rebuilt graph so it never shows up as stray work.
# Re-append with: Scripts/graphify_autocommit.sh install   (graphify hook install drops it)
_gfy_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$_gfy_root" ] && [ -x "$_gfy_root/Scripts/graphify_autocommit.sh" ]; then
    nohup "$_gfy_root/Scripts/graphify_autocommit.sh" >/dev/null 2>&1 &
    disown 2>/dev/null || true
fi
EOF
}

install() {
    if [ ! -f "$HOOK" ]; then
        echo "no post-commit hook at $HOOK — run: graphify hook install" >&2
        return 1
    fi
    if grep -qF "$MARKER" "$HOOK"; then
        # Refresh in place (the block is last), so an edited launcher takes effect and a
        # graphify upgrade that dropped it is repaired by the same command.
        local tmp
        tmp=$(mktemp)
        awk -v m="$MARKER" 'index($0, m) {exit} {print}' "$HOOK" > "$tmp"
        cat "$tmp" > "$HOOK" && rm -f "$tmp"
        launch_block >> "$HOOK"
        chmod +x "$HOOK"
        echo "refreshed in $HOOK"
        return 0
    fi
    launch_block >> "$HOOK"
    chmod +x "$HOOK"
    echo "installed in $HOOK"
}

# One commit of graph output only. Returns 1 when it declined, so selftest can assert.
commit_once() {
    local staged
    [ -n "${GRAPHIFY_AUTOCOMMIT_RUNNING:-}" ] && return 1   # our own commit re-entered the hook
    local marker
    for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
        [ -e "$ROOT/.git/$marker" ] && return 1
    done
    # Staged work belongs to whoever staged it; never fold it into a graph commit.
    [ -n "$(git -C "$ROOT" diff --cached --name-only)" ] && return 1
    git -C "$ROOT" add -u -- graphify-out 2>/dev/null || return 1
    staged="$(git -C "$ROOT" diff --cached --name-only)"
    [ -z "$staged" ] && return 1
    GRAPHIFY_AUTOCOMMIT_RUNNING=1 git -C "$ROOT" commit --no-verify -q \
        -m "graphify: rebuild after $(git -C "$ROOT" rev-parse --short HEAD)" || return 1
    echo "graphify-autocommit: committed $(printf '%s\n' "$staged" | wc -l | tr -d ' ') graph file(s)"
}

# True once the rebuild log has gained a line saying the rebuild ended (or never started).
# Without it, a commit that only skipped the rebuild would park a sleeper for the timeout.
log_finished() {
    local log="$1" start="$2"
    [ -f "$log" ] || return 1
    tail -c "+$((start + 1))" "$log" 2>/dev/null | grep -qE \
        'Rebuilt:|outputs left untouched|skipping rebuild|No tracked code files|Rebuild failed|exceeded'
}

# Waits until a rebuild has both written something and stopped writing. A rebuild writes
# its output at the end, so "quiet" alone would pass before it starts.
run() {
    local log="${GRAPHIFY_REBUILD_LOG:-$HOME/.cache/graphify-rebuild.log}"
    local start deadline
    start=$(wc -c < "$log" 2>/dev/null | tr -d ' '); start=${start:-0}
    deadline=$((SECONDS + TIMEOUT))
    while (( SECONDS < deadline )); do
        sleep "$QUIET"
        if log_finished "$log" "$start"; then
            commit_once
            return 0
        fi
        if [ -n "$(git -C "$ROOT" status --porcelain -- graphify-out 2>/dev/null)" ] &&
           [ -z "$(find "$ROOT/graphify-out" -type f -newermt "-${QUIET} seconds" 2>/dev/null | head -1)" ]; then
            commit_once
            return 0
        fi
    done
}

selftest() {
    local tmp fails=0
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    git -C "$tmp" init -q
    git -C "$tmp" config user.email t@example.com
    git -C "$tmp" config user.name t
    mkdir -p "$tmp/graphify-out" "$tmp/src"
    printf '{"nodes":[]}\n' > "$tmp/graphify-out/graph.json"
    echo 'let a = 1' > "$tmp/src/a.swift"
    git -C "$tmp" add -A && git -C "$tmp" commit -qm init

    # 1. clean tree → nothing to commit
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" GRAPHIFY_AUTOCOMMIT_QUIET=0 GRAPHIFY_AUTOCOMMIT_TIMEOUT=1 "$SELF" >/dev/null
    [ "$(git -C "$tmp" rev-list --count HEAD)" = 1 ] && echo "PASS clean tree stays clean" || { echo "FAIL clean tree"; fails=1; }

    # 2. modified graph output → exactly one graph commit, source left alone
    printf '{"nodes":[1]}\n' > "$tmp/graphify-out/graph.json"
    echo 'let a = 2' > "$tmp/src/a.swift"
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" GRAPHIFY_AUTOCOMMIT_QUIET=0 GRAPHIFY_AUTOCOMMIT_TIMEOUT=5 "$SELF" >/dev/null
    local count subject
    count="$(git -C "$tmp" rev-list --count HEAD)"
    subject="$(git -C "$tmp" log -1 --pretty=%s)"
    [ "$count" = 2 ] && case "$subject" in graphify:*) echo "PASS graph output committed ($subject)";; *) echo "FAIL message: $subject"; fails=1;; esac || { echo "FAIL expected 2 commits, got $count"; fails=1; }
    [ -n "$(git -C "$tmp" status --porcelain -- src)" ] && echo "PASS source edit left uncommitted" || { echo "FAIL source was committed"; fails=1; }

    # 3. staged foreign work → refuse, leave the index alone
    git -C "$tmp" add -A src
    printf '{"nodes":[2]}\n' > "$tmp/graphify-out/graph.json"
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" GRAPHIFY_AUTOCOMMIT_QUIET=0 GRAPHIFY_AUTOCOMMIT_TIMEOUT=5 "$SELF" >/dev/null
    [ "$(git -C "$tmp" rev-list --count HEAD)" = 2 ] && echo "PASS staged work is not folded in" || { echo "FAIL committed over staged work"; fails=1; }

    # 4. a rebuild that skipped itself must not park a sleeper for the whole timeout
    git -C "$tmp" reset -q
    local flog="$tmp/rebuild.log" began
    printf '[graphify hook] 1 file(s) changed - rebuilding graph...\n[graphify watch] No tracked code files in change set - skipping rebuild.\n' > "$flog"
    began=$SECONDS
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" GRAPHIFY_AUTOCOMMIT_QUIET=1 GRAPHIFY_AUTOCOMMIT_TIMEOUT=120 \
        GRAPHIFY_REBUILD_LOG="$flog" "$SELF" >/dev/null
    [ $((SECONDS - began)) -le 10 ] && echo "PASS skipped rebuild exits at once" || { echo "FAIL waited $((SECONDS - began))s on a skipped rebuild"; fails=1; }

    # 5. install twice → exactly one launcher block, and it survives a refresh
    printf '#!/bin/sh\nexit 0\n' > "$tmp/.git/hooks/post-commit"
    mkdir -p "$tmp/Scripts" && cp "$SELF" "$tmp/Scripts/graphify_autocommit.sh"
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" "$tmp/Scripts/graphify_autocommit.sh" install >/dev/null
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" "$tmp/Scripts/graphify_autocommit.sh" install >/dev/null
    [ "$(grep -cF "$MARKER" "$tmp/.git/hooks/post-commit")" = 1 ] && echo "PASS install stays single" || { echo "FAIL install duplicated itself"; fails=1; }
    return "$fails"
}

case "${1:-run}" in
    install) install ;;
    selftest) selftest ;;
    run) run ;;
    *) echo "usage: $0 [run|install|selftest]" >&2; exit 2 ;;
esac
