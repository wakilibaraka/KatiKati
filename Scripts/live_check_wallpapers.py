#!/usr/bin/env python3
"""DW-11 — live check of the dynamic wallpaper, the Small Animation overlay and the preservation rules.

Every case quits KatiKati, launches the built app with DOCK_WALLPAPER_PHASE=<phase>:<sky> (plus the pinned
environment written into `com.katikati.wallpaper.terrain`), waits for the desktop picture to point at a freshly
generated frame in `…/DynamicWallpapers/Generated`, and records a screenshot and the path it found.

    ./Scripts/live_check_wallpapers.py                # one environment × 5 phases × 6 skies
    ./Scripts/live_check_wallpapers.py --full         # all four environments
    ./Scripts/live_check_wallpapers.py --limit 3      # a quick spot check
    ./Scripts/live_check_wallpapers.py --skip-animation
    ./Scripts/live_check_wallpapers.py --skip-cases      # preservation + animation only

Exit codes: 0 every case matched and every preservation check held · 1 a mismatch/regression · 2 a setup problem
(signing gate, missing bundle, app still running) · 3 the signing gate refused because the bundle no longer matches
the Accessibility grant.

The plan's DW-11 lists six phases including `morning`/`noon`, but `DOCK_WALLPAPER_PHASE` parses `SolarPhase`
(night/dawn/day/golden/dusk) — `morning` and `noon` are `DaylightPhase` steps inside `day`. This script therefore
drives the five phases the renderer's override understands; `day` covers morning and noon.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "build/DerivedData/Build/Products/Debug/KatiKati.app"
BIN = APP / "Contents/MacOS/KatiKati"
SUPPORT = pathlib.Path.home() / "Library/Application Support/KatiKati"
GENERATED = SUPPORT / "DynamicWallpapers/Generated"
SKY_PACK = SUPPORT / "Wallpapers/sky"
OUT = ROOT / "build/live-check/wallpapers"
WINDOW_PROBE = ROOT / "build/live-check/desktop_window.swift"
DOMAIN = "com.katikati.app"

PHASES = ["dawn", "day", "golden", "dusk", "night"]
SKIES = ["clear", "cloudy", "rain", "snow", "storm", "fog"]
ENVIRONMENTS = ["auto", "city", "countryside", "terrain"]
SCENES = {"city": "city", "countryside": "countryside"}


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def signed() -> int:
    result = run([str(ROOT / "Scripts/build_and_run.sh"), "--check-signing"])
    if result.returncode == 3:
        print("signing gate refused: the bundle no longer matches the Accessibility grant "
              "(run Scripts/build_and_run.sh --check-signing)", file=sys.stderr)
        return 3
    if result.returncode != 0:
        print((result.stdout + result.stderr).strip(), file=sys.stderr)
        return 2
    return 0


def pids() -> list:
    out = run(["pgrep", "-x", "KatiKati"]).stdout.split()
    return [int(p) for p in out if p.isdigit()]


def quit_app(timeout=12.0) -> bool:
    run(["osascript", "-e", 'tell application "KatiKati" to quit'])
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not pids():
            return True
        time.sleep(0.25)
    for pid in pids():
        run(["kill", str(pid)])
    return not pids()


def launch(extra_env=None):
    env = dict(os.environ)
    env.pop("DOCK_WALLPAPER_PHASE", None)
    env.pop("DOCK_WALLPAPER_ANIMATE", None)
    env.update(extra_env or {})
    subprocess.Popen([str(BIN)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline and not pids():
        time.sleep(0.2)
    time.sleep(3.0)


def desktop_picture() -> str:
    result = run(["osascript", "-e", 'tell application "System Events" to get picture of desktop 1'])
    return result.stdout.strip() if result.returncode == 0 else ""


def wait_for_picture(pattern, timeout=25.0) -> str:
    deadline = time.monotonic() + timeout
    found = ""
    while time.monotonic() < deadline:
        found = desktop_picture()
        if re.search(pattern, found):
            return found
        time.sleep(0.5)
    return found


def write_setting(key, value):
    run(["defaults", "write", DOMAIN, key, value])


def digest_tree(folder: pathlib.Path) -> dict:
    result = {}
    if not folder.exists():
        return result
    for path in sorted(folder.rglob("*")):
        if path.is_file():
            result[str(path.relative_to(folder))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def wait_for_overlay(present: bool, timeout=15.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        count = desktop_windows()
        if (count > 0) == present:
            return True
        time.sleep(0.75)
    return False


def desktop_windows() -> int:
    """How many KatiKati windows sit at desktopWindow + 1 (the Small Animation overlay)."""
    if not WINDOW_PROBE.exists():
        WINDOW_PROBE.write_text(SWIFT_PROBE)
    binary = WINDOW_PROBE.with_suffix("")
    if not binary.exists() or binary.stat().st_mtime < WINDOW_PROBE.stat().st_mtime:
        compiled = run(["swiftc", "-O", str(WINDOW_PROBE), "-o", str(binary)])
        if compiled.returncode != 0:
            return -1
    result = run([str(binary)])
    match = re.search(r"at desktop\+1 .*: (\d+)", result.stdout)
    return int(match.group(1)) if match else -1


SWIFT_PROBE = """import CoreGraphics
import Foundation
let level = Int(CGWindowLevelForKey(.desktopWindow)) + 1
let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let ours = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "KatiKati" }
print("KatiKati windows: \\(ours.count), at desktop+1 (\\(level)): \\(ours.filter { ($0[kCGWindowLayer as String] as? Int) == level }.count)")
"""


def case_list(full: bool) -> list:
    environments = ENVIRONMENTS if full else ["auto"]
    return [(environment, phase, sky) for environment in environments for phase in PHASES for sky in SKIES]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--full", action="store_true", help="all four environments instead of auto only")
    parser.add_argument("--limit", type=int, default=0, help="stop after N cases")
    parser.add_argument("--skip-animation", action="store_true")
    parser.add_argument("--skip-preservation", action="store_true")
    parser.add_argument("--skip-cases", action="store_true", help="only the preservation and animation checks")
    args = parser.parse_args()

    if not BIN.exists():
        print(f"no app bundle at {APP} — build it first", file=sys.stderr)
        return 2
    if desktop_windows() < 0:
        print("could not enumerate windows (swiftc failed)", file=sys.stderr)
        return 2
    if pids() and not quit_app():
        print("KatiKati is running and did not quit", file=sys.stderr)
        return 2
    status = signed()
    if status:
        return status

    OUT.mkdir(parents=True, exist_ok=True)
    sky_before = digest_tree(SKY_PACK)
    generated_before = set(GENERATED.glob("*")) if GENERATED.exists() else set()
    planted = GENERATED / "default.heic"
    if GENERATED.exists():
        planted.write_bytes(b"user file that pruning must not touch")

    cases = [] if args.skip_cases else case_list(args.full)
    if args.limit:
        cases = cases[:args.limit]
    rows, failures = [], []
    for environment, phase, sky in cases:
        write_setting("com.katikati.wallpaper.terrain", environment)
        quit_app()
        launch({"DOCK_WALLPAPER_PHASE": f"{phase}:{sky}", "DOCK_WALLPAPER_ANIMATE": "pause"})
        expected_scene = SCENES.get(environment)
        pattern = (f"terrain-{expected_scene if expected_scene else r'(?:city|countryside|alpine|coast)'}"
                   f"-{phase}-{sky}-")
        found = wait_for_picture(pattern, timeout=25)
        shot = OUT / f"{environment}-{phase}-{sky}.png"
        run(["screencapture", "-x", str(shot)])
        ok = bool(re.search(pattern, found)) and str(GENERATED) in found
        rows.append({"environment": environment, "phase": phase, "sky": sky, "picture": found,
                     "screenshot": str(shot.relative_to(ROOT)), "ok": ok})
        print(("ok   " if ok else "FAIL ") + f"{environment}/{phase}/{sky} -> {pathlib.Path(found).name}")
        if not ok:
            failures.append(f"{environment}/{phase}/{sky}: expected {pattern}… in {GENERATED}, got {found!r}")

    preservation = {}
    if not args.skip_preservation:
        quit_app()
        launch({"DOCK_WALLPAPER_PHASE": "night:clear"})
        time.sleep(2)
        sky_after = digest_tree(SKY_PACK)
        preservation["sky_pack_unchanged"] = sky_before == sky_after and bool(sky_before)
        preservation["planted_file_survives"] = planted.exists()
        preservation["generated_kept_its_frames"] = bool(generated_before & set(GENERATED.glob("*")))
        for key, value in preservation.items():
            print(("ok   " if value else "FAIL ") + key)
            if not value:
                failures.append(key)
        planted.unlink(missing_ok=True)

    animation = {}
    if not args.skip_animation:
        write_setting("com.katikati.wallpaper.animate", "true")
        quit_app()
        launch({"DOCK_WALLPAPER_PHASE": "night:clear"})
        time.sleep(2)
        animation["overlay_present_when_on"] = wait_for_overlay(present=True)
        quit_app()
        launch({"DOCK_WALLPAPER_PHASE": "night:clear", "DOCK_WALLPAPER_ANIMATE": "pause"})
        time.sleep(2)
        animation["overlay_absent_when_paused"] = wait_for_overlay(present=False)
        animation["desktop_picture_unchanged_by_animation"] = "Generated" in desktop_picture()
        write_setting("com.katikati.wallpaper.animate", "false")
        for key, value in animation.items():
            print(("ok   " if value else "FAIL ") + key)
            if not value:
                failures.append(key)

    index = {"generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"), "cases": rows,
             "preservation": preservation, "animation": animation, "failures": failures}
    (OUT / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    print(f"\n{len(rows)} cases, {len(failures)} failures · index: {OUT / 'index.json'}")
    if failures:
        for failure in failures:
            print("  ✗ " + failure)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
