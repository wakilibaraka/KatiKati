#!/bin/bash
# Keep Vendor/mediaremote-adapter in step with upstream (BSD-3-Clause).
#
#   Scripts/sync_mediaremote_adapter.sh check   # fetch upstream, report drift. Exit 1 if drift.
#   Scripts/sync_mediaremote_adapter.sh update  # copy vendored files from upstream HEAD, rewrite MANIFEST.txt
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V="$ROOT/Vendor/mediaremote-adapter"
MAN="$V/MANIFEST.txt"
REPO="${MEDIAREMOTE_ADAPTER_REPO:-https://github.com/ungive/mediaremote-adapter.git}"
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
  case "$sha" in \#*|commit|"") continue;; esac
  now="$(shasum -a 256 "$WORK/up/$up" | cut -d' ' -f1)"
  if [ "$now" != "$sha" ]; then
    echo "VENDORED CHANGED: $up"; drift=1
    [ "$MODE" = check ] && git -C "$WORK/up" diff --stat "$OLD" "$NEW" -- "$up" 2>/dev/null || true
  fi
done < "$MAN"

if [ "$MODE" = check ]; then
  [ "$drift" = 0 ] && echo "up to date" || echo "drift found — run: $0 update"
  exit "$drift"
fi

tmp="$(mktemp)"
while IFS= read -r line; do
  set -- $line
  case "${1:-}" in
    commit) echo "commit $NEW" ;;
    \#*|"") echo "$line" ;;
    *) cp "$WORK/up/$2" "$V/$3"; echo "$(shasum -a 256 "$V/$3" | cut -d' ' -f1)  $2  $3" ;;
  esac
done < "$MAN" > "$tmp"
mv "$tmp" "$MAN"
chmod +x "$V/bin/mediaremote-adapter.pl"
echo "updated to $NEW — run the tests, then commit Vendor/mediaremote-adapter"
