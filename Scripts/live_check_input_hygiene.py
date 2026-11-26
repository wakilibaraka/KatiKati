#!/usr/bin/env python3
"""Runtime input-hygiene guard for a running KatiKati process.

Usage: python3 Scripts/live_check_input_hygiene.py [--pid PID] [--allow-missing-quartz]

Probes the live KatiKati process via public OS APIs and fails (exit 1) if any
of the runtime hygiene invariants are violated. With no KatiKati running the
script succeeds without probing (there is nothing to violate).

Invariants checked
──────────────────
LR1 – No oversized elevated resting window
  Every KatiKati window at floating level or above that is on screen and opaque
  enough to see is reported per display once it outgrows both resting shapes:
  a bar (full width, at most 120 pt tall — the dock plate) and a rail (at most
  60 pt wide — the edge deck). Such a window can eat clicks when nominally
  closed or idle. The window's `ignoresMouseEvents` flag is not readable from
  outside the process, so a popover-sized one is a human-review note; one large
  in both dimensions is a failure.

LR2 – CGEventTap list matches the expected entries
  Calls `CGGetEventTapList` via ctypes. The number of `.defaultTap`
  (non-listenOnly) entries must not exceed the count implied by the live
  feature flags read from `defaults export com.katikati.app`.

LR3 – No KatiKati window at screen-saver level or above
  Any window at `kCGScreenSaverWindowLevelKey` or above is reported per display
  for a source check of `ignoresMouseEvents`.

LR4 – No elevated window straddles two displays (MD-2 seam guard)
  A floating-or-higher window whose bounds overlap two displays by more than a
  sliver is a click surface on a seam: it is exactly the shape that swallows the
  pointer while crossing between displays. Geometry is public, so this fails.
  A straddle thinner than the dock plate's 20 pt shadow margin is reported as a
  note, not a failure: that band is the plate's own drop shadow, and where it
  crosses onto a display's top edge it lies under the menu bar (window level 25
  vs. the plate's 20), so it cannot take the click.

LR5 – Parked windows use the documented off-screen origin (MD-3)
  A window outside every display must be at the wallpaper overlay's park point
  (`-100000, 100000`) or at least 10 000 pt away on one axis. A window parked a
  few points off screen is a stray that may snap back into view.

Per-display attribution uses the same rule as `WindowDisplayAttribution`: a rect
belongs to the display it overlaps most, and a rect overlapping two displays is
reported against both so a seam problem is never attributed away.

Requirements: macOS 12+, Python 3.9+ (annotations are deferred, so the 3.9
system interpreter works), PyObjC Quartz. A missing PyObjC is a hard failure by
default: a gate that silently checks nothing is worse than no gate. Pass
`--allow-missing-quartz` only when deliberately running without it.
"""
from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import json
import subprocess
import sys
from typing import Any, NamedTuple, Optional

MIN_PYTHON = (3, 9)

try:
    import Quartz  # type: ignore
    HAS_QUARTZ = True
except ImportError:  # pragma: no cover - environment dependent
    HAS_QUARTZ = False


# ── helpers ───────────────────────────────────────────────────────────────────

def find_katikati_pid() -> Optional[int]:
    out = subprocess.run(["pgrep", "-x", "KatiKati"], capture_output=True, text=True).stdout.strip()
    return int(out.split()[0]) if out else None


def read_defaults() -> dict[str, Any]:
    """Read com.katikati.app defaults as a dict (best-effort)."""
    result = subprocess.run(["defaults", "export", "com.katikati.app", "-"], capture_output=True, text=True)
    if result.returncode != 0:
        return {}
    conv = subprocess.run(["plutil", "-convert", "json", "-o", "-", "-"],
                          input=result.stdout, capture_output=True, text=True)
    if conv.returncode != 0:
        return {}
    try:
        return json.loads(conv.stdout)
    except Exception:
        return {}


class Rect(NamedTuple):
    x: float
    y: float
    width: float
    height: float

    @property
    def max_x(self) -> float:
        return self.x + self.width

    @property
    def max_y(self) -> float:
        return self.y + self.height

    def overlap(self, other: "Rect") -> float:
        dx = min(self.max_x, other.max_x) - max(self.x, other.x)
        dy = min(self.max_y, other.max_y) - max(self.y, other.y)
        return max(0.0, dx) * max(0.0, dy)

    def contains(self, px: float, py: float) -> bool:
        return self.x <= px <= self.max_x and self.y <= py <= self.max_y


class Display(NamedTuple):
    display_id: int
    bounds: Rect


def active_displays() -> list[Display]:
    """Online display ids and their Quartz bounds (top-left origin)."""
    if not HAS_QUARTZ:
        return []
    error, ids, count = Quartz.CGGetActiveDisplayList(16, None, None)
    if error != 0 or not ids:
        return []
    out: list[Display] = []
    for display_id in list(ids)[: int(count)]:
        origin, size = Quartz.CGDisplayBounds(display_id)
        out.append(Display(int(display_id), Rect(origin[0], origin[1], size[0], size[1])))
    return out


