#!/usr/bin/env python3
"""Click strip chips by name and screenshot the result — the repeatable form of the live chip pass.

Why this exists (livecheck slice 6): every earlier pass improvised its own click and screenshot
helpers in `/tmp`, so the next pass had to rediscover the strip's coordinates by hand and could not
reproduce a finding. This script asks the app for the coordinates instead.

    python3 Scripts/live_check_chip.py --app build/DerivedData/Build/Products/Debug/KatiKati.app \
        --chip pop,shelf,trash --shots build/live-check/shots

How it works: the app writes its chip registry to the file named by `DOCK_CHIP_FRAMES_OUT`
(`DebugSwitch.chipFramesOut`, written from `DockStripView.dumpChipFramesIfRequested`). Each chip's
frame is in the strip's own space, and the registry carries the strip root in CG screen coordinates,
so the click point is `root + frame.mid` with no geometry in this file. Clicks are real HID events
(`CGEvent`), not `AXPress`.

What it prints: for each chip, the window set before and after the click and whether it changed —
the same evidence the pass report quotes. Exit code 0 when every chip was clicked and screenshotted,
1 when a chip was missing from the registry, 2 for a setup problem (app running, no .app, no frames).

A manual live-check aid, not a CI step. It deliberately clicks *every* matching chip once, so pass a
`--chip` filter when you only want the pop.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / 'build/live-check'
HELPER_SWIFT = '''
import AppKit
import CoreGraphics

let args = CommandLine.arguments
let source = CGEventSource(stateID: .hidSystemState)

func windows() -> [[String: Any]] {
    (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
}

switch args.count > 1 ? args[1] : "" {
case "click":
    let point = CGPoint(x: Double(args[2]) ?? 0, y: Double(args[3]) ?? 0)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(120_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(70_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
case "windows":
    // id|owner|layer|x,y,w,h — the fields the pass report quotes.
    for window in windows() {
        guard let id = window[kCGWindowNumber as String] as? Int,
              let owner = window[kCGWindowOwnerName as String] as? String,
              let layer = window[kCGWindowLayer as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
              let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double
        else { continue }
        print("\\(id)|\\(owner)|\\(layer)|\\(Int(x)),\\(Int(y)),\\(Int(w)),\\(Int(h))")
    }
case "front":
    print(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-")
default:
    print("usage: helper click X Y | windows | front")
    exit(2)
}
'''


def run(*cmd: str, timeout: float = 30) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def helper() -> pathlib.Path:
    """Compile the click / window-list helper once, under the gitignored build/ directory."""
    binary = WORK / 'clickwin'
    source = WORK / 'clickwin.swift'
    WORK.mkdir(parents=True, exist_ok=True)
    if binary.exists() and source.exists() and binary.stat().st_mtime >= source.stat().st_mtime:
        return binary
    source.write_text(HELPER_SWIFT)
    built = run('xcrun', 'swiftc', '-O', str(source), '-o', str(binary), timeout=120)
    if built.returncode != 0:
        raise RuntimeError(f'swiftc failed:\n{built.stderr}')
    return binary


def window_set(binary: pathlib.Path) -> dict[int, str]:
    rows = {}
    for line in run(str(binary), 'windows').stdout.splitlines():
        parts = line.split('|')
        if len(parts) == 4:
            rows[int(parts[0])] = f'{parts[1]} L{parts[2]} {parts[3]}'
    return rows


def front(binary: pathlib.Path) -> str:
    return run(str(binary), 'front').stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True, help='path to the built KatiKati.app')
    parser.add_argument('--chip', default='',
                        help='comma-separated chip ids (pop, trash, shelf, a bundle id, …); default every chip')
    parser.add_argument('--shots', help='directory for one screenshot pair per chip')
    parser.add_argument('--keep', action='store_true', help='leave the app running afterwards')
    args = parser.parse_args()

    if not pathlib.Path(args.app).is_dir():
        print(f'❌ no app bundle at {args.app}')
        return 2
    if run('pgrep', '-x', 'KatiKati').returncode == 0:
        print('❌ KatiKati is already running — quit it first (the app terminates other instances)')
        return 2

    binary = helper()
    frames_file = WORK / 'frames.json'
    frames_file.unlink(missing_ok=True)
    shots = pathlib.Path(args.shots) if args.shots else None
    if shots is not None:
        shots.mkdir(parents=True, exist_ok=True)

    run('open', '-n', '--env', f'DOCK_CHIP_FRAMES_OUT={frames_file}',
        '--env', 'DOCK_DEV_SKIP_PERMISSIONS=1', args.app)
    frames = None
    for _ in range(40):
        time.sleep(0.5)
        try:
            frames = json.loads(frames_file.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if frames.get('chips'):
            break
    if not frames or not frames.get('chips'):
        print(f'❌ the strip never wrote {frames_file} — is DOCK_CHIP_FRAMES_OUT plumbed through `open`?')
        return 2

    def point_of(name: str):
        """The chip's click point, re-read from the app every single time.

        The strip re-centres while a plate opens and closes, so a coordinate cached at launch
        points at a neighbour a few clicks later: the first all-chip pass clicked WhatsApp and
        opened the shelf's plate, then clicked where the shelf had been and hit nothing.
        """
        nonlocal frames
        try:
            current = json.loads(frames_file.read_text())
            if current.get('chips'):
                frames = current
        except (OSError, json.JSONDecodeError):
            pass
        chip = next((c for c in frames['chips'] if c['id'] == name), None)
        if chip is None:
            return None
        return (frames['rootLeft'] + chip['x'] + chip['w'] / 2,
                frames['rootTop'] + chip['y'] + chip['h'] / 2, chip)

    chips = {chip['id']: chip for chip in frames['chips']}
    wanted = [name.strip() for name in args.chip.split(',') if name.strip()] or list(chips)
    missing = [name for name in wanted if name not in chips]
    if missing:
        print(f'❌ not in the registry: {", ".join(missing)} — have: {", ".join(sorted(chips))}')
        return 1

    failures = []
    for name in wanted:
        point = point_of(name)
        if point is None:
            print(f'  ❌ {name:<22} left the registry after a reflow')
            failures.append(name)
            continue
        x, y, chip = point
        before, before_front = window_set(binary), front(binary)
        if shots is not None:
            run('screencapture', '-x', str(shots / f'{name}-before.png'))
        run(str(binary), 'click', f'{x:.1f}', f'{y:.1f}')
        time.sleep(1.3)
        if shots is not None:
            run('screencapture', '-x', str(shots / f'{name}-after.png'))
        after, after_front = window_set(binary), front(binary)
        appeared = [after[i] for i in after.keys() - before.keys()]
        vanished = [before[i] for i in before.keys() - after.keys()]
        fired = bool(appeared or vanished) or before_front != after_front
        print(f'  {"✅" if fired else "❌"} {name:<22} click {x:.0f},{y:.0f} '
              f'zone={chip["zone"]:<9} appeared={appeared or "-"} vanished={vanished or "-"} '
              f'front={before_front}→{after_front}')
        if not fired:
            failures.append(name)
        # A chip that opened something must close it, or the next click lands on the plate —
        # and it must close at the chip's *current* point, for the reason above.
        closing = point_of(name)
        if closing is not None:
            run(str(binary), 'click', f'{closing[0]:.1f}', f'{closing[1]:.1f}')
        time.sleep(0.9)

    if not args.keep:
        run('osascript', '-e', 'tell application "KatiKati" to quit')
        time.sleep(1.2)
        run('pkill', '-x', 'KatiKati')  # safe: we refused to start with one running
    if failures:
        print('❌ these chips did not fire: ' + ', '.join(failures))
        return 1
    print(f'✅ {len(wanted)} chips fired; frames from {frames_file}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
