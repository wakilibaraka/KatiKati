#!/usr/bin/env python3
"""Drive every dock layout preset, killing and relaunching the app between them.

Why this exists: the dock's width used to be solved per mode (Full Width ran edge to edge and
poured the spare width into section gaps), so a spacing change could only be proven by looking at a
running dock in each mode. This script switches `com.katikati.layout.mode`, relaunches the built app,
reads the dock window that the WindowServer reports, and screenshots it.

    python3 Scripts/live_check_dock_layout.py --app /tmp/katikati-dd-cc/Build/Products/Debug/KatiKati.app

What it asserts:
  * every preset produces a dock window of bar height on screen;
  * no preset draws a plate wider than the usable screen (screen minus side margins);
  * Full Width (`.windows`) is no longer the old full-bleed bar: its plate is narrower than the
    usable width, because the plate now hugs its content.

Exit 0 when every preset passed, 1 on a failed assertion, 2 for a setup problem. The script only
kills the processes of the bundle it was given.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import json
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / 'build/live-check'
DOMAIN = 'com.katikati.app'
MODE_KEY = 'com.katikati.layout.mode'
MODES = ['windows', 'split3', 'split4', 'split5', 'centered']
# Registered in Core/Support/DebugSwitch.swift: the strip's chip-frame dump.
DebugSwitchTrigger = 'DOCK_CHIP_FRAMES_OUT'

HELPER_SWIFT = r'''
import AppKit
import CoreGraphics

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "windows":
    let rows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    for row in rows {
        guard (row[kCGWindowOwnerName as String] as? String) == "KatiKati",
              let layer = row[kCGWindowLayer as String] as? Int,
              let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
              let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double else { continue }
        print("\(layer)|\(Int(x))|\(Int(y))|\(Int(w))|\(Int(h))")
    }
case "screen":
    let frame = NSScreen.screens.first?.frame ?? .zero
    print("\(Int(frame.width))|\(Int(frame.height))")
default:
    exit(2)
}
'''


def run(*cmd: str, timeout: float = 60) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def helper() -> pathlib.Path:
    binary = WORK / 'dockprobe'
    source = WORK / 'dockprobe.swift'
    WORK.mkdir(parents=True, exist_ok=True)
    if not binary.exists() or not source.exists() or source.read_text() != HELPER_SWIFT:
        source.write_text(HELPER_SWIFT)
        built = run('xcrun', 'swiftc', '-O', str(source), '-o', str(binary), timeout=180)
        if built.returncode != 0:
            raise RuntimeError(f'swiftc failed:\n{built.stderr}')
    return binary


def pids(app: str) -> list[int]:
    exe = str(pathlib.Path(app).resolve() / 'Contents/MacOS/KatiKati')
    out = run('pgrep', '-f', exe)
    return [int(n) for n in out.stdout.split()] if out.returncode == 0 else []


def windows(binary: pathlib.Path) -> list[tuple[int, int, int, int, int]]:
    rows = []
    for line in run(str(binary), 'windows').stdout.splitlines():
        parts = [int(n) for n in line.split('|')]
        if len(parts) == 5:
            rows.append(tuple(parts))
    return rows


def dock_window(rows, screen_h: int):
    """The dock: a bar-height KatiKati window in the lower half of the screen, not a panel."""
    best = None
    for layer, x, y, w, h in rows:
        if w >= 180 and 40 <= h <= 100 and y >= screen_h * 0.5:
            if best is None or w > best[3]:
                best = (layer, x, y, w, h)
    return best


def set_mode(mode: str) -> None:
    run('defaults', 'write', DOMAIN, MODE_KEY, mode)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True)
    parser.add_argument('--shots', help='directory for one screenshot per preset')
    args = parser.parse_args()

    if not pathlib.Path(args.app).is_dir():
        print(f'❌ no app bundle at {args.app}')
        return 2
    binary = helper()
    screen = run(str(binary), 'screen').stdout.strip().split('|')
    screen_w = int(screen[0]) if len(screen) == 2 else 1440
    screen_h = int(screen[1]) if len(screen) == 2 else 1112
    shots = pathlib.Path(args.shots) if args.shots else None
    if shots:
        shots.mkdir(parents=True, exist_ok=True)

    # The app writes its own settings on quit, so the mode is only written once it is fully gone.
    for stale in pids(args.app):
        run('kill', '-TERM', str(stale))
    for _ in range(20):
        if not pids(args.app):
            break
        time.sleep(0.4)
    time.sleep(0.6)

    failures: list[str] = []
    usable = screen_w - 24          # the bar never runs past the side margins
    frames_file = WORK / 'frames.json'
    for mode in MODES:
        set_mode(mode)
        stored = run('defaults', 'read', DOMAIN, MODE_KEY).stdout.strip()
        if stored != mode:
            print(f'  ❌ {mode:<9} defaults kept {stored!r} instead of the requested mode')
            failures.append(mode)
            continue
        frames_file.unlink(missing_ok=True)
        # The strip publishes its own chip frames: that is the only measurement that proves the
        # plate hugs the *drawn* content, and it keeps the shot and the number on the same window.
        run('launchctl', 'setenv', DebugSwitchTrigger, str(frames_file))
        run('open', '-n', args.app)
        time.sleep(5.0)
        run('launchctl', 'unsetenv', DebugSwitchTrigger)
        try:
            frames = json.loads(frames_file.read_text())
        except (OSError, json.JSONDecodeError):
            print(f'  ❌ {mode:<9} the strip published no chip frames')
            failures.append(mode)
            for owned in pids(args.app):
                run('kill', '-TERM', str(owned))
            continue

        chips = sorted(frames['chips'], key=lambda c: c['x'])
        span = (min(c['x'] for c in chips), max(c['x'] + c['w'] for c in chips))
        gaps = [b['x'] - (a['x'] + a['w']) for a, b in zip(chips, chips[1:])]
        pads = (span[0], frames['rootWidth'] - span[1])
        # Any of the strip's windows can be the widest one (the glass background panel is 40 pt
        # wider than its content), so match the published strip frame instead of guessing.
        window = None
        for attempt in range(4):
            best = None
            for row in windows(binary):
                _, x, y, w, h = row
                if y < screen_h * 0.5:
                    continue
                # Either the content window or its glass background (20 pt wider each side).
                score = min(abs(w - frames['rootWidth']) + abs(x - frames['rootLeft']),
                            abs(w - (frames['rootWidth'] + 40)) + abs(x - (frames['rootLeft'] - 20)))
                if score <= 6 and (best is None or score < best):
                    best, window = score, row
            if window:
                break
            time.sleep(0.6)
        problems = []
        if max(pads) > 10:
            problems.append(f'trailing/leading dead plate {pads[0]:.0f}/{pads[1]:.0f} pt')
        if gaps and max(gaps) > 3.5:
            problems.append(f'inner gap {max(gaps):.1f} pt above the 3 pt section spacing')
        if window is None:
            problems.append('no window matches the published strip width')
        if span[1] - span[0] > frames['rootWidth'] + 4:
            problems.append(f'content {span[1] - span[0]:.0f} pt overflows the plate')
        if frames['rootWidth'] > usable:
            problems.append(f'{frames["rootWidth"]:.0f} pt wider than the {usable} pt usable screen')
        if mode == 'windows' and frames['rootWidth'] >= usable - 1:
            problems.append('Full Width is still the full-bleed bar')
        shot = ''
        if shots and window:
            time.sleep(0.8)          # let the strip finish its spring before the shot
            _, x, y, w, h = window
            pad = 10
            run('screencapture', '-x', str(shots / f'dock-{mode}.png'))
            run('screencapture', '-x', '-R',
                f'{max(0, x - pad)},{max(0, y - pad)},{w + 2 * pad},{h + 2 * pad}',
                str(shots / f'plate-{mode}.png'))
            shot = f' → {shots / f"plate-{mode}.png"}'
        ok = not problems
        detail = (f'plate {frames["rootWidth"]:.0f} content {span[1] - span[0]:.0f} '
                  f'pads {pads[0]:.0f}/{pads[1]:.0f} maxgap {max(gaps) if gaps else 0:.1f}')
        print(f'  {"✅" if ok else "❌"} {mode:<9} {detail}'
              + (f' — {"; ".join(problems)}' if problems else '') + shot)
        if not ok:
            failures.append(mode)
        for owned in pids(args.app):
            run('kill', '-TERM', str(owned))
        time.sleep(0.8)

    if failures:
        print('❌ failed: ' + ', '.join(failures))
        return 1
    print('✅ every preset drew a content-sized dock; the bar never ran past the margins')
    return 0


if __name__ == '__main__':
    sys.exit(main())
