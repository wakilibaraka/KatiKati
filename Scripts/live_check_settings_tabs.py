#!/usr/bin/env python3
"""Smoke test: launched on each Settings page, the app opens a Settings window. Nothing more — there
is no height or fit rule, and it does not read which page is showing (use --shots and look).

Usage:
    python3 Scripts/live_check_settings_tabs.py --app /path/to/KatiKati.app [--shots DIR]

A manual live-check aid (like Scripts/build_and_run.sh), not a CI step. The tab list is read from
App/Scenes/SettingsTab.swift, so a new page is covered without editing this file. For each tab it
launches the app with DOCK_OPEN_SETTINGS=<tab> (the debug switch in Core/Support/DebugSwitch.swift),
waits for the window, asks System Events for the standard-window sizes (the terminal needs
Accessibility access), optionally screenshots, then quits the app.

The app terminates other running instances at launch, so this refuses to run while KatiKati is open.

Exit code: 0 every page opened a window; 1 a page did not; 2 setup problem (app running, no .app).
"""
from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIN_W, MIN_H = 600, 400  # a hair under SettingsMetrics.minWindowWidth/Height (640x440)


def tabs() -> list[str]:
    src = (ROOT / 'App/Scenes/SettingsTab.swift').read_text().split('var title')[0]
    return re.findall(r'^    case (\w+)\s*$', src, re.M)


def run(*cmd: str) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30)


def window_sizes() -> list[tuple[int, int]]:
    # Prefer CGWindowList layer-0 KatiKati windows (works without terminal Accessibility grant).
    helper = ROOT / 'build/live-check/clickwin'
    if helper.is_file():
        sizes = []
        for line in run(str(helper), 'windows').stdout.splitlines():
            parts = line.split('|')
            if len(parts) == 4 and parts[1] == 'KatiKati' and parts[2] == '0':
                coords = [int(n) for n in parts[3].split(',')]
                if len(coords) == 4:
                    sizes.append((coords[2], coords[3]))
        if sizes:
            return sizes
    # Fallback: System Events AXStandardWindow (needs Accessibility on the terminal).
    script = ('tell application "System Events" to tell (first process whose name is "KatiKati") '
              'to get size of every window whose subrole is "AXStandardWindow"')
    out = run('osascript', '-e', script).stdout
    nums = [int(n) for n in re.findall(r'\d+', out)]
    return list(zip(nums[0::2], nums[1::2]))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True, help='path to the built KatiKati.app')
    parser.add_argument('--shots', help='directory for one screenshot per tab (created if needed)')
    args = parser.parse_args()

    if not pathlib.Path(args.app).is_dir():
        print(f'❌ no app bundle at {args.app}')
        return 2
    if run('pgrep', '-x', 'KatiKati').returncode == 0:
        print('❌ KatiKati is already running — quit it first (the app would kill it at launch)')
        return 2
    shots = pathlib.Path(args.shots) if args.shots else None
    if shots is not None:
        shots.mkdir(parents=True, exist_ok=True)

    failures = []
    for tab in tabs():
        run('open', '-n', '--env', f'DOCK_OPEN_SETTINGS={tab}', '--env', 'DOCK_DEV_SKIP_PERMISSIONS=1', args.app)
        sizes = []
        ok = False
        # AppDelegate presents the page 3 s after the strip starts (DOCK_OPEN_SETTINGS), then a cold
        # launch adds its own time on a loaded machine; 7 s (the old 14 x 0.5 s) was short enough to
        # fail heavy pages such as Widgets. Poll for 20 s and stop as soon as a window is there.
        for _ in range(40):
            time.sleep(0.5)
            sizes = window_sizes()
            if any(w >= MIN_W and h >= MIN_H for w, h in sizes):
                ok = True
                break
        if ok and shots is not None:
            run('screencapture', '-x', str(shots / f'{tab}.png'))
        print(f'  {"✅" if ok else "❌"} {tab:<18} windows: {sizes or "none"}', flush=True)
        if not ok:
            failures.append(tab)
        run('pkill', '-x', 'KatiKati')
        for _ in range(10):
            if run('pgrep', '-x', 'KatiKati').returncode != 0:
                break
            time.sleep(0.2)
    if failures:
        print('❌ these pages did not open a window: ' + ', '.join(failures))
        return 1
    print(f'✅ all {len(tabs())} Settings pages opened a window')
    return 0


if __name__ == '__main__':
    sys.exit(main())