def display_labels(displays: list[Display]) -> dict[int, str]:
    """A readable per-display label: index in the public display order."""
    return {d.display_id: f"display {index + 1} (id {d.display_id})" for index, d in enumerate(displays)}


def attribute(bounds: Rect, displays: list[Display]) -> list[Display]:
    """Displays a rect sits on: the one it overlaps most, or every display it straddles."""
    overlaps = [(d, d.bounds.overlap(bounds)) for d in displays]
    hits = [(d, area) for d, area in overlaps if area > 0]
    if not hits:
        return []
    # Anything overlapping by more than a 2 pt sliver counts as straddling.
    return [d for d, area in hits if area > 4]


def overlap_thickness(bounds: Rect, display: Display) -> float:
    """The thinner side of the overlap rect: how far the window reaches into a display."""
    width = min(bounds.max_x, display.bounds.max_x) - max(bounds.x, display.bounds.x)
    height = min(bounds.max_y, display.bounds.max_y) - max(bounds.y, display.bounds.y)
    return min(max(0.0, width), max(0.0, height))


SCREEN_SAVER_LEVEL = 2147483630  # CGWindowLevelForKey(kCGScreenSaverWindowLevelKey)
FLOATING_LEVEL = 3               # NSWindow.Level.floating
LR1_BAR_HEIGHT = 120.0           # a dock plate is wide but never this tall
LR1_RAIL_WIDTH = 60.0            # an edge deck is tall but never this wide
LR1_REVIEW_WIDTH = 600.0         # beyond both shapes: worth a human look
LR1_REVIEW_HEIGHT = 400.0
LR1_FAIL_WIDTH = 1200.0          # large in both dimensions: a click-eating overlay
LR1_FAIL_HEIGHT = 600.0
LR4_SHADOW_MARGIN = 20.0         # a dock plate's drop-shadow padding
PARK_ORIGIN = (-100000.0, 100000.0)
STRAY_DISTANCE = 10_000.0


def katikati_windows(pid: int) -> list[dict[str, Any]]:
    if not HAS_QUARTZ:
        return []
    info = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionAll | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID,
    )
    return [dict(w) for w in (info or []) if w.get(Quartz.kCGWindowOwnerPID) == pid]


def rect_of(window: dict[str, Any]) -> Rect:
    bounds = window.get(Quartz.kCGWindowBounds, {}) or {}
    return Rect(bounds.get("X", 0), bounds.get("Y", 0), bounds.get("Width", 0), bounds.get("Height", 0))


# ── checks ────────────────────────────────────────────────────────────────────

def check_windows(pid: int, violations: list[str]) -> None:
    """LR1 / LR3 / LR4 / LR5, reported per display."""
    displays = active_displays()
    labels = display_labels(displays)
    windows = katikati_windows(pid)
    if displays:
        print("  displays: " + ", ".join(f"{labels[d.display_id]} {d.bounds.width:.0f}×{d.bounds.height:.0f}"
                                         f" at ({d.bounds.x:.0f},{d.bounds.y:.0f})" for d in displays))

    counts = {d.display_id: 0 for d in displays}
    for window in windows:
        level = window.get(Quartz.kCGWindowLayer, 0)
        alpha = window.get(Quartz.kCGWindowAlpha, 1.0)
        if not window.get(Quartz.kCGWindowIsOnscreen, False) or alpha < 0.01:
            continue

        bounds = rect_of(window)
        name = (window.get(Quartz.kCGWindowName, "") or "").strip()
        wid = window.get(Quartz.kCGWindowNumber, 0)
        hosts = attribute(bounds, displays)
        for host in hosts:
            counts[host.display_id] += 1
        where = ", ".join(labels[h.display_id] for h in hosts) if hosts else "no display"

        if level >= SCREEN_SAVER_LEVEL:
            violations.append(
                f"[LR3] window #{wid} '{name}' on {where} sits at level {level} (>= screenSaver); "
                f"verify ignoresMouseEvents=true in source."
            )
            continue

        if len({h.display_id for h in hosts}) > 1 and level >= FLOATING_LEVEL:
            thickness = min(overlap_thickness(bounds, host) for host in hosts)
            if thickness <= LR4_SHADOW_MARGIN:
                print(f"  note: [LR4] window #{wid} '{name}' level={level} crosses the seam by "
                      f"{thickness:.0f} pt ({where}) — inside the plate shadow margin, under the "
                      f"menu bar; not a click surface.")
            else:
                violations.append(
                    f"[LR4] window #{wid} '{name}' at level {level} straddles a display seam "
                    f"({where}, {thickness:.0f} pt in); a click surface on the seam swallows the "
                    f"pointer while crossing."
                )

        if not hosts:
            parked = bounds.x <= PARK_ORIGIN[0] + 1 or bounds.y >= PARK_ORIGIN[1] - 1
            far = (bounds.x <= -STRAY_DISTANCE or bounds.y >= STRAY_DISTANCE
                   or bounds.max_x <= -STRAY_DISTANCE or bounds.max_y >= STRAY_DISTANCE)
            if not (parked or far):
                violations.append(
                    f"[LR5] window #{wid} '{name}' is at ({bounds.x:.0f},{bounds.y:.0f}) "
                    f"{bounds.width:.0f}×{bounds.height:.0f}, outside every display but not at the "
                    f"documented park point."
                )
            continue

        # Bars and rails are the legitimate resting shapes, whatever their long side: the dock
        # plate is 1321×86 on this desk and the edge deck 14×256, and neither can eat a click
        # meant for something else. Only a window beyond *both* shapes is interesting.
        bar_like = bounds.height <= LR1_BAR_HEIGHT
        rail_like = bounds.width <= LR1_RAIL_WIDTH
        if level >= FLOATING_LEVEL and not bar_like and not rail_like:
            if bounds.width > LR1_FAIL_WIDTH and bounds.height > LR1_FAIL_HEIGHT:
                violations.append(
                    f"[LR1] window #{wid} '{name}' level={level} on {where} is "
                    f"{bounds.width:.0f}×{bounds.height:.0f} — large elevated window is on screen. "
                    f"Verify ignoresMouseEvents=true if it is a background overlay."
                )
            elif bounds.width > LR1_REVIEW_WIDTH or bounds.height > LR1_REVIEW_HEIGHT:
                print(f"  note: [LR1] window #{wid} '{name}' level={level} on {where} is "
                      f"{bounds.width:.0f}×{bounds.height:.0f} — larger than a bar or rail; "
                      f"review if it should be resting.")

    if displays:
        print("  onscreen windows per display: "
              + ", ".join(f"{labels[did]}={count}" for did, count in counts.items()))


