#!/usr/bin/env python3
"""Cycle every tiling preset over four staged TextEdit windows and measure what each one did.

Why this exists: the nine-preset pass was improvised in `/tmp/tiling-live/preset_loop.py` once per
session and lost with the temp directory, so every pass rediscovered the staging, the floating-app
list and the frame reader. This is that harness in the repo, gated the same way the other live checks
are. It is a manual live-check aid (like `Scripts/live_check_chip.py`), not a CI step.

    python3 Scripts/live_check_tiling_presets.py
    python3 Scripts/live_check_tiling_presets.py --preset grid,monocle --shots build/live-check/tiling
    python3 Scripts/live_check_tiling_presets.py --settle 12 --screen 1512x982

What it does, in order:

 1. runs `Scripts/build_and_run.sh --check-signing` and refuses to continue unless it passes (exit 3).
    An ad-hoc build left behind by `xcodebuild test` runs untrusted: nothing moves, and every row
    below would report the *previous* preset's frames as if the preset had done nothing. Use
    `Scripts/build_and_run.sh --test` (which re-signs on its way out) or `--resign` first.
 2. turns tiling on, marks the apps the strip normally holds as floating so only the staged windows
    are candidates, and stages four 580x380 TextEdit windows via AppleScript (two columns, two rows).
 3. for each preset writes `com.katikati.tiling.preset`, relaunches the app, waits `--settle` seconds
    and reads the on-screen windows from CGWindowList (no Accessibility grant needed for that part).
 4. prints per preset: how many windows, pairwise overlaps, union coverage of the screen, off-screen
    area and whether every window is fully on screen. Writes `preset-results.json` and one screenshot
    per preset into `--out` (default `build/live-check/tiling`, gitignored).

The list of presets is read from `Core/Support/TilingLayout.swift` (`TilingLayoutPreset`), so a new
preset is covered without editing this file. `--preset` takes a comma-separated subset.

Exit codes: 0 every preset moved something and left four windows on screen; 1 a preset left the staged
geometry exactly as it was — with every preset unchanged that is the "no preset moved a single window"
failure, which almost always means Accessibility or the tiling switch, not the layout; 2 a setup
problem (no app bundle, app already running, fewer than four staged windows); 3 the signing gate refused.

Side effects that outlive the run: `com.katikati.tiling.enabled`, `com.katikati.tiling.floatingApps`
and `com.katikati.tiling.preset` keep the values written here, four empty TextEdit documents stay open,
and the app is left running on the last preset.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / 'build/live-check'
DEFAULT_APP = ROOT / 'build/DerivedData/Build/Products/Debug/KatiKati.app'
DEFAULT_OUT = WORK / 'tiling'
STAGED = 4
FLOATING = """ai.storyteller.deckcraft=float
ai.storyteller.wordcraft=float
com.apple.ActivityMonitor=float
com.apple.Dictionary=float
com.apple.FontBook=float
com.apple.MobileSMS=float
com.apple.Music=float
com.apple.Notes=float
com.apple.Preview=float
com.apple.QuickTimePlayerX=float
com.apple.Safari=float
com.apple.Stickies=float
com.apple.Terminal=float
com.apple.finder=float
com.apple.findmy=float
com.apple.freeform=float
com.apple.iCal=float
com.apple.reminders=float
com.apple.systempreferences=float
com.freebuff.desktop=float
com.github.th-ch.youtube-music=float
com.google.Chrome=float
net.whatsapp.WhatsApp=float"""

HELPER_SWIFT = '''
import AppKit
import CoreGraphics

// `tilingwin screen` prints the main display's size in points; the frame list is the default mode.
if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "screen" {
    let bounds = CGDisplayBounds(CGMainDisplayID())
    print("\(Int(bounds.width))x\(Int(bounds.height))")
    exit(0)
}

// Id|owner|layer|x,y,w,h for every on-screen window. Layer 0 + owner is enough to isolate the
// staged documents from panels, the menu bar and the strip's own plates.
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
for window in windows {
    guard let id = window[kCGWindowNumber as String] as? Int,
          let owner = window[kCGWindowOwnerName as String] as? String,
          let layer = window[kCGWindowLayer as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
          let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double
    else { continue }
    print("\\(id)|\\(owner)|\\(layer)|\\(Int(x)),\\(Int(y)),\\(Int(w)),\\(Int(h))")
}
'''


def run(*cmd: str, timeout: float = 60) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def helper() -> pathlib.Path:
    """Compile the window reader once, under the gitignored build/ directory."""
    binary, source = WORK / 'tilingwin', WORK / 'tilingwin.swift'
    WORK.mkdir(parents=True, exist_ok=True)
    if binary.exists() and source.exists() and binary.stat().st_mtime >= source.stat().st_mtime:
        return binary
    source.write_text(HELPER_SWIFT)
    built = run('xcrun', 'swiftc', '-O', str(source), '-o', str(binary), timeout=120)
    if built.returncode != 0:
        raise SystemExit(f'swiftc failed:\n{built.stderr}')
    return binary


def presets() -> list[str]:
    """Every case of `TilingLayoutPreset`, read from the enum so a new preset needs no edit here."""
    src = (ROOT / 'Core/Support/TilingLayout.swift').read_text()
    start = src.index('enum TilingLayoutPreset')
    block = src[start:src.index('\n    var ', start)]
    names = re.findall(r'^    case (\w+)\s*$', block, re.M)
    if not names:
        raise SystemExit('❌ could not read TilingLayoutPreset cases from Core/Support/TilingLayout.swift')
    return names


def screen_size(override: str, binary: pathlib.Path) -> tuple[int, int]:
    """Main display size in points: the layout engine works in points, not backing pixels."""
    if override:
        w, h = override.lower().split('x')
        return int(w), int(h)
    out = run(str(binary), 'screen').stdout.strip()
    if re.fullmatch(r'\d+x\d+', out):
        width, height = out.split('x')
        return int(width), int(height)
    raise SystemExit('❌ could not read the main display size; pass --screen WxH')


def signing_gate() -> None:
    result = run(str(ROOT / 'Scripts/build_and_run.sh'), '--check-signing')
    if result.returncode != 0:
        print(result.stderr.strip() or result.stdout.strip())
        raise SystemExit(3)
    print(result.stdout.strip())


def frames(binary: pathlib.Path) -> list[dict]:
    result = []
    for line in run(str(binary)).stdout.splitlines():
        parts = line.split('|')
        if len(parts) != 4:
            continue
        pid, owner, layer, bounds = parts
        if owner != 'TextEdit' or layer != '0':
            continue
        x, y, w, h = (int(n) for n in bounds.split(','))
        result.append(dict(pid=int(pid), x=x, y=y, w=w, h=h))
    # Deterministic order: top-to-bottom, left-to-right.
    result.sort(key=lambda r: (r['y'], r['x']))
    return result


def intersection(a: dict, b: dict) -> int:
    x1, y1 = max(a['x'], b['x']), max(a['y'], b['y'])
    x2 = min(a['x'] + a['w'], b['x'] + b['w'])
    y2 = min(a['y'] + a['h'], b['y'] + b['h'])
    return max(0, x2 - x1) * max(0, y2 - y1)


def union_area(rects: list[dict]) -> int:
    if not rects:
        return 0
    xs = sorted({r['x'] for r in rects} | {r['x'] + r['w'] for r in rects})
    total = 0
    for i in range(len(xs) - 1):
        x1, x2 = xs[i], xs[i + 1]
        spans = sorted((r['y'], r['y'] + r['h']) for r in rects if r['x'] <= x1 and r['x'] + r['w'] >= x2)
        covered, cur = 0, None
        for lo, hi in spans:
            if cur is None:
                cur = [lo, hi]
            elif lo <= cur[1]:
                cur[1] = max(cur[1], hi)
            else:
                covered += cur[1] - cur[0]
                cur = [lo, hi]
        if cur:
            covered += cur[1] - cur[0]
        total += covered * (x2 - x1)
    return total


def outside_area(r: dict, screen: tuple[int, int]) -> int:
    """Area of a window that hangs off the screen, overhanging both axes counted once."""
    width, height = screen
    x_over = max(0, -r['x']) + max(0, r['x'] + r['w'] - width)
    y_over = max(0, -r['y']) + max(0, r['y'] + r['h'] - height)
    return x_over * r['h'] + y_over * r['w']


def measure(binary: pathlib.Path, screen: tuple[int, int]) -> dict:
    width, height = screen
    fs = frames(binary)
    overlaps = [dict(pair=[i, j], area=area, frames=[fs[i], fs[j]])
                for i in range(len(fs)) for j in range(i + 1, len(fs))
                if (area := intersection(fs[i], fs[j])) > 16]
    outside = sum(outside_area(r, screen) for r in fs)
    return dict(
        frames=fs,
        overlaps=overlaps,
        union=union_area(fs),
        coverage=round(union_area(fs) / (width * height), 4),
        sumArea=sum(r['w'] * r['h'] for r in fs),
        offscreen=outside,
        allOnScreen=all(0 <= r['x'] and 0 <= r['y'] and r['x'] + r['w'] <= width and r['y'] + r['h'] <= height
                        for r in fs),
    )


def stage_windows() -> None:
    script = '''
    tell application "TextEdit"
        activate
        make new document with properties {text:""}
        set bounds of window 1 to {120, 140, 700, 520}
        make new document with properties {text:""}
        set bounds of window 1 to {760, 140, 1340, 520}
        make new document with properties {text:""}
        set bounds of window 1 to {120, 620, 700, 1000}
        make new document with properties {text:""}
        set bounds of window 1 to {760, 620, 1340, 1000}
    end tell
    '''
    run('osascript', '-e', script)


def geometry(rows: list[dict]) -> list[tuple[int, int, int, int]]:
    return [(f['x'], f['y'], f['w'], f['h']) for f in rows]


def untouched_presets(results: dict, staged: list[dict]) -> list[str]:
    """Presets that left the staged geometry exactly as it was: the shape a lost grant or a switched-off
    tiling engine takes, which would otherwise read as nine quiet, plausible rows."""
    return [name for name in results if geometry(results[name]['frames']) == geometry(staged)]


def main() -> int:
    parser = argparse.ArgumentParser(description='Measure every tiling preset over four staged windows.')
    parser.add_argument('--app', default=str(DEFAULT_APP), help='path to the built KatiKati.app')
    parser.add_argument('--preset', default='', help='comma-separated subset of presets (default: all)')
    parser.add_argument('--out', default=str(DEFAULT_OUT), help='directory for results and screenshots')
    parser.add_argument('--shots', action='store_true', help='also screenshot each preset')
    parser.add_argument('--settle', type=float, default=9.0, help='seconds to wait after each launch')
    parser.add_argument('--screen', default='', help='screen size in points as WxH (default: read it)')
    args = parser.parse_args()

    if not pathlib.Path(args.app).is_dir():
        print(f'❌ no app bundle at {args.app}')
        return 2
    if run('pgrep', '-x', 'KatiKati').returncode == 0:
        print('❌ KatiKati is already running — quit it first (the app terminates other instances)')
        return 2

    signing_gate()
    binary = helper()
    screen = screen_size(args.screen, binary)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    run('defaults', 'write', 'com.katikati.app', 'com.katikati.tiling.enabled', '-bool', 'true')
    run('defaults', 'write', 'com.katikati.app', 'com.katikati.tiling.floatingApps', '-string', FLOATING)
    run('osascript', '-e', 'tell application "TextEdit" to close every document saving no')
    time.sleep(0.6)
    stage_windows()
    time.sleep(1.0)
    staged = frames(binary)
    if len(staged) != STAGED:
        print(f'❌ expected {STAGED} staged TextEdit windows, saw {len(staged)} '
              '— is TextEdit allowed to open documents?')
        return 2
    (out / 'staged-windows.json').write_text(json.dumps(staged, indent=2))
    print(f'staged TextEdit windows: {len(staged)} on {screen[0]}x{screen[1]}')

    known = presets()
    wanted = [name.strip() for name in args.preset.split(',') if name.strip()] or known
    missing = [name for name in wanted if name not in known]
    if missing:
        print(f'❌ not a preset: {", ".join(missing)} — have: {", ".join(known)}')
        return 2

    results = {}
    for name in wanted:
        run('defaults', 'write', 'com.katikati.app', 'com.katikati.tiling.preset', '-string', name)
        run('pkill', '-x', 'KatiKati')
        time.sleep(1.0)
        run('open', args.app)
        time.sleep(args.settle)
        data = measure(binary, screen)
        results[name] = data
        if args.shots:
            run('screencapture', '-x', str(out / f'preset-{name}.png'))
        print(f"{name:<12} windows={len(data['frames'])} overlaps={len(data['overlaps'])} "
              f"coverage={data['coverage']:.3f} offscreen={data['offscreen']} onscreen={data['allOnScreen']}")
        for f in data['frames']:
            print(f"    {f['x']:>4},{f['y']:>4} {f['w']:>4}x{f['h']:<4}")
    (out / 'preset-results.json').write_text(json.dumps(results, indent=2))

    # A preset that leaves every window exactly where the staged set was did not run at all. That is
    # the shape a lost grant (or tiling switched off) takes, so say so instead of reporting nine quiet,
    # plausible rows.
    untouched = untouched_presets(results, staged)
    if untouched and len(untouched) == len(results):
        print('❌ no preset moved a single window: check Accessibility '
              '(Scripts/build_and_run.sh --check-signing) and the tiling switch, not the layout')
        return 1
    bad = [name for name in results if not results[name]['allOnScreen']]
    if untouched or bad:
        if untouched:
            print('❌ these presets left the windows exactly where they were: ' + ', '.join(untouched))
        if bad:
            print('❌ these presets put a window off screen: ' + ', '.join(bad))
        return 1
    print(f'✅ {len(results)} presets moved all {STAGED} windows, all on screen; '
          f'results in {out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
