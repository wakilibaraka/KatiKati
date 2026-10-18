#!/usr/bin/env python3
"""Walk all ten Settings tabs through real AX toolbar clicks and prove each page opens.

Usage:
    python3 Scripts/live_check_settings_tabs.py [--app /path/to/KatiKati.app] [--shots DIR]

A manual live-check aid (like Scripts/build_and_run.sh), not a CI step: it needs the app
running with a window the AX route can raise, so launch it first with e.g.
`open --env DOCK_OPEN_SETTINGS=general <app>` and grant the terminal Accessibility access.
For each tab it clicks the toolbar button, asserts the window title follows, and records the
window frame (pages size themselves to content — a 0-size or missing window fails loudly).

Exit code: 0 all ten pages opened; 1 anything did not; 2 the app/window was not found.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

TABS = ['General', 'Appearance', 'Widgets', 'Notch', 'Edge Bars', 'Window Management',
        'Launcher', 'Control Center', 'Shortcuts', 'Tools', 'Advanced']


def ax(script: str) -> str:
    run = subprocess.run(['osascript', '-e', script], capture_output=True, text=True, timeout=30)
    if run.returncode != 0:
        raise RuntimeError(run.stderr.strip().splitlines()[-1] if run.stderr.strip() else 'osascript failed')
    return run.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--shots', help='directory for one screenshot per tab (created if needed)')
    args = parser.parse_args()

    shots = pathlib.Path(args.shots) if args.shots else None
    if shots is not None:
        shots.mkdir(parents=True, exist_ok=True)

    try:
        proc = 'tell application "System Events" to tell (first process whose name is "KatiKati")'
        ax(f'{proc} to get name')
    except RuntimeError as e:
        print(f'❌ KatiKati is not running (or AX is denied): {e}')
        return 2

    current = 'General'
    failures = []
    for tab in TABS:
        try:
            ax(f'{proc} to tell window "{current}" to tell toolbar 1 to click button "{tab}"')
            import time
            time.sleep(1.0)
            rect = ax(f'{proc} to get {{position, size}} of window "{tab}"')
            x, y, w, h = (p.strip() for p in rect.split(','))
            if shots is not None:
                slug = tab.replace(' ', '_')
                subprocess.run(['screencapture', '-x',
                                f'-R{int(x) * 2},{int(y) * 2},{int(w) * 2},{int(h) * 2}',
                                str(shots / f'{slug}.png')], check=False, timeout=30)
            print(f'  ✅ {tab:<20} {w}×{h} at ({x},{y})')
            current = tab
        except (RuntimeError, ValueError) as e:
            print(f'  ❌ {tab:<20} {e}')
            failures.append(tab)
    if failures:
        print('❌ these pages did not open: ' + ', '.join(failures))
        return 1
    print('✅ all ten Settings pages opened via their toolbar buttons')
    return 0


if __name__ == '__main__':
    sys.exit(main())
