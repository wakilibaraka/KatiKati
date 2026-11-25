# Control Centre menu-bar home — live recheck after main sync

Date: 2026-11-25 · `main` at `779f4291`, identical to `origin/main` (0 ahead / 0 behind), nothing to
rebase. Working tree was clean before this pass and the running build was the signed Debug app from
that commit. No code changes were needed; this folder is evidence only.

## Observed

1. Reset to `surface=edge` with the prompt flag cleared, relaunched, Settings › Control Center › Home →
   **Menu Bar**. The prompt appears (`01`) with **Keep in Menu Bar** / **Use Edge Instead**; both
   buttons are present in the AX tree.
2. **Keep in Menu Bar** → `surface=menuBar`. Status item opens Control Centre: 360×792 at 1342,38, AX
   `Wi-Fi, Not Connected` / `Bluetooth, 0 Devices` (`02`).
3. Dock capsule opens **Background Apps**: 360×994 at 1338,50, AX title "Background Apps", no dialog
   (`03`).
4. Quit + relaunch: defaults still `menuBar` / prompt seen. Status item again opens Control Centre
   (360×792, Wi-Fi card, no `AXDialog`) (`04`), capsule again opens Background Apps (`05`).
5. Settings → **Edge**: `surface=edge`, no prompt. Status item opens the Creative Hub (380×570 at
   1322,38, `06`); capsule opens the standalone Control Centre (360×994, Wi-Fi card, `07`).
6. Dock chip hub menus intact after the revert: trash (`08`) shows "Trash" + Settings / Control Center
   / Auto-Hide / Position and the Open Trash / Empty Trash… items; Downloads (`09`) shows
   "Downloads" + the same four tiles and Preview Contents / Open in Finder / Sort by / Add Folder… /
   Remove from Taskbar.

Final machine state: `surface=edge`, prompt flag set, app running on the synced commit.

## Not covered

- The two button strings were only rendered in English; all twelve catalogs pass the localization gate.
- The status-item context row title in menu-bar mode was not opened in this pass.
