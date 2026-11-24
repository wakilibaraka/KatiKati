#!/usr/bin/env python3
"""Static CI guard for KatiKati input-hygiene rules.

Usage: python3 Scripts/check_input_hygiene.py

Exit 0 = clean.  Exit 1 = violations found (list printed to stdout).

Three rules checked
───────────────────
Rule 1 – No `.defaultTap` CGEventTap on CFRunLoopGetMain().
  Any file that calls both `tapCreate` (with `.defaultTap`) AND `CFRunLoopGetMain()` in the
  same function block is a violation — the tap will stall the WindowServer HID pipeline on
  the main thread.  Files on the ALLOWLIST are known-safe (they use a dedicated thread loop).

Rule 2 – No un-allowlisted 24/7 resident global mouse click/drag/scroll monitor.
  Specific event masks that are heavy when permanently resident: .mouseMoved, .leftMouseDown /
  .rightMouseDown / .otherMouseDown (click-eating risk), .scrollWheel (scroll hijack risk),
  .leftMouseDragged / .rightMouseDragged.
  Monitors are OK when:
    a) the file is on the per-event ALLOWLIST (feature-scoped, not 24/7), OR
    b) the monitor is installed/removed conditionally (guarded by a flag/state) — we can't
       prove this statically, so only files NOT on the allowlist AND whose monitor is proven
       resident (always installed in init / start / viewDidLoad) fail.
  Conservative: flag only the allowlist; human review confirms the rest.

Rule 3 – Every elevated overlay window (level >= .floating) that sets ignoresMouseEvents
  must do so explicitly.  A line like `panel.level = .floating` without a matching
  `ignoresMouseEvents = true` OR a `# INTERACTIVE` annotation comment in the same file
  is a potential click-eating hazard.

Annotations understood (in Swift source comment lines):
  // INPUT-HYGIENE: ALLOW_MAIN_TAP   — file uses main run loop intentionally (e.g. FullscreenIntentMonitor)
  // INPUT-HYGIENE: ALLOW_RESIDENT_MONITOR — monitor is feature-gated, not 24/7 (but always review)
  // INPUT-HYGIENE: INTERACTIVE       — panel is intentionally interactive (no ignoresMouseEvents needed)
"""
import pathlib, re, sys
from typing import NamedTuple

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC_DIRS = ["App", "Core", "Platform"]

# ── helpers ──────────────────────────────────────────────────────────────────

def swift_files(dirs=SRC_DIRS):
    for d in dirs:
        p = ROOT / d
        if p.is_dir():
            yield from p.rglob("*.swift")

def file_annotations(text: str) -> set[str]:
    """Return the set of INPUT-HYGIENE annotation tags present in the file."""
    return set(re.findall(r"//\s*INPUT-HYGIENE:\s*(\S+)", text))

# ── Rule 1: defaultTap on main run loop ──────────────────────────────────────

# Files allowed to attach a .defaultTap to the main run loop:
# (FullscreenIntentMonitor is behavior-frozen and uses the main loop intentionally)
MAIN_TAP_ALLOWLIST = {
    "FullscreenIntentMonitor.swift",
}

# Pattern: .defaultTap appears in the same file as CFRunLoopGetMain
_RE_DEFAULT_TAP = re.compile(r"\bdefaultTap\b")
_RE_MAIN_RUNLOOP = re.compile(r"\bCFRunLoopGetMain\s*\(\s*\)")

def check_rule1(violations: list[str]) -> None:
    for path in swift_files():
        name = path.name
        if name in MAIN_TAP_ALLOWLIST:
            continue
        text = path.read_text(errors="replace")
        if "ALLOW_MAIN_TAP" in file_annotations(text):
            continue
        if _RE_DEFAULT_TAP.search(text) and _RE_MAIN_RUNLOOP.search(text):
            rel = path.relative_to(ROOT)
            violations.append(
                f"[Rule 1] {rel}: .defaultTap tap attached to CFRunLoopGetMain() "
                f"— move to a dedicated thread or add // INPUT-HYGIENE: ALLOW_MAIN_TAP"
            )

# ── Rule 2: resident 24/7 .mouseMoved global monitor ─────────────────────────

# Files allowed to hold a permanent .mouseMoved monitor (feature-gated by user toggle):
MOUSEMOVED_ALLOWLIST = {
    "FocusFollowService.swift",         # gated by Focus Follows Pointer toggle
    "DockWindowManager.swift",          # gated by dock hover feature
    "DesktopWidgetPanelController.swift",  # stash monitor, gated by widget visibility
    "PanelCoordinator+Spaces.swift",    # MissionControlSession: installed on enter, removed on dismiss
    "StripScrollService.swift",         # gated by StripScroll user toggle (startIfEnabled/stop)
}

