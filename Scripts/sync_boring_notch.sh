#!/bin/bash
# Keep Vendor/boring.notch in step with upstream (Phase 8b-7 owner exception to the "no donors" rule).
#
#   Scripts/sync_boring_notch.sh check    # fetch upstream, report drift. Changes nothing. Exit 1 if drift.
#   Scripts/sync_boring_notch.sh update   # copy the vendored files from upstream HEAD, rewrite MANIFEST.txt
#
# Vendored files are verbatim copies; `update` never merges. Drift in the *watched* files (the ones
# KatiKati re-implements: sizing, ContentView, app/window setup) is reported so the adapter can be
# reviewed by hand. After `update`: run the test suite, then commit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V="$ROOT/Vendor/boring.notch"
MAN="$V/MANIFEST.txt"
REPO="${BORING_NOTCH_REPO:-https://github.com/TheBoredTeam/boring.notch.git}"
MODE="${1:-check}"
[ "$MODE" = check ] || [ "$MODE" = update ] || { echo "usage: $0 check|update" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
git clone --quiet "$REPO" "$WORK/up"
NEW="$(git -C "$WORK/up" rev-parse HEAD)"
OLD="$(awk '$1=="commit"{print $2}' "$MAN")"
echo "pinned:   $OLD"
echo "upstream: $NEW"

drift=0
while read -r sha up local; do
  case "$sha" in \#*|commit|watch|"") continue;; esac
  now="$(shasum -a 256 "$WORK/up/$up" | cut -d' ' -f1)"
  if [ "$now" != "$sha" ]; then
    echo "VENDORED CHANGED: $up"; drift=1
    [ "$MODE" = check ] && git -C "$WORK/up" diff --stat "$OLD" "$NEW" -- "$up" 2>/dev/null || true
  fi
done < "$MAN"

while read -r kw up; do
  [ "$kw" = watch ] || continue
  if ! git -C "$WORK/up" diff --quiet "$OLD" "$NEW" -- "$up" 2>/dev/null; then
    echo "WATCHED CHANGED (review adapter): $up"; drift=1
  fi
done < "$MAN"

if [ "$MODE" = check ]; then
  [ "$drift" = 0 ] && echo "up to date" || echo "drift found — run: $0 update (vendored) and review the adapter (watched)"
  exit "$drift"
fi

tmp="$(mktemp)"
while IFS= read -r line; do
  set -- $line
  case "${1:-}" in
    commit) echo "commit $NEW" ;;
    \#*|watch|"") echo "$line" ;;
    *) cp "$WORK/up/$2" "$V/$3"; echo "$(shasum -a 256 "$V/$3" | cut -d' ' -f1)  $2  $3" ;;
  esac
done < "$MAN" > "$tmp"
mv "$tmp" "$MAN"
cp "$WORK/up/LICENSE" "$V/LICENSE"
echo "updated to $NEW — run the tests, then commit Vendor/boring.notch"
