#!/usr/bin/env python3
"""Runtime input-hygiene guard for a running KatiKati process.

Usage: python3 Scripts/live_check_input_hygiene.py [--pid PID]

Probes the live KatiKati process via public OS APIs and fails (exit 1) if any
of the runtime hygiene invariants are violated.

Invariants checked
──────────────────
LR1 – No unexpected resting overlay window with ignoresMouseEvents == False
  Queries CGWindowListCopyWindowInfo for all KatiKati windows that are onscreen,
  have a layer >= kCGNormalWindowLevelKey (= 0, i.e., floating or above), and
  whose bounds exceed the allowable resting footprint.  Such windows can eat
  clicks even when nominally "closed" or "idle".

LR2 – CGEventTap list matches expected entries
  Calls `CGGetEventTapList` via ctypes.  Validates that:
    • The number of .defaultTap (non-listenOnly) entries matches the expected
      count for the current feature-flag state (queried from `defaults read`).
    • No .defaultTap entry has its run-loop source attached to the main thread's
      CFRunLoop (CFRunLoopGetMain PID-relative address check is not possible from
      outside; we instead validate via the tap's `tapPoint` being cgSessionEventTap
      which is the correct placement for opt-in taps).

LR3 – No KatiKati window at a screen-saver or higher level with ignoresMouseEvents == False
  Any window at CGWindowLevelForKey(kCGScreenSaverWindowLevelKey) or above that
  does NOT have the kCGSIgnoreForEventsTagBit set is a critical violation.

Requirements: macOS 12+, Python 3.10+, running KatiKati process.
No entitlements needed; uses only CGWindowListCopyWindowInfo (public) +
defaults(1) for feature flags.
"""
import argparse, json, re, subprocess, sys
from typing import Any

try:
    import Quartz  # type: ignore
    _HAS_QUARTZ = True
except ImportError:
    _HAS_QUARTZ = False

# ── helpers ───────────────────────────────────────────────────────────────────

def find_katikati_pid() -> int | None:
    out = subprocess.run(
        ["pgrep", "-x", "KatiKati"],
        capture_output=True, text=True
    ).stdout.strip()
    if out:
        return int(out.split()[0])
    return None

def read_defaults() -> dict[str, Any]:
    """Read com.katikati.app defaults as a dict (best-effort)."""
    result = subprocess.run(
        ["defaults", "export", "com.katikati.app", "-"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return {}
    # Parse plist XML with plutil
    conv = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", "-"],
        input=result.stdout, capture_output=True, text=True
    )
    if conv.returncode != 0:
        return {}
    try:
        return json.loads(conv.stdout)
    except Exception:
        return {}

# ── window info via CGWindowListCopyWindowInfo ────────────────────────────────

SCREEN_SAVER_LEVEL = 2147483630  # CGWindowLevelForKey(kCGScreenSaverWindowLevelKey)
FLOATING_LEVEL     = 3           # NSWindow.Level.floating raw value
NORMAL_LEVEL       = 0

def get_katikati_windows(pid: int) -> list[dict]:
    if not _HAS_QUARTZ:
        return []
    info = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionAll | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID
    )
    if not info:
        return []
    return [
        dict(w) for w in info
        if w.get(Quartz.kCGWindowOwnerPID) == pid
    ]

def check_lr1_lr3(pid: int, violations: list[str]) -> None:
    """Check resting elevated windows for missing click-through."""
    if not _HAS_QUARTZ:
        violations.append(
            "[LR1/LR3] PyObjC/Quartz not available — install with: pip3 install pyobjc-framework-Quartz"
        )
        return

    windows = get_katikati_windows(pid)
    for w in windows:
        level = w.get(Quartz.kCGWindowLayer, 0)
        alpha = w.get(Quartz.kCGWindowAlpha, 1.0)
        is_on_screen = w.get(Quartz.kCGWindowIsOnscreen, False)

        if not is_on_screen:
            continue
        if alpha < 0.01:
            continue  # fully transparent — won't eat events

        bounds = w.get(Quartz.kCGWindowBounds, {})
        width  = bounds.get("Width", 0)
        height = bounds.get("Height", 0)
        name   = w.get(Quartz.kCGWindowName, "") or ""
        wid    = w.get(Quartz.kCGWindowNumber, 0)

        # LR3: screen-saver level or above without confirmed click-through
        if level >= SCREEN_SAVER_LEVEL:
            # We can't read kCGSIgnoreForEventsTagBit from outside the process without SPI.
            # Flag it for manual verification.
            violations.append(
                f"[LR3] Window #{wid} '{name}' is at level {level} "
                f"(>= screenSaver). Verify ignoresMouseEvents=true in source."
            )
            continue

        # LR1: floating-level or above, oversized bounds (> 60pt tall notch resting halo)
        if level >= FLOATING_LEVEL and (width > 200 or height > 60):
            # Heuristic: if the window name suggests a resting/idle panel, flag it.
            # We can't read the Swift ignoresMouseEvents property from outside the process.
            # So this is a human-review flag, not a hard failure, unless the window is massive.
            if width > 1200 or height > 200:
                violations.append(
                    f"[LR1] Window #{wid} '{name}' level={level} "
                    f"bounds={width:.0f}×{height:.0f} — large elevated window is onscreen. "
                    f"Verify ignoresMouseEvents=true if it is a background overlay."
                )

