#!/usr/bin/env python3
"""Drive the Side Deck's resting handle and rail, and assert what the deck actually draws.

Why this exists: `live_check_settings_tabs.py` only asks whether a window appeared, so the Side Deck's
rail, its page dock and its panes could regress into an empty glass panel and every earlier check would
still pass. This drives the real input path instead — a HID pointer move onto the 4 x 44 pt resting
handle (the window's tracking area opens the deck after its dwell), then HID clicks on the rail buttons
and the identity strip's Settings gear — and reads the accessibility tree of the open deck to assert the
labels and pane text it renders.

    python3 Scripts/live_check_side_deck.py --app /tmp/katikati-dd-sidedeck/Build/Products/Debug/KatiKati.app \
        --shots build/live-check/side-deck-shots

The deck's edge activation and identity strip are opt-in preferences, both off by default. This script
saves them, turns them on for the run, and restores the saved values afterwards (pass --keep-prefs to
leave them on). It refuses to run while KatiKati is open, because the app terminates other instances at
launch and the measure would then be of the wrong process.

What it checks, in order:
  1. the resting handle window exists at the left edge before anything is hovered;
  2. hovering it opens the deck panel at the configured width with full-height geometry;
  3. the open deck exposes all sixteen rail buttons, the five page-dock tabs and the Pin toggle;
  4. clicking the Storage rail button swaps the pane to Storage content;
  5. clicking the Downloads rail button swaps it to the downloads pane;
  6. clicking the identity strip's gear opens Settings;
  7. a click outside the panel collapses it (the deck has no chevron control; Escape is inert).

Exit code: 0 every step passed; 1 a step failed; 2 a setup problem (app running, no .app, no AX trust).

A manual live-check aid, not a CI step.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / 'build/live-check'
DOMAIN = 'com.katikati.app'
PREFS = ('com.katikati.sidedeck.prefs.v1.edgeActivation',
         'com.katikati.sidedeck.prefs.v1.identityStrip')

RAIL_LABELS = ['Search', 'Windows', 'Apps', 'AI Mission Control', 'Notifications', 'Downloads',
               'Dictionary', 'Dashboard', 'Storage', 'Weather', 'Quick Access', 'Layouts', 'Emoji',
               'Clipboard', 'Clothesline', 'Scratchpad']
PAGE_TAB_LABELS = ['Windows', 'Notifications', 'Downloads', 'Storage', 'Weather']

HELPER_SWIFT = r'''
import AppKit
import ApplicationServices

func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var out: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &out) == .success else { return nil }
    return out
}
func text(_ element: AXUIElement, _ key: String) -> String { (value(element, key) as? String) ?? "" }
func children(_ element: AXUIElement) -> [AXUIElement] {
    (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}
func frame(_ element: AXUIElement) -> CGRect? {
    guard let rawPoint = value(element, kAXPositionAttribute),
          let rawSize = value(element, kAXSizeAttribute),
          CFGetTypeID(rawPoint) == AXValueGetTypeID(),
          CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(unsafeBitCast(rawPoint, to: AXValue.self), .cgPoint, &point)
    AXValueGetValue(unsafeBitCast(rawSize, to: AXValue.self), .cgSize, &size)
    return CGRect(origin: point, size: size)
}
func walk(_ element: AXUIElement, _ depth: Int, _ visit: (AXUIElement, Int) -> Void) {
    guard depth <= 8 else { return }
    visit(element, depth)
    for child in children(element) { walk(child, depth + 1, visit) }
}
func appPID() -> pid_t? {
    if CommandLine.arguments.count > 2, let raw = Int32(CommandLine.arguments[2]) { return raw }
    return NSWorkspace.shared.runningApplications.first { $0.localizedName == "KatiKati" }?.processIdentifier
}
func report(_ element: AXUIElement, _ depth: Int) {
    let pad = String(repeating: "  ", count: depth)
    var body = "\(text(element, kAXRoleAttribute))"
    let desc = text(element, kAXDescriptionAttribute)
    if !desc.isEmpty { body += " desc=\(desc)" }
    let title = text(element, kAXTitleAttribute)
    if !title.isEmpty { body += " title=\(title)" }
    if let raw = value(element, kAXValueAttribute) {
        let asText = "\(raw)"
        if !asText.isEmpty { body += " value=\(asText.prefix(80))" }
    }
    print(pad + body)
}
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : ""
switch mode {
case "trust":
    print(AXIsProcessTrusted() ? "true" : "false")
case "windows":
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    for window in list {
        guard (window[kCGWindowOwnerName as String] as? String) == "KatiKati",
              let layer = window[kCGWindowLayer as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
              let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double else { continue }
        print("\(layer)|\(Int(x))|\(Int(y))|\(Int(w))|\(Int(h))")
    }
case "handle":
    // The handle sits on the left visible edge, vertically centred (SideDeckHandleWindow.show).
    let screen = NSScreen.main!
    let visible = screen.visibleFrame
    let x = visible.minX + 7
    let y = screen.frame.height - visible.midY
    print("\(Int(x)) \(Int(y))")
case "move":
    let point = CGPoint(x: Double(args[2]) ?? 0, y: Double(args[3]) ?? 0)
    CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
case "click":
    let point = CGPoint(x: Double(args[2]) ?? 0, y: Double(args[3]) ?? 0)
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(120_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(70_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
case "focus":
    guard let pid = appPID() else { exit(1) }
    NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
case "keypid":
    // Delivered to the app's own event queue: Escape must not depend on which app is frontmost.
    let code = CGKeyCode(UInt16(args[2]) ?? 53)
    guard args.count > 3, let pid = Int32(args[3]) else { exit(1) }
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)?.postToPid(pid)
    CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.postToPid(pid)
case "find":
    guard args.count > 3, let pid = Int32(args[3]) else { print("no-pid"); exit(1) }
    let root = AXUIElementCreateApplication(pid)
    let wanted = args[2]
    walk(root, 0) { element, _ in
        let role = text(element, kAXRoleAttribute)
        guard role == kAXButtonRole || role == kAXCheckBoxRole || role == kAXMenuButtonRole else { return }
        let label = text(element, kAXDescriptionAttribute)
        let title = text(element, kAXTitleAttribute)
        guard label == wanted || title == wanted else { return }
        guard let box = frame(element) else { return }
        print("\(Int(box.midX)) \(Int(box.midY))")
    }
case "tree":
    guard let pid = appPID() else { print("no-app"); exit(1) }
    let root = AXUIElementCreateApplication(pid)
    for window in children(root) where text(window, kAXRoleAttribute) == kAXWindowRole {
        print("WINDOW \(text(window, kAXSubroleAttribute))")
        walk(window, 0) { element, depth in report(element, depth) }
    }
default:
    print("usage: helper windows|handle|move X Y|click X Y|focus PID|keypid CODE PID|find LABEL PID|tree PID|trust")
    exit(2)
}
'''


def run(*cmd: str, timeout: float = 30) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def helper() -> pathlib.Path:
    binary = WORK / 'deckprobe'
    source = WORK / 'deckprobe.swift'
    WORK.mkdir(parents=True, exist_ok=True)
    # Rebuild when the embedded source changes, not only when it is newer: this file is the source.
    if (binary.exists() and source.exists() and source.read_text() == HELPER_SWIFT
            and binary.stat().st_mtime >= source.stat().st_mtime):
        return binary
    source.write_text(HELPER_SWIFT)
    built = run('xcrun', 'swiftc', '-O', str(source), '-o', str(binary), timeout=180)
    if built.returncode != 0:
        raise RuntimeError(f'swiftc failed:\n{built.stderr}')
    return binary


def pref(name: str) -> str | None:
    out = run('defaults', 'read', DOMAIN, name)
    return out.stdout.strip() if out.returncode == 0 else None


def set_pref(name: str, value: bool) -> None:
    run('defaults', 'write', DOMAIN, name, '-bool', 'true' if value else 'false')


def app_pid(app: str) -> int | None:
    """The pid running this exact bundle — never another KatiKati instance on the machine."""
    exe = str(pathlib.Path(app).resolve() / 'Contents/MacOS/KatiKati')
    out = run('pgrep', '-f', exe)
    pids = [int(n) for n in out.stdout.split()] if out.returncode == 0 else []
    return pids[0] if pids else None


def wait_pid(app: str, timeout: float = 20.0) -> int | None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        pid = app_pid(app)
        if pid:
            return pid
        time.sleep(0.4)
    return None


def windows(binary: pathlib.Path) -> list[tuple[int, int, int, int, int]]:
    rows = []
    for line in run(str(binary), 'windows').stdout.splitlines():
        parts = [int(n) for n in line.split('|')]
        if len(parts) == 5:
            rows.append(tuple(parts))
    return rows


def deck_window(binary: pathlib.Path):
    """The open deck: a KatiKati window 360-560 pt wide and at least 900 pt tall (full height)."""
    for layer, x, y, w, h in windows(binary):
        if 360 <= w <= 560 and h >= 900:
            return layer, x, y, w, h
    return None


def ax_tree(binary: pathlib.Path, pid: int, need: str | None = None, timeout: float = 8.0) -> str:
    """Read the app's accessibility tree, waiting for it to be populated.

    A freshly launched accessory app answers AX before SwiftUI has published the panel's children, and
    the previous instance is still exiting for a moment after `open -n`, so an immediate read can be
    empty. Poll until *need* (or any content) is there.
    """
    deadline = time.time() + timeout
    tree = ''
    while time.time() < deadline:
        tree = run(str(binary), 'tree', str(pid)).stdout
        if tree.strip() and (need is None or need in tree):
            return tree
        time.sleep(0.4)
    return tree


def find_point(binary: pathlib.Path, pid: int, label: str) -> tuple[int, int] | None:
    lines = run(str(binary), 'find', label, str(pid)).stdout.splitlines()
    points = []
    for line in lines:
        parts = line.split()
        if len(parts) == 2:
            points.append((int(parts[0]), int(parts[1])))
    if not points:
        return None
    # Rail buttons are the leftmost column; the page dock repeats several of the same titles.
    return min(points)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True, help='path to the built KatiKati.app')
    parser.add_argument('--shots', help='directory for screenshots of each step (created if needed)')
    parser.add_argument('--keep-prefs', action='store_true',
                        help='leave edge activation and the identity strip switched on afterwards')
    args = parser.parse_args()

    if not pathlib.Path(args.app).is_dir():
        print(f'❌ no app bundle at {args.app}')
        return 2
    if app_pid(args.app) is not None:
        print(f'❌ this build is already running ({args.app}) — quit it first')
        return 2
    if run('pgrep', '-x', 'KatiKati').returncode == 0:
        print('⚠️  another KatiKati instance is running; launching this build terminates it')

    binary = helper()
    if run(str(binary), 'trust').stdout.strip() != 'true':
        print('❌ the terminal is not trusted for Accessibility, so the deck cannot be read')
        return 2
    shots = pathlib.Path(args.shots) if args.shots else None
    if shots is not None:
        shots.mkdir(parents=True, exist_ok=True)

    saved = {name: pref(name) for name in PREFS}
    failures: list[str] = []

    def shot(name: str) -> None:
        if shots is not None:
            run('screencapture', '-x', str(shots / f'{name}.png'))

    def fail(step: str, detail: str) -> None:
        failures.append(step)
        print(f'  ❌ {step}: {detail}')

    try:
        for name in PREFS:
            set_pref(name, True)
        run('open', '-n', '--env', 'DOCK_DEV_SKIP_PERMISSIONS=1', args.app)
        pid = wait_pid(args.app)
        if pid is None:
            fail('launch', 'the build never appeared in the process table')
            return 1

        handle = None
        for _ in range(20):
            time.sleep(0.5)
            handle = next((row for row in windows(binary) if row[3] == 14 and row[4] == 54), None)
            if handle:
                break
        if handle is None:
            fail('handle', 'no 14x54 KatiKati window on the screen edge within 10 s')
        else:
            print(f'  ✅ handle        {handle[3]}x{handle[4]} at {handle[1]},{handle[2]} (edge {handle[0]:+})')

        point = run(str(binary), 'handle').stdout.split()
        run(str(binary), 'move', point[0], point[1])
        deck = None
        for _ in range(16):
            time.sleep(0.5)
            deck = deck_window(binary)
            if deck:
                break
        if deck is None:
            fail('open', f'no full-height deck window after hovering {point[0]},{point[1]}')
            shot('deck-missing')
        else:
            print(f'  ✅ open          {deck[3]}x{deck[4]} at {deck[1]},{deck[2]} (edge {deck[0]:+})')
            shot('deck-open')

            pid = app_pid(args.app) or pid
            tree = ax_tree(binary, pid, 'desc=Windows')
            missing = [label for label in RAIL_LABELS if f'desc={label}' not in tree]
            rail_ok = not missing
            print(f'  {"✅" if rail_ok else "❌"} rail          {len(RAIL_LABELS) - len(missing)}/{len(RAIL_LABELS)} buttons'
                  + (f' — missing {missing}' if missing else ''))
            if missing:
                failures.append('rail')
            dock_missing = []
            for label in PAGE_TAB_LABELS:
                # The dock is the only place these appear as buttons after the rail's own copies.
                if tree.count(f'desc={label}') < 2:
                    dock_missing.append(label)
            dock_ok = not dock_missing
            print(f'  {"✅" if dock_ok else "❌"} page dock     {len(PAGE_TAB_LABELS) - len(dock_missing)}/{len(PAGE_TAB_LABELS)} tabs'
                  + (f' — missing {dock_missing}' if dock_missing else ''))
            if dock_missing:
                failures.append('dock')
            for needed, label in (('desc=Pin Strip Open', 'pin toggle'), ('desc=Settings', 'Settings gear')):
                ok = needed in tree
                print(f'  {"✅" if ok else "❌"} {label:<14} accessibility label present')
                if not ok:
                    failures.append(label)

            for step, label, needles in (
                ('storage', 'Storage', ('Developer & Cache', 'Move to Trash', 'used')),
                ('downloads', 'Downloads', ('URL RESOLVER', 'IN-FLIGHT TRANSFERS', 'TORRENT HUB')),
            ):
                pid = app_pid(args.app) or pid
                spot = None
                for _ in range(4):
                    spot = find_point(binary, pid, label)
                    if spot:
                        break
                    time.sleep(0.6)
                if spot is None:
                    fail(step, f'rail button {label!r} not found in the accessibility tree')
                    continue
                hits: list[str] = []
                for attempt in range(3):
                    run(str(binary), 'click', str(spot[0]), str(spot[1]))
                    # The pane swaps behind a 20 ms stagger; poll for its text instead of reading once.
                    pane = ax_tree(binary, pid, need=None, timeout=3.0)
                    hits = [needle for needle in needles if needle in pane]
                    if hits:
                        break
                    time.sleep(0.8)
                shot(f'rail-{step}')
                ok = bool(hits)
                print(f'  {"✅" if ok else "❌"} {label:<14} click {spot[0]},{spot[1]} renders '
                      + (', '.join(repr(h) for h in hits) if hits else 'none of ' + ', '.join(needles)))
                if not ok:
                    failures.append(f'pane-{step}')

            # Collapse: the deck closes on a click outside it (DrawerPanel's global click monitor).
            # The render's bottom chevron was never implemented — the rail's foot is the Pin toggle —
            # and Escape reaches nothing because the nonactivating panel never becomes key, so
            # click-away is the collapse path this build actually ships.
            run(str(binary), 'click', '900', '500')
            closed = False
            for _ in range(12):
                time.sleep(0.4)
                if deck_window(binary) is None:
                    closed = True
                    break
            print('  ✅ collapse      click outside closed the deck' if closed
                  else '  ❌ collapse      click outside left the deck open')
            if not closed:
                failures.append('collapse')

            # Re-open through the handle (leave first: the tracking area only fires on a new enter),
            # then the identity strip's gear must open Settings.
            run(str(binary), 'move', str(int(point[0]) + 400), str(int(point[1])))
            time.sleep(0.4)
            run(str(binary), 'move', point[0], point[1])
            pid = app_pid(args.app) or pid
            reopened = None
            for _ in range(24):
                time.sleep(0.5)
                reopened = deck_window(binary)
                if reopened:
                    break
            gear = find_point(binary, pid, 'Settings') if reopened else None
            if gear is None:
                fail('settings', 'the deck did not reopen from its handle, or has no Settings gear')
            else:
                before = {row[0:2] for row in windows(binary)}
                run(str(binary), 'click', str(gear[0]), str(gear[1]))
                settings = None
                for _ in range(16):
                    time.sleep(0.5)
                    for row in windows(binary):
                        if row[3] >= 600 and row[4] >= 400 and (row[0], row[1]) not in before:
                            settings = row
                            break
                    if settings:
                        break
                if settings is None:
                    fail('settings', 'clicking the gear opened no window of at least 600x400')
                else:
                    time.sleep(0.6)
                    shot('settings-from-gear')
                    pane = ax_tree(binary, pid).lower()
                    ok = 'side deck' in pane
                    print(f'  {"✅" if ok else "❌"} Settings      {settings[3]}x{settings[4]} '
                          + ('— Side Deck pane is listed' if ok else '— no "Side Deck" row found'))
                    if not ok:
                        failures.append('settings-content')
    finally:
        # Only the build this script started: another worktree's KatiKati must survive this run.
        ours = app_pid(args.app)
        if ours is not None:
            run('kill', '-TERM', str(ours))
            time.sleep(0.8)
        if not args.keep_prefs:
            for name, old in saved.items():
                if old is None:
                    run('defaults', 'delete', DOMAIN, name)
                else:
                    run('defaults', 'write', DOMAIN, name, '-bool', old)

    if failures:
        print('❌ failed: ' + ', '.join(failures))
        return 1
    print('✅ the deck opens from its handle, its rail swaps panes, the gear opens Settings, click-away collapses it')
    return 0


if __name__ == '__main__':
    sys.exit(main())
