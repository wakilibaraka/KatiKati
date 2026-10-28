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
# A silent background committer needs a trail; set GRAPHIFY_AUTOCOMMIT_LOG to a file to read it.
trace() { [ -n "${GRAPHIFY_AUTOCOMMIT_LOG:-}" ] && echo "$(date +%H:%M:%S) $*" >> "$GRAPHIFY_AUTOCOMMIT_LOG"; return 0; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${GRAPHIFY_AUTOCOMMIT_ROOT:-$ROOT}"
HOOK="$ROOT/.git/hooks/post-commit"
MARKER="# graphify-autocommit"
QUIET="${GRAPHIFY_AUTOCOMMIT_QUIET:-2}"
TIMEOUT="${GRAPHIFY_AUTOCOMMIT_TIMEOUT:-180}"
# An unstarted rebuild looks exactly like a finished one, and the hook spawns it a beat after
# this waiter; without a grace window the waiter read the gap as "done" and exited.
GRACE="${GRAPHIFY_AUTOCOMMIT_GRACE:-15}"
ROOT_REAL="$(cd "$ROOT" 2>/dev/null && pwd -P || echo "$ROOT")"

launch_block() {
    cat <<'EOF'

# graphify-autocommit: commit the rebuilt graph so it never shows up as stray work.
# Re-append with: Scripts/graphify_autocommit.sh install   (graphify hook install drops it)
_gfy_root=$(git rev-parse --show-toplevel 2>/dev/null)
_gfy_ac="$_gfy_root/Scripts/graphify_autocommit.sh"
if [ -n "$_gfy_root" ] && [ -x "$_gfy_ac" ]; then
    # Its own session, like the rebuild itself: a waiter must outlive the shell that committed,
    # and a process-group kill (closing the terminal, a tool cleaning up) must not take it out.
    python3 -c 'import subprocess, sys
subprocess.Popen(["/bin/bash", sys.argv[1]], stdin=subprocess.DEVNULL,
                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)' \
        "$_gfy_ac" >/dev/null 2>&1 &
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
    [ -n "${GRAPHIFY_AUTOCOMMIT_RUNNING:-}" ] && { trace "skip: re-entered"; return 1; }   # our own commit re-entered the hook
    local marker
    for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
        [ -e "$ROOT/.git/$marker" ] && { trace "skip: $marker"; return 1; }
    done
    # Staged work belongs to whoever staged it; never fold it into a graph commit.
    [ -n "$(git -C "$ROOT" diff --cached --name-only)" ] && { trace "skip: index has staged work"; return 1; }
    git -C "$ROOT" add -u -- graphify-out 2>/dev/null || return 1
    staged="$(git -C "$ROOT" diff --cached --name-only)"
    [ -z "$staged" ] && { trace "skip: nothing staged after add -u"; return 1; }
    GRAPHIFY_AUTOCOMMIT_RUNNING=1 git -C "$ROOT" commit --no-verify -q \
        -m "graphify: rebuild after $(git -C "$ROOT" rev-parse --short HEAD)" || return 1
    echo "graphify-autocommit: committed $(printf '%s\n' "$staged" | wc -l | tr -d ' ') graph file(s)"
}

graph_dirty() {
    [ -n "$(git -C "$ROOT" status --porcelain -- graphify-out 2>/dev/null)" ]
}

# A rebuild writes its output at the end, so "dirty" alone can be a half-written graph.
# Ages the four files a rebuild writes; `find -newermt '-2 seconds'` is GNU-only, macOS find
# rejects the relative date and would call every write quiet.
graph_quiet() {
    local f m newest=0 now
    now=$(date +%s)
    for f in graph.json GRAPH_REPORT.md graph.html manifest.json; do
        [ -f "$ROOT/graphify-out/$f" ] || continue
        m=$(stat -f %m "$ROOT/graphify-out/$f" 2>/dev/null || stat -c %Y "$ROOT/graphify-out/$f" 2>/dev/null) || continue
        [ -n "${m:-}" ] && [ "$m" -gt "$newest" ] && newest=$m
    done
    [ $((now - newest)) -ge "$QUIET" ]
}

# Waits for the hook's rebuild to leave committed-ready output, then commits it.
# It deliberately does not read the rebuild log: that file is shared by every checkout on
# the machine, so another repo finishing looked like this one finishing and the waiter
# exited before its own output existed.
# shortcut: a rebuild slower than TIMEOUT leaves its output for the next commit to sweep.
# A graph-only commit made the hook skip its rebuild, so its waiter has nothing to wait for.
head_is_graph_only() {
    local files
    files=$(git -C "$ROOT" show --pretty=format: --name-only HEAD 2>/dev/null)
    [ -n "$files" ] && ! printf '%s\n' "$files" | grep -qv '^graphify-out/'
}

# Is this checkout's rebuild still running? Every rebuild on the machine has the same argv,
# so only the working directory tells them apart — which is why the log, shared by all
# checkouts, was the wrong question to ask. Selftest drives this with a file instead of a
# process, since a temp repo has no rebuild of its own.
rebuild_running() {
    if [ -n "${GRAPHIFY_AUTOCOMMIT_BUSY_FILE:-}" ]; then
        [ -e "$GRAPHIFY_AUTOCOMMIT_BUSY_FILE" ]
        return
    fi
    local pid cwd
    for pid in $(ps -Ao pid,command 2>/dev/null | grep -F graphify | grep -v grep |
                 grep -v graphify_autocommit | awk '{print $1}'); do
        cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
        if [ "$cwd" = "$ROOT_REAL" ] || [ "$cwd" = "$ROOT" ]; then return 0; fi
    done
    return 1
}

# Commits what the rebuild leaves, and stops as soon as this checkout's rebuild is gone.
# It deliberately does not read the rebuild log: that file is shared by every checkout on
# the machine, so another repo finishing looked like this one finishing.
# shortcut: a rebuild slower than TIMEOUT leaves its output for the next commit to sweep.
run() {
    trace "started pid=$$ root=$ROOT"
    local began=$SECONDS
    if head_is_graph_only; then
        # The hook skips its rebuild for a graph-only commit, so there is normally nothing here —
        # but an earlier waiter that died, timed out or lost its rebuild leaves dirty output, and
        # returning without looking is what carried it past one more commit. Sweep it.
        if graph_dirty && graph_quiet; then
            commit_once && trace "swept a dead run's output"
        fi
        trace "graph-only commit, nothing else to sweep"
        return 0
    fi
    local deadline=$((SECONDS + TIMEOUT)) idle=0 seen=0
    while :; do
        if graph_dirty && graph_quiet; then
            commit_once && trace "committed"
        fi
        if rebuild_running; then
            seen=1
            idle=0
        elif ! graph_dirty || graph_quiet; then
            # Count a settled poll only once the rebuild has been seen or the grace window has
            # passed; before that, "no process and nothing written" is a rebuild that has not
            # started, not one that has finished.
            if [ "$seen" -eq 1 ] || [ $((SECONDS - began)) -ge "$GRACE" ]; then
                idle=$((idle + 1))
                # Two consecutive settled polls: the rebuild is gone and what it wrote is in.
                # "Settled" includes dirty, so the exit never leaves a fresh write uncommitted —
                # an earlier version did exactly that with manifest.json and stat-index.json.
                if [ "$idle" -ge 2 ]; then
                    if graph_dirty; then commit_once && trace "committed at exit"; fi
                    trace "rebuild finished (dirty=$(graph_dirty && echo yes || echo no))"
                    return 0
                fi
            fi
        else
            idle=0
        fi
        if (( SECONDS >= deadline )); then
            # Never walk away from output that is sitting there finished.
            if graph_dirty && graph_quiet; then commit_once && trace "committed at deadline"; fi
            trace "deadline (dirty=$(graph_dirty && echo yes || echo no))"
            return 0
        fi
        sleep 1
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

    # 4. output still being written is left alone, and a run with nothing to do returns
    #    at its deadline instead of committing a half-written graph
    git -C "$tmp" reset -q
    printf '{"nodes":[3]}\n' > "$tmp/graphify-out/graph.json"
    local began=$SECONDS
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" GRAPHIFY_AUTOCOMMIT_QUIET=30 GRAPHIFY_AUTOCOMMIT_TIMEOUT=3 "$SELF" >/dev/null
    [ "$(git -C "$tmp" rev-list --count HEAD)" = 2 ] && echo "PASS half-written output is left alone" || { echo "FAIL committed a fresh write"; fails=1; }
    [ $((SECONDS - began)) -le 10 ] && echo "PASS gives up at the deadline" || { echo "FAIL overran its deadline"; fails=1; }

    # 5. a graph-only HEAD is the committer's own commit: the hook skipped its rebuild, so
    #    the waiter must not sit out the whole timeout
    git -C "$tmp" add -A -- graphify-out && git -C "$tmp" commit -qm "graphify: test"
    began=$SECONDS
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" GRAPHIFY_AUTOCOMMIT_QUIET=30 GRAPHIFY_AUTOCOMMIT_TIMEOUT=60 "$SELF" >/dev/null
    [ $((SECONDS - began)) -le 5 ] && echo "PASS graph-only commit exits at once" || { echo "FAIL sat out the timeout on a graph-only commit"; fails=1; }

    # 6. a rebuild that writes again after the first commit gets a second one, and the
    #    tree ends clean — the gap that once left output behind
    printf '{"nodes":[4]}\n' > "$tmp/graphify-out/graph.json"
    git -C "$tmp" commit -q --allow-empty -m "code touch"
    #    A "rebuild in progress" file stands in for the rebuild process a temp repo has none of.
    local busy="$tmp/BUSY" before
    : > "$busy"
    before=$(git -C "$tmp" rev-list --count HEAD)
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" GRAPHIFY_AUTOCOMMIT_QUIET=1 GRAPHIFY_AUTOCOMMIT_TIMEOUT=30 \
        GRAPHIFY_AUTOCOMMIT_BUSY_FILE="$busy" "$SELF" >/dev/null &
    waiter=$!
    sleep 4
    printf '{"nodes":[5]}\n' > "$tmp/graphify-out/graph.json"
    sleep 3
    rm -f "$busy"
    wait "$waiter"
    [ -z "$(git -C "$tmp" status --porcelain -- graphify-out)" ] && echo "PASS late write is committed too" || { echo "FAIL late write left behind"; fails=1; }
    [ "$(( $(git -C "$tmp" rev-list --count HEAD) - before ))" -ge 2 ] && echo "PASS both bursts committed" || { echo "FAIL second burst never committed"; fails=1; }

    # 7. install twice → exactly one launcher block, and it survives a refresh
    printf '#!/bin/sh\nexit 0\n' > "$tmp/.git/hooks/post-commit"
    mkdir -p "$tmp/Scripts" && cp "$SELF" "$tmp/Scripts/graphify_autocommit.sh"
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" "$tmp/Scripts/graphify_autocommit.sh" install >/dev/null
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" "$tmp/Scripts/graphify_autocommit.sh" install >/dev/null
    [ "$(grep -cF "$MARKER" "$tmp/.git/hooks/post-commit")" = 1 ] && echo "PASS install stays single" || { echo "FAIL install duplicated itself"; fails=1; }
    grep -q start_new_session "$tmp/.git/hooks/post-commit" && echo "PASS waiter gets its own session" || { echo "FAIL waiter not detached into a session"; fails=1; }

    # 8. a waiter that died before committing leaves dirty output behind a graph-only HEAD;
    #    that early return is exactly what carried it past the next commit, so it must sweep
    printf '{"nodes":[6]}\n' > "$tmp/graphify-out/graph.json"
    git -C "$tmp" add -A -- graphify-out && git -C "$tmp" commit -qm "graphify: test 2"
    printf '{"nodes":[7]}\n' > "$tmp/graphify-out/graph.json"
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" GRAPHIFY_AUTOCOMMIT_QUIET=0 GRAPHIFY_AUTOCOMMIT_TIMEOUT=5 "$SELF" >/dev/null
    [ -z "$(git -C "$tmp" status --porcelain -- graphify-out)" ] && echo "PASS leftover swept on a graph-only HEAD" || { echo "FAIL leftover left uncommitted behind a graph-only HEAD"; fails=1; }

    # 9. a rebuild that has not appeared in the process table yet must not be read as finished;
    #    the old waiter polled twice, saw nothing, and exited before the rebuild started
    printf '{"nodes":[8]}\n' > "$tmp/graphify-out/graph.json"
    git -C "$tmp" add -A -- graphify-out && git -C "$tmp" commit -qm "graphify: test 3"
    git -C "$tmp" commit -q --allow-empty -m "code touch 3"
    printf '{"nodes":[9]}\n' > "$tmp/graphify-out/graph.json"
    local busy2="$tmp/BUSY2"
    # The marker must appear after the old waiter's second empty poll (~2 s), or the race is not
    # reproduced: with a 3 s delay the old code saw the process in time and passed.
    ( sleep 4; : > "$busy2"; sleep 2; printf '{"nodes":[10]}\n' > "$tmp/graphify-out/graph.json"; sleep 1; rm -f "$busy2" ) &
    GRAPHIFY_AUTOCOMMIT_ROOT="$tmp" GRAPHIFY_AUTOCOMMIT_QUIET=1 GRAPHIFY_AUTOCOMMIT_TIMEOUT=40 \
        GRAPHIFY_AUTOCOMMIT_GRACE=10 GRAPHIFY_AUTOCOMMIT_BUSY_FILE="$busy2" "$SELF" >/dev/null
    wait
    [ -z "$(git -C "$tmp" status --porcelain -- graphify-out)" ] && echo "PASS late-starting rebuild is waited for" || { echo "FAIL exited before the rebuild had written"; fails=1; }
    return "$fails"
}

case "${1:-run}" in
    install) install ;;
    selftest) selftest ;;
    run) run ;;
    *) echo "usage: $0 [run|install|selftest]" >&2; exit 2 ;;
esac