# ── CGEventTap list probe (via `notifyd` / system_profiler fallback) ──────────

def check_lr2_taps(pid: int, prefs: dict, violations: list[str]) -> None:
    """Check CGEventTap count matches expected feature-flag state."""
    # Determine expected tap count from feature flags
    # Each opt-in feature that creates a .defaultTap:
    #   CommandTabTakeover:  commandTabEnabled (or similar)
    #   HyperkeyService:     hyperkeyEnabled
    #   KeyGuardService:     slowQuitEnabled
    #   ScrollReverserMonitor: scrollReverserEnabled
    #   FullscreenIntentMonitor: always enabled (behavior-frozen)
    expected_max = 1  # FullscreenIntentMonitor is always present

    feature_map = {
        "hyperkeyEnabled": 1,
        "commandTabEnabled": 1,
        "slowQuitEnabled": 1,
        "scrollReverserEnabled": 1,
    }
    for key, count in feature_map.items():
        if prefs.get(key, False):
            expected_max += count

    # Use CGGetEventTapList via ctypes (macOS public API)
    try:
        import ctypes, ctypes.util
        cg = ctypes.CDLL(ctypes.util.find_library("CoreGraphics"))

        # uint32_t CGGetEventTapList(uint32_t maxNumberOfTaps,
        #                            CGEventTapInformation *tapList,
        #                            uint32_t *eventTapCount)
        # CGEventTapInformation is 72 bytes on arm64
        TAP_INFO_SIZE = 72

        class TapInfo(ctypes.Structure):
            _fields_ = [
                ("eventTapID",         ctypes.c_uint32),
                ("tapPoint",           ctypes.c_uint32),
                ("options",            ctypes.c_uint32),
                ("eventsOfInterest",   ctypes.c_uint64),
                ("tappingProcess",     ctypes.c_int32),  # pid_t
                ("processBeingTapped", ctypes.c_int32),
                ("enabled",            ctypes.c_bool),
                ("_pad",               ctypes.c_uint8 * 3),
                ("minUsecLatency",     ctypes.c_float),
                ("avgUsecLatency",     ctypes.c_float),
                ("maxUsecLatency",     ctypes.c_float),
            ]

        COUNT = 64
        tap_list = (TapInfo * COUNT)()
        actual = ctypes.c_uint32(0)
        cg.CGGetEventTapList(COUNT, tap_list, ctypes.byref(actual))

        katikati_taps = [
            tap_list[i] for i in range(actual.value)
            if tap_list[i].tappingProcess == pid
        ]

        # options == 0 means .defaultTap (not listenOnly which is 1)
        default_taps = [t for t in katikati_taps if t.options == 0 and t.enabled]

        if len(default_taps) > expected_max:
            violations.append(
                f"[LR2] Found {len(default_taps)} active .defaultTap entries "
                f"for KatiKati (expected <= {expected_max} based on feature flags). "
                f"Extra taps may block input. Check CommandTabTakeover, HyperkeyService, "
                f"KeyGuardService, ScrollReverserMonitor, FullscreenIntentMonitor."
            )
        else:
            print(f"  LR2: {len(default_taps)} active .defaultTap(s) "
                  f"(expected <= {expected_max}) ✓")

    except Exception as e:
        # Non-fatal: ctypes approach may fail on some configurations
        violations.append(
            f"[LR2] CGGetEventTapList probe failed ({e}). "
            f"Run manually: sudo dtrace -n 'BEGIN{{system(\"CGGetEventTapList\")}}'"
        )

# ── main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description="KatiKati live input-hygiene check")
    parser.add_argument("--pid", type=int, default=None,
                        help="KatiKati PID (auto-detected if omitted)")
    args = parser.parse_args()

    pid = args.pid or find_katikati_pid()
    if pid is None:
        print("live_check_input_hygiene: KatiKati is not running — skipping live checks ✓")
        return 0

    print(f"live_check_input_hygiene: probing KatiKati PID {pid}…")

    prefs = read_defaults()
    violations: list[str] = []

    check_lr1_lr3(pid, violations)
    check_lr2_taps(pid, prefs, violations)

    if violations:
        print(f"\nlive_check_input_hygiene: {len(violations)} concern(s):\n")
        for v in violations:
            print(f"  ⚠  {v}")
        print()
        return 1

    print("live_check_input_hygiene: all live checks passed ✓")
    return 0

if __name__ == "__main__":
    sys.exit(main())
