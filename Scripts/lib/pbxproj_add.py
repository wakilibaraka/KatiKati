#!/usr/bin/env python3
"""
Minimal helper: add Swift source files to the KatiKati Xcode project.

Usage:
    add_source(pbx_path, entries)

    entries is a list of dicts:
        {
          "uid":  "A0000000000000000001E000",  # base uid for fileRef
          "name": "SnapRects.swift",
          "path": "Core/Support/SnapRects.swift",   # relative to SOURCE_ROOT
          "group": "Support",                        # "Support" | "UnitTests" | "Composition" | ...
          "targets": ["main", "tools"],              # which build phases to add to
        }

Each source file needs:
  - one PBXFileReference
  - N PBXBuildFile entries (one per target)
  - insertion into the group children list
  - insertion into each target's Sources build phase

UIDs are deterministic: fileRef = uid+"00", buildFile[i] = uid+"01"/"02"/...
"""

import re, sys

PBXPROJ = "/Users/baraka/Desktop/KatiKati/KatiKati.xcodeproj/project.pbxproj"

# ── target build-phase UUIDs (from project.pbxproj) ──────────────────────────
# grep 'isa = PBXSourcesBuildPhase' project.pbxproj -B1
TARGET_SOURCES = {
    "main":       "A0000000000000000000001B",   # KatiKati app target Sources
    "tools":      "A0000000000000000000001C",   # (WindowLab/tools – may differ)
    "tests":      "A0000000000000000000001D",   # Unit test target Sources
}

# ── group UUIDs ───────────────────────────────────────────────────────────────
GROUP_IDS = {
    "Support":    "A000000000000000000019E2",
    "UnitTests":  None,   # unit test files live in their own group – handled by path
    "Composition":"A0000000000000000000F200",   # App/Composition group
    "Entry":      "A0000000000000000000F210",   # App/Entry group
}

def _read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

def _write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)

def _insert_after(text, needle, insertion):
    idx = text.find(needle)
    if idx == -1:
        raise ValueError(f"Needle not found: {needle!r}")
    end = idx + len(needle)
    return text[:end] + insertion + text[end:]

def add_sources(entries):
    """Add a batch of source files to the pbxproj."""
    text = _read(PBXPROJ)

    for e in entries:
        uid   = e["uid"]
        name  = e["name"]
        path  = e["path"]
        group = e.get("group", "Support")
        targets = e.get("targets", ["main", "tools"])

        ref_uid = uid + "00"

        # ── 1. PBXBuildFile entries ──────────────────────────────────────────
        build_lines = ""
        for i, tgt in enumerate(targets, start=1):
            bu = uid + f"{i:02d}"
            build_lines += f"\t\t{bu} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_uid} /* {name} */; }};\n"

        # Insert into PBXBuildFile section – after last line that ends "};"
        # Strategy: insert after the first PBXBuildFile block sentinel
        sentinel = "/* Begin PBXBuildFile section */"
        text = _insert_after(text, sentinel + "\n", build_lines)

        # ── 2. PBXFileReference ──────────────────────────────────────────────
        # Determine sourceTree and path representation
        if path.startswith("Core/") or path.startswith("Platform/") or path.startswith("App/"):
            source_tree = "SOURCE_ROOT"
            path_attr = f'name = {name}; path = {path};'
        else:
            # relative (Tests/Unit/...)
            source_tree = '"<group>"'
            path_attr = f'path = {name};'

        ref_line = (
            f'\t\t{ref_uid} /* {name} */ = '
            f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
            f'{path_attr} sourceTree = {source_tree}; }};\n'
        )
        sentinel2 = "/* Begin PBXFileReference section */"
        text = _insert_after(text, sentinel2 + "\n", ref_line)

        # ── 3. Group children ────────────────────────────────────────────────
        if group == "UnitTests":
            # Insert into the Unit test group – find by looking for ClipboardPlusTests or similar
            grp_needle = "A0000000000000000000D010 /* ClipboardPlusTests.swift */,"
            text = _insert_after(text, grp_needle + "\n",
                                  f"\t\t\t\t{ref_uid} /* {name} */,\n")
        elif group == "Support":
            # Insert after WindowSnap.swift in Support group children
            grp_needle = "ED00000000000000000000C1 /* WindowSnap.swift */,"
            text = _insert_after(text, grp_needle + "\n",
                                  f"\t\t\t\t{ref_uid} /* {name} */,\n")
        elif group == "Composition":
            grp_needle = "A0000000000000000000A320 /* NotificationMoveService.swift */,"
            text = _insert_after(text, grp_needle + "\n",
                                  f"\t\t\t\t{ref_uid} /* {name} */,\n")
        elif group == "Entry":
            grp_needle = "A0000000000000000000A140 /* TranslatePanelController.swift */,"
            text = _insert_after(text, grp_needle + "\n",
                                  f"\t\t\t\t{ref_uid} /* {name} */,\n")
        else:
            print(f"WARNING: unknown group {group!r} for {name}, skipping group insertion")

        # ── 4. Sources build phase insertions ────────────────────────────────
        for i, tgt in enumerate(targets, start=1):
            bu = uid + f"{i:02d}"
            tgt_label = {"main": "KatiKati", "tools": "Tools", "tests": "UnitTests"}[tgt]
            # Find the build phase for this target: look for the Sources section comment
            phase_needle = f"/* Sources ({tgt_label}) */ = {{"
            if phase_needle not in text:
                # fallback: find by uid
                src_uid = TARGET_SOURCES[tgt]
                phase_needle2 = f"{src_uid} /* Sources */"
                if phase_needle2 not in text:
                    print(f"WARNING: could not find build phase for target {tgt!r}")
                    continue
            # Insert the build file ref right before the closing ");" of the files list
            # Find the phase block and insert our line before "ED00000000000000000000C2" (first snap build file)
            # Strategy: find the last WindowSnap build file in each target and insert after it
            if tgt == "main":
                insert_needle = "ED00000000000000000000C2 /* WindowSnap.swift in Sources */,"
            elif tgt == "tools":
                insert_needle = "ED00000000000000000000C3 /* WindowSnap.swift in Sources */,"
            elif tgt == "tests":
                insert_needle = "ED00000000000000000000C9 /* WindowSnapTests.swift in Sources */,"

            text = _insert_after(text, insert_needle + "\n",
                                  f"\t\t\t\t{bu} /* {name} in Sources */,\n")

    _write(PBXPROJ, text)
    print(f"✅ Added {len(entries)} file(s) to pbxproj.")


if __name__ == "__main__":
    # Quick self-test: print the groups
    print("pbxproj_add helper ready")
