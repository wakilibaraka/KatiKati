#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="KatiKati"
CLI_NAME="window-lab"
PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/KatiKati.xcodeproj"
DERIVED_DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
# 必须和 install_local_release.sh 用同一张证书：开发构建与已安装包 bundle id 相同，
# 共用一条辅助功能授权记录，两边身份不一致就会互相作废。证书解析在 lib/sign_app.sh，
# 那里同时负责判断「这次签名还对不对得上那条授权」。
source "$(dirname "${BASH_SOURCE[0]}")/lib/sign_app.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/clean_stale_install.sh"

# One KatiKati on disk: other copies share the bundle id and fight over the same permission record.
remove_other_copies() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  remove_other_katikati_copies "$APP_BUNDLE"
}

build_app() {
  remove_other_copies
  # Force the universal product to be re-created on every build. After an `xcodebuild test` has
  # already relinked the per-arch binaries, a plain build can skip CreateUniversalBinary and leave
  # the previous executable in the .app (re-signed below, so its mtime looks fresh) — the launched
  # app then runs old code while the build log says BUILD SUCCEEDED.
  rm -f "$APP_EXECUTABLE"
  xcodebuild -project "$PROJECT_PATH" -scheme "$APP_NAME" -configuration Debug -skipPackagePluginValidation -derivedDataPath "$DERIVED_DATA_DIR" build >/tmp/katikati-build.log 2>&1
}

sign_app() {
  local identity
  identity="$(katikati_signing_identity)"
  if [[ -z "$identity" ]]; then
    echo "warning: no signing identity found; keeping Xcode's build signature" >&2
    return 0
  fi
  katikati_sign_bundle "$APP_BUNDLE" "$identity"
  # 每次都把签名结论打出来：没有被签名的构建（例如刚跑过 xcodebuild test）会让辅助功能授权
  # 静默失效，窗口一动不动，实机验收就会把它读成「布局没生效」。
  katikati_report_signing "$APP_BUNDLE" || true
}

run_cli() {
  xcodebuild -project "$PROJECT_PATH" -scheme "$CLI_NAME" -configuration Debug -skipPackagePluginValidation -derivedDataPath "$DERIVED_DATA_DIR" build >/tmp/katikati-build.log 2>&1
  "$DERIVED_DATA_DIR/Build/Products/Debug/$CLI_NAME" "$@"
}

# 先确认旧进程真的退干净了再启动。原先这里用 `open -n`（强制再开一个新实例），
# 只要 pkill 慢一拍或有别处启动的实例没被 pkill 覆盖到，屏幕上就会出现两条一模一样
# 的任务条，验收时根本分不清测的是哪个版本。
wait_for_exit() {
  local attempt
  for attempt in $(seq 1 25); do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || return 0
    sleep 0.2
  done
  echo "warning: 旧实例 5 秒内未退出，强制结束" >&2
  pkill -9 -x "$APP_NAME" >/dev/null 2>&1 || true
  sleep 0.3
}

open_app() {
  wait_for_exit
  /usr/bin/open "$APP_BUNDLE"
}

# Portable file mtime. `stat -f` is BSD-only and `stat -c` GNU-only, while `date -r <file>` reads the
# reference file's timestamp on both (the same portability trick graphify_autocommit.sh uses).
file_time() {
  date -r "$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown
}

