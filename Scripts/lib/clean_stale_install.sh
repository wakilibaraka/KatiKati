# Sourced by install_local_release.sh. Clears everything a previous KatiKati left behind so a new install
# starts from a known state. Stale TCC rows (bound to an older code identity), a leftover Caps Lock→F18
# remap and other copies sharing the bundle id are what can leave input unusable after a permission toggle.
clean_stale_katikati() {
  local ids=(com.katikati.app com.katikati.app.windowlab)
  echo "==> Cleaning old KatiKati instances, copies and permissions…"
  pkill -x KatiKati >/dev/null 2>&1 || true
  pkill -x window-lab >/dev/null 2>&1 || true
  for _ in $(seq 1 25); do pgrep -x KatiKati >/dev/null 2>&1 || break; sleep 0.2; done
  pkill -9 -x KatiKati >/dev/null 2>&1 || true
  # kill -9 skips the Hyperkey restore; drop the remap only when it is ours (Caps Lock → F18).
  if hidutil property --get UserKeyMapping 2>/dev/null | grep -qi '0x70000006d'; then
    hidutil property --set '{"UserKeyMapping":[]}' >/dev/null 2>&1 || true
    echo "    removed leftover Caps Lock→F18 remap"
  fi
  # Other copies share the bundle id, so macOS may launch or authorise the wrong one.
  remove_other_katikati_copies
  for id in "${ids[@]}"; do tccutil reset All "$id" >/dev/null 2>&1 || true; done
  echo "    permissions reset; grant them again once in the fresh app"
}

# Removes every KatiKati.app macOS knows about except $1, so it can never launch or authorise a stale
# copy. LaunchServices remembers copies in any folder (old build dirs, /tmp, worktrees, the Trash);
# Trash and mounted-DMG copies are only unregistered, everything else is deleted.
remove_other_katikati_copies() {
  local keep="${1:-}" p
  local lsr=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  { "$lsr" -dump 2>/dev/null | sed -n 's/^path: *\(.*\/KatiKati[^/]*\.app\) (0x.*/\1/p'
    ls -d /Applications/KatiKati*.app "$HOME"/Applications/KatiKati*.app \
          "$HOME"/Library/Developer/Xcode/DerivedData/KatiKati-*/Build/Products/*/KatiKati.app 2>/dev/null
  } | sort -u | while IFS= read -r p; do
    [[ "$p" == "$keep" ]] && continue
    "$lsr" -u "$p" >/dev/null 2>&1 || true
    [[ -d "$p" && "$p" != /Volumes/* && "$p" != "$HOME/.Trash/"* ]] || continue
    # Only our own bundle: never delete something that merely shares the name.
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$p/Contents/Info.plist" 2>/dev/null)" == com.katikati.app ]] || continue
    rm -rf "$p" && echo "    removed old copy $p"
  done
}