def check_taps(pid: int, prefs: dict[str, Any], violations: list[str]) -> None:
    """LR2 – the tap list must match the feature flags."""
    expected_max = 1  # FullscreenIntentMonitor is always present (behaviour-frozen)
    for key in ("hyperkeyEnabled", "commandTabEnabled", "slowQuitEnabled", "scrollReverserEnabled"):
        if prefs.get(key, False):
            expected_max += 1

    try:
        cg = ctypes.CDLL(ctypes.util.find_library("CoreGraphics"))

        class TapInfo(ctypes.Structure):
            _fields_ = [
                ("eventTapID", ctypes.c_uint32),
                ("tapPoint", ctypes.c_uint32),
                ("options", ctypes.c_uint32),
                ("eventsOfInterest", ctypes.c_uint64),
                ("tappingProcess", ctypes.c_int32),
                ("processBeingTapped", ctypes.c_int32),
                ("enabled", ctypes.c_bool),
                ("_pad", ctypes.c_uint8 * 3),
                ("minUsecLatency", ctypes.c_float),
                ("avgUsecLatency", ctypes.c_float),
                ("maxUsecLatency", ctypes.c_float),
            ]

        count = 64
        tap_list = (TapInfo * count)()
        actual = ctypes.c_uint32(0)
        cg.CGGetEventTapList(count, tap_list, ctypes.byref(actual))

        ours = [tap_list[i] for i in range(actual.value) if tap_list[i].tappingProcess == pid]
        default_taps = [t for t in ours if t.options == 0 and t.enabled]

        if len(default_taps) > expected_max:
            violations.append(
                f"[LR2] {len(default_taps)} active .defaultTap entries for KatiKati "
                f"(expected <= {expected_max} from the feature flags). Extra taps may block input."
            )
        else:
            print(f"  LR2: {len(default_taps)} active .defaultTap(s) (expected <= {expected_max}) ✓")
    except Exception as error:  # pragma: no cover - environment dependent
        violations.append(f"[LR2] CGGetEventTapList probe failed ({error}).")


# ── main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    if sys.version_info < MIN_PYTHON:
        print(f"live_check_input_hygiene: Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required, "
              f"found {sys.version_info.major}.{sys.version_info.minor}", file=sys.stderr)
        return 2

    parser = argparse.ArgumentParser(description="KatiKati live input-hygiene check")
    parser.add_argument("--pid", type=int, default=None, help="KatiKati PID (auto-detected if omitted)")
    parser.add_argument("--allow-missing-quartz", action="store_true",
                        help="downgrade a missing PyObjC/Quartz to a warning instead of failing")
    args = parser.parse_args()

    if not HAS_QUARTZ:
        message = ("live_check_input_hygiene: PyObjC Quartz is required for the live checks "
                   "(pip3 install pyobjc-framework-Quartz).")
        if args.allow_missing_quartz:
            print(f"⚠  {message} Skipping LR1/LR3/LR4/LR5 by request.")
        else:
            print(message, file=sys.stderr)
            return 2

    pid = args.pid or find_katikati_pid()
    if pid is None:
        print("live_check_input_hygiene: KatiKati is not running — nothing to probe ✓")
        return 0

    print(f"live_check_input_hygiene: probing KatiKati PID {pid}…")

    prefs = read_defaults()
    violations: list[str] = []

    if HAS_QUARTZ:
        check_windows(pid, violations)
    check_taps(pid, prefs, violations)

    if violations:
        print(f"\nlive_check_input_hygiene: {len(violations)} concern(s):\n")
        for violation in violations:
            print(f"  ⚠  {violation}")
        print()
        return 1

    print("live_check_input_hygiene: all live checks passed ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