wait_for_app() {
  local attempt
  for attempt in $(seq 1 20); do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

case "$MODE" in
  run)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_app
    sign_app
    open_app
    ;;
  --debug|debug)
    build_app
    lldb -- "$APP_EXECUTABLE"
    ;;
  --logs|logs)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_app
    sign_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_app
    sign_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"com.katikati.app\""
    ;;
  --launch-trace|launch-trace)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_app
    sign_app
    wait_for_exit
    DOCK_LAUNCH_TRACE=1 "$APP_EXECUTABLE" > /tmp/launch-trace.log 2>&1 &
    wait_for_app
    echo "launch trace: /tmp/launch-trace.log"
    ;;
  --verify|verify)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_app
    sign_app
    open_app
    wait_for_app
    ;;
  --resign|resign)
    # `xcodebuild test` relinks the product and signs it ad-hoc, which discards the Accessibility
    # grant. This puts the local identity back on what is already built (no rebuild) and refuses to
    # leave quietly when the identity is unavailable.
    identity="$(katikati_signing_identity)"
    if [[ -z "$identity" ]]; then
      echo "signing: ❌ no KatiKati signing identity in this keychain — nothing can restore the grant" >&2
      exit 3
    fi
    remove_other_copies
    katikati_sign_bundle "$APP_BUNDLE" "$identity"
    katikati_report_signing "$APP_BUNDLE" || exit 3
    open_app
    wait_for_app
    ;;
  --test|test)
    # A gate you cannot forget: `xcodebuild test` relinks the product and signs it ad-hoc, which
    # silently drops the Accessibility grant, so the next live pass measures nothing (or, worse,
    # reads a still-running instance). This runs the tests and puts the local identity straight back
    # on, printing the verdict for both. Extra arguments pass through, so -only-testing filters and
    # other xcodebuild flags work unchanged:
    #   Scripts/build_and_run.sh --test -only-testing:KatiKatiTests/WallpaperMoodTests
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    test_log="${KATIKATI_TEST_LOG:-/tmp/katikati-test.log}"
    # Read the build time *before* xcodebuild relinks the product: afterwards every timestamp on disk belongs
    # to the untested build, and the stale process's own executable image is no longer readable.
    pre_run_build="$(file_time "$APP_EXECUTABLE")"
    test_status=0
    xcodebuild -project "$PROJECT_PATH" -scheme "$APP_NAME" -destination 'platform=macOS' \
      -skipPackagePluginValidation -derivedDataPath "$DERIVED_DATA_DIR" CODE_SIGNING_ALLOWED=NO \
      test "${@:2}" >"$test_log" 2>&1 || test_status=$?
    if [[ "$test_status" -eq 0 ]]; then
      echo "test: ✅ TEST SUCCEEDED"
    else
      echo "test: ❌ TEST FAILED (xcodebuild exit $test_status)"
    fi
    grep -E "Executed [0-9]+ tests|error: -\[" "$test_log" | tail -4 || true
    echo "test: full log at $test_log"
    # Re-sign unconditionally: the product on disk is ad-hoc whether the tests passed, failed or
    # never built, and that is exactly the state that has to be impossible to leave behind unnoticed.
    identity="$(katikati_signing_identity)"
    if [[ -z "$identity" ]]; then
      echo "signing: ❌ no KatiKati signing identity in this keychain — the test build was left ad-hoc" >&2
      exit 3
    fi
    katikati_sign_bundle "$APP_BUNDLE" "$identity"
    echo "signing: re-signed $APP_NAME.app with \"$identity\" after the test run"
    katikati_report_signing "$APP_BUNDLE" || exit 3
    if [[ "$test_status" -eq 0 ]]; then
      open_app
      if wait_for_app; then echo "signing: relaunched the app on the re-signed build"; fi
    else
      # A red run re-signs the product but never launches it, so anything on screen is the build from before
      # this run — exactly the thing a live pass would measure believing it is the new code. Name it (pid,
      # start time, executable path and its build time, next to the on-disk build time it differs from), then
      # quit it, so the trap cannot be read past.
      if stale_pid="$(pgrep -x "$APP_NAME" | head -1)"; then
        stale_exe="$(ps -o comm= -p "$stale_pid" | sed 's/^ *//')"
        stale_started="$(ps -o lstart= -p "$stale_pid" | sed 's/^ *//; s/ *$//')"
        echo "live: ⚠️  $APP_NAME (pid $stale_pid) is still on screen: started $stale_started, running $stale_exe" >&2
        echo "live: its build was $pre_run_build (the executable's time before the tests); this red run rebuilt it at $(file_time "$APP_EXECUTABLE") and never launched that build" >&2
        pkill -x "$APP_NAME" >/dev/null 2>&1 || true
        wait_for_exit
        if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
          echo "live: ❌ $APP_NAME is still running after the quit — do not live-check it, it is the pre-run build" >&2
        else
          echo "live: quit the stale instance — nothing is left on screen to mistake for the failed build" >&2
        fi
      else
        echo "live: no $APP_NAME is running — a failed run never launches the re-signed build, so there is nothing stale on screen" >&2
      fi
    fi
    exit "$test_status"
    ;;
  --check-signing|check-signing)
    # Read-only gate for a live pass: no build, no re-sign, no launch. Exit 3 when this bundle's
    # signature no longer matches the Accessibility grant, so a harness stops here instead of
    # reporting windows that never moved because nothing was allowed to move them.
    katikati_report_signing "$APP_BUNDLE" || exit 3
    running="$(katikati_running_executable)"
    if [[ -n "$running" && "$running" != "$APP_EXECUTABLE" ]]; then
      echo "signing: ⚠️  the running instance is $running, not the bundle just checked" >&2
      exit 3
    fi
    # 写成 if 而不是 `[[ … ]] && echo`：没有实例在跑时那个复合命令返回 1，脚本会带着 1 退出，
    # 调用方（例如 Scripts/live_check_tiling_presets.py）就会把「没在跑」读成「签名不对」而拒绝开工。
    if [[ -n "$running" ]]; then
      echo "signing: running instance is this bundle (pid $(pgrep -x "$APP_NAME" | head -1))"
    fi
    ;;
  --lab|lab)
    run_cli "${@:2}"
    ;;
  --lab-minimize|lab-minimize)
    run_cli minimizeRestore "${@:2}"
    ;;
  --lab-close|lab-close)
    run_cli closeTarget "${@:2}"
    ;;
  --lab-replay|lab-replay)
    run_cli replay "${2:-minimize-restore-replay}"
    ;;
  --lab-placement|lab-placement)
    run_cli placementReplay "${2:-placement-permanent-hold-replay}"
    ;;
  --lab-transition|lab-transition)
    run_cli transitionReplay "${2:-focused-active-replay}"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--launch-trace|--verify|--resign|--check-signing|--test [xcodebuild test args…]|--lab|--lab-minimize|--lab-close|--lab-replay [scenario-name]|--lab-placement [scenario-name]|--lab-transition [scenario-name]]" >&2
    exit 2
    ;;
esac
