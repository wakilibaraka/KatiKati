# Sourced by build_and_run.sh. One place decides which identity the dev build carries, and one place
# answers "does the Accessibility grant still match this bundle?" — because a live check that reads
# frames without that answer cannot tell "the layout did not change" from "the app has no grant".
#
# Why this matters (2026-11-21): TCC stores an Accessibility grant against the code's *designated
# requirement*. A bundle signed with "KatiKati Local Code Signing" carries a requirement naming that
# certificate, which survives every rebuild. `xcodebuild test` relinks and re-signs the product
# ad-hoc, whose requirement is a bare cdhash: every existing grant stops applying, `AXIsProcessTrusted()`
# goes false, window automation silently does nothing, and the live pass reports the windows where
# they already were — indistinguishable from "the tiling preset did not change anything".

KATIKATI_FALLBACK_SIGNING_IDENTITY="KatiKati Local Code Signing"

# Echo the identity to sign with, honouring DEVELOPER_ID_APPLICATION. Prints nothing when this
# machine has neither identity in its keychain.
katikati_signing_identity() {
  local identities preferred="${DEVELOPER_ID_APPLICATION:-}"
  identities="$(security find-identity -v -p codesigning 2>&1 || true)"
  if [[ -n "$preferred" ]] && grep -Fq "\"$preferred\"" <<<"$identities"; then
    printf '%s\n' "$preferred"
  elif grep -Fq "\"$KATIKATI_FALLBACK_SIGNING_IDENTITY\"" <<<"$identities"; then
    printf '%s\n' "$KATIKATI_FALLBACK_SIGNING_IDENTITY"
  fi
}

# Echo how $1 is signed: the signing authority's name, "adhoc", "unsigned" or "missing".
katikati_bundle_signature() {
  local bundle="$1" out authority
  if [[ ! -d "$bundle" ]]; then
    printf 'missing\n'
    return 0
  fi
  out="$(codesign -dv --verbose=2 "$bundle" 2>&1 || true)"
  if grep -q 'Signature=adhoc' <<<"$out"; then
    printf 'adhoc\n'
    return 0
  fi
  authority="$(sed -n 's/^Authority=//p' <<<"$out" | head -1)"
  if [[ -n "$authority" ]]; then
    printf '%s\n' "$authority"
  else
    printf 'unsigned\n'
  fi
}

# Sign $1 (a bundle) with $2, nested code first. Deliberately no --options runtime / --entitlements:
# hardened runtime blocks debugger attach (and the entitlements file would replace Xcode's Debug
# get-task-allow), while TCC keys on the certificate chain + bundle id, not the runtime flag.
katikati_sign_bundle() {
  local bundle="$1" identity="$2" framework nested
  framework="$bundle/Contents/Frameworks/Sparkle.framework"
  if [[ -d "$framework" ]]; then
    # Sparkle ships more than one executable (Updater.app, Autoupdate); an outer-only re-sign leaves
    # them on Xcode's certificate and the updater refuses to launch next to a host it disagrees with.
    for nested in "$framework/Versions/B/Updater.app" "$framework/Versions/B/Autoupdate"; do
      [[ -e "$nested" ]] && /usr/bin/codesign --force --sign "$identity" "$nested" >>/tmp/katikati-codesign.log 2>&1
    done
    /usr/bin/codesign --force --sign "$identity" "$framework" >>/tmp/katikati-codesign.log 2>&1
  fi
  /usr/bin/codesign --force --sign "$identity" "$bundle" >>/tmp/katikati-codesign.log 2>&1
}

# Print the verdict for $1. Returns 0 when the bundle still matches the grant's identity, 3 when it
# does not (ad-hoc/unsigned/different certificate), 2 when there is no bundle to judge.
katikati_report_signing() {
  local bundle="$1" authority identity
  authority="$(katikati_bundle_signature "$bundle")"
  identity="$(katikati_signing_identity)"
  case "$authority" in
    missing)
      echo "signing: ❌ no app bundle at $bundle" >&2
      return 2
      ;;
    adhoc|unsigned)
      echo "signing: ❌ $authority — the Accessibility grant no longer matches this build" >&2
      echo "  An $authority signature's designated requirement is its cdhash, so a grant recorded for" >&2
      echo "  \"${identity:-$KATIKATI_FALLBACK_SIGNING_IDENTITY}\" cannot apply to it. Window automation runs untrusted:" >&2
      echo "  nothing moves, and a live pass reads the windows exactly where the previous pass left them." >&2
      if [[ -n "$identity" ]]; then
        echo "  Fix: Scripts/build_and_run.sh --resign (re-signs what is already built with \"$identity\"), then re-grant" >&2
        echo "       Accessibility in Settings › General › Permissions if the app asks for it." >&2
      else
        echo "  Fix: no KatiKati signing identity is in this keychain, so nothing can restore the grant — install" >&2
        echo "       \"$KATIKATI_FALLBACK_SIGNING_IDENTITY\" or run Scripts/install_local_release.sh first." >&2
      fi
      return 3
      ;;
  esac
  if [[ -n "$identity" && "$authority" != "$identity" ]]; then
    echo "signing: ⚠️  signed by \"$authority\" instead of \"$identity\" — the grant follows the requirement, so it may not match" >&2
    return 3
  fi
  echo "signing: ✅ \"$authority\" — the Accessibility grant's requirement still matches"
  return 0
}

# Echo the executable of the running KatiKati, if any. A bundle signed correctly on disk can still be
# shadowed by an instance launched from another copy, so a live pass should compare the two.
katikati_running_executable() {
  local pid
  pid="$(pgrep -x KatiKati 2>/dev/null | head -1)"
  [[ -n "$pid" ]] && ps -o comm= -p "$pid"
  return 0
}
