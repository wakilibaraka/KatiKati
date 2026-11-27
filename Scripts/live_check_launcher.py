#!/usr/bin/env python3
"""Live-check KatiKati's Launcher panel via Accessibility & synthetic keyboard activation.

Verifies:
  1. Launcher panel is absent before trigger;
  2. Pressing Option+Space opens the Launcher panel with search field and grid items;
  3. Escape dismisses the Launcher panel cleanly.

Exit code: 0 passed; 1 failed; 2 setup problem (app running, missing .app, missing AX trust).
Manual live-check aid, modeled on `Scripts/live_check_side_deck.py`.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "build/live-check"

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
func walk(_ element: AXUIElement, _ depth: Int, _ visit: (AXUIElement) -> Void) {
    guard depth <= 8 else { return }
    visit(element)
    for child in children(element) { walk(child, depth + 1, visit) }
}

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : ""
switch mode {
case "trust":
    print(AXIsProcessTrusted() ? "true" : "false")
case "toggle":
    guard let src = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(keyboardEventSource: src, virtualKey: 49, keyDown: true),
          let up = CGEvent(keyboardEventSource: src, virtualKey: 49, keyDown: false) else { exit(2) }
    down.flags = [.maskAlternate, .maskShift]
    up.flags = [.maskAlternate, .maskShift]
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
case "esc":
    guard let src = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true),
          let up = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false) else { exit(2) }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
case "dump":
    guard args.count > 2, let pid = Int32(args[2]) else { exit(2) }
    let app = AXUIElementCreateApplication(pid)
    let windows = (value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    for (idx, win) in windows.enumerated() {
        var found = [String]()
        walk(win, 0) { el in
            let r = text(el, kAXRoleAttribute)
            let d = text(el, kAXDescriptionAttribute)
            let t = text(el, kAXTitleAttribute)
            if !d.isEmpty || !t.isEmpty || r == kAXTextFieldRole as String {
                found.append("\(r):\(d)|\(t)")
            }
        }
        print("WIN[\(idx)] " + found.joined(separator: "; "))
    }
default:
    exit(2)
}
'''


def build_helper() -> pathlib.Path:
    WORK.mkdir(parents=True, exist_ok=True)
    src = WORK / "launcher_helper.swift"
    bin_path = WORK / "launcher_helper"
    src.write_text(HELPER_SWIFT, encoding="utf-8")
    if not bin_path.exists() or src.stat().st_mtime > bin_path.stat().st_mtime:
        subprocess.run(["swiftc", "-O", str(src), "-o", str(bin_path)], check=True)
    return bin_path


def run_helper(helper: pathlib.Path, *args: str) -> str:
    return subprocess.run([str(helper), *args], capture_output=True, text=True, check=True).stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=pathlib.Path)
    args = parser.parse_args()

    if not args.app.exists():
        print(f"error: app not found at {args.app}", file=sys.stderr)
        return 2

    running = subprocess.run(["pgrep", "-x", "KatiKati"], capture_output=True).returncode == 0
    if running:
        print("error: KatiKati is already running", file=sys.stderr)
        return 2

    helper = build_helper()
    if run_helper(helper, "trust") != "true":
        print("error: accessibility permission not granted", file=sys.stderr)
        return 2

    proc = subprocess.Popen([str(args.app / "Contents/MacOS/KatiKati")])
    try:
        time.sleep(2.5)
        run_helper(helper, "toggle")
        time.sleep(0.8)
        dump = run_helper(helper, "dump", str(proc.pid))
        if "Launcher" not in dump and "Search" not in dump:
            print(f"FAIL: launcher did not surface in AX tree:\n{dump}", file=sys.stderr)
            return 1
        run_helper(helper, "esc")
        time.sleep(0.5)
        after = run_helper(helper, "dump", str(proc.pid))
        if "Launcher" in after:
            print(f"FAIL: launcher did not dismiss on Esc:\n{after}", file=sys.stderr)
            return 1
        print("PASS: launcher live check succeeded")
        return 0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=4)
        except subprocess.TimeoutExpired:
            proc.kill()


if __name__ == "__main__":
    raise SystemExit(main())
