#!/usr/bin/env python3
"""List strings that are still English in every locale, so they can be translated.

A string counts as pending when every localization entry carries state "new" and the
same value as the key. Run from the repo root:

    python3 Scripts/list_pending_translations.py            # table for Docs/TRANSLATIONS.md
    python3 Scripts/list_pending_translations.py --markdown  # full document body

Exit status is 1 when anything is pending, 0 when the catalog is fully translated.
"""
import json
import subprocess
import sys
from pathlib import Path

CATALOG = Path("Resources/Localizable.xcstrings")
HEADER = "# Pending translations"


def pending():
    data = json.loads(CATALOG.read_text())
    rows = []
    for key, entry in data["strings"].items():
        locs = entry.get("localizations", {})
        if not locs:
            continue
        states = {u.get("stringUnit", {}).get("state") for u in locs.values()}
        values = {u.get("stringUnit", {}).get("value") for u in locs.values()}
        if states == {"new"} and values == {key}:
            rows.append(key)
    return sorted(rows)


def surfaces(key):
    found = subprocess.run(["rg", "-l", "-F", key, "App", "Core"],
                           capture_output=True, text=True).stdout
    return ", ".join(sorted({p.split("/")[-1] for p in found.split("\n") if p}))


def main():
    keys = pending()
    if "--markdown" in sys.argv:
        print(HEADER + "\n")
        print(f"{len(keys)} strings are still English in every locale. Nothing here carries")
        print("`shouldTranslate: false`: everything the user can see gets translated.\n")
        print("| String | Used in |\n|---|---|")
        for key in keys:
            print(f"| `{key}` | {surfaces(key) or '—'} |")
    else:
        for key in keys:
            print(f"{key}  [{surfaces(key)}]")
    return 1 if keys else 0


if __name__ == "__main__":
    sys.exit(main())