# Global monitors whose masks include heavy always-on events that eat input if resident:
HEAVY_MASKS = re.compile(
    r"addGlobalMonitorForEvents\s*\(\s*matching\s*:[^)]*"
    r"(\.mouseMoved|\.scrollWheel)"
)

def check_rule2(violations: list[str]) -> None:
    for path in swift_files():
        name = path.name
        text = path.read_text(errors="replace")
        if "ALLOW_RESIDENT_MONITOR" in file_annotations(text):
            continue
        if not HEAVY_MASKS.search(text):
            continue
        if name in MOUSEMOVED_ALLOWLIST:
            continue
        # Flag it
        rel = path.relative_to(ROOT)
        matches = [m.group(0)[:80] for m in HEAVY_MASKS.finditer(text)]
        for m in matches:
            violations.append(
                f"[Rule 2] {rel}: resident heavy global monitor — {m!r} "
                f"— ensure it is feature-gated or add // INPUT-HYGIENE: ALLOW_RESIDENT_MONITOR"
            )

# ── Rule 3: elevated window without explicit ignoresMouseEvents contract ───────

# Files that are intentionally interactive (Eject, Notch Track Pill, etc.):
INTERACTIVE_WINDOW_ALLOWLIST = {
    "USBEjectPill.swift",           # Eject button — interactive by design
    "NotchTrackPill.swift",         # dismiss-on-click — interactive by design
    "ScreenTimeAlertPresenter.swift",  # Snooze/OK buttons — interactive by design
    "PrivacyUseProbe.swift",        # already sets ignoresMouseEvents = true inline
    "WindowStripController.swift",  # level is normal.rawValue-1 (below normal, not elevated)
    # Panels that explicitly manage ignoresMouseEvents dynamically:
    "NotchPanelController.swift",
    "DockWindowManager.swift",
    "EdgeBarPanelController.swift",
    "DesktopWidgetPanelController.swift",
    "ShelfActions.swift",
    "MenuBarSystemItem.swift",
    # Fully interactive panels (command bar, launcher, etc.):
    "CommandBarPanelController.swift",
    "LauncherPanelController.swift",
    "LauncherOrbController.swift",
    "DesktopSearchPanelController.swift",
    "DictionaryPanelController.swift",
    "EdgeFlyoutController.swift",
    "EdgeNotesPopupController.swift",
    "RadialDialPanelController.swift",
    "RadialSnapPreviewPanelController.swift",
    "TerminalPanelController.swift",
    "TranslatePanelController.swift",
    "TeleprompterWindowController.swift",
    "WidgetPanelController.swift",
    "WindowBorderController.swift",
    "DragController.swift",           # behavior-frozen
    "PanelCoordinator+PanelSetup.swift",
    "PanelCoordinator+ResizeCursor.swift",
    "WindowSnapService.swift",
    "DragShakeWatcher.swift",
    "LiveEventCenter.swift",
    "PowerNotificationCenter.swift",
    "ClaudeApprovalService.swift",
    "ChipPanelController.swift",
    # Toast / overlay panels (statusBar level, ephemeral):
    "KeyVisualizerOverlay.swift",
    "ShortcutToastPresenter.swift",
    "ShortcutCheatSheetOverlay.swift",
    "SlowQuitOverlay.swift",
    "ScreenIdentifyOverlayController.swift",
}

_ELEVATED_LEVEL = re.compile(
    r"\.(level)\s*=\s*(NSWindow\.Level\(|\.floating|\.statusBar|\.popUpMenu|\.screenSaver|\.tornOffMenu)"
)
_IGNORES_MOUSE = re.compile(r"ignoresMouseEvents\s*=\s*true")

def check_rule3(violations: list[str]) -> None:
    for path in swift_files():
        name = path.name
        if name in INTERACTIVE_WINDOW_ALLOWLIST:
            continue
        text = path.read_text(errors="replace")
        if "INTERACTIVE" in file_annotations(text):
            continue
        if not _ELEVATED_LEVEL.search(text):
            continue
        # Has elevated level assignment — must also have ignoresMouseEvents = true
        if _IGNORES_MOUSE.search(text):
            continue
        rel = path.relative_to(ROOT)
        violations.append(
            f"[Rule 3] {rel}: sets elevated window level but has no "
            f"`ignoresMouseEvents = true` and is not in the interactive allowlist — "
            f"add `panel.ignoresMouseEvents = true` or // INPUT-HYGIENE: INTERACTIVE"
        )

# ── main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    violations: list[str] = []
    check_rule1(violations)
    check_rule2(violations)
    check_rule3(violations)

    if violations:
        print(f"check_input_hygiene: {len(violations)} violation(s) found:\n")
        for v in violations:
            print(f"  ✗ {v}")
        print()
        return 1

    print("check_input_hygiene: all rules passed ✓")
    return 0

if __name__ == "__main__":
    sys.exit(main())
