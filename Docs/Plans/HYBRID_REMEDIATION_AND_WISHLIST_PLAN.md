# Hybrid Remediation and Wishlist Plan

**Purpose:** A code-verified implementation plan that joins the product wishlist with the repository quality audit. Existing shipped work stays the foundation; verified data-loss, execution, and reliability defects take precedence over additional surface area.

**Status:** Active; Phases 0–4 remediation and consolidated wishlist slices (Slices A–H: `bdc67c76`–`14509653`) are landed and tested on `main`, and documentation/README reconciliation is current. Remaining Phase 5 release/UI items (live URLSession delegate test harness, signed-build README screenshots, and external Google Home/Cast protocol discovery) stay explicitly tracked below. Preserve dated release notes and historical plan snapshots; update only current status claims when source code proves them stale.

## Operating rules

- Confirm each claim in source and trace callers before changing behavior. A status in an old plan, report, or screenshot is evidence to check, not current truth.
- Fix the shared decision/service once, cover the dangerous edge with a focused regression test, then update this checklist in the same slice.
- Keep destructive actions review-first and recoverable; retain existing files if a replacement fails.
- For interface work, build on the existing AppKit/SwiftUI panel and settings patterns. Keep accessibility and localization in scope.
- A slice is complete when its code, callers, project registration, tests, and factual documentation agree.

## Priority order

| Phase | Focus | Exit condition |
|---|---|---|
| 0 | Evidence reconciliation | Verified current-state matrix and false claims corrected |
| 1 | P0 data safety and execution boundaries | Dangerous inputs fail closed; downloaded/restored data is preserved; tests cover seams |
| 2 | P1 runtime and interaction reliability | Socket, clipboard, Finder, shortcut, and monitor paths behave on failure and privacy boundaries |
| 3 | Shipped-feature completion and polish | Existing exposed controls work, accessibility/localization match behavior, README describes shipped product |
| 4 | New wishlist features | Only genuinely unbuilt features are scoped and delivered on existing foundations |
| 5 | Cleanup and release readiness | Dead code/duplicate work is proven before removal; release docs and project gates align |

## Phase 0 — Evidence reconciliation

- [x] Re-check the hydration claim: `HydrationController.startTimer()` previously stopped any running timer before restarting; updated to `guard timer == nil else { return }` with regression coverage in `Tests/Unit/SydedockControllersTests.swift`.
- [x] Correct the green-button claim: Option-click is passed through to native macOS Zoom. The stale Settings description needs correction, not a new interception behavior.
- [x] Keep encrypted notes' same-Mac WebDAV limitation as intentional: the encryption key is local and is not uploaded.
- [x] Trace backup scheduling: the concrete concern is restored scheduled evolutions/tool paths running scripts or commands later; there is no automatic `statusScript` probe on Hub open.
- [x] Audit and finish the SnApp/window inspector/display-mode (`SN-1`–`SN-6`) work on `main`: fixed multi-zone picker, AX/CPU inspection math, display revert safety, Xbox/MenuBar Hub submenus, Counter VoiceOver labels, and `NowPlayingServiceTests` target registration.
- [x] Reconcile stale wishlist/gap, Icon Studio, Music/Wallpaper, and Side Deck plan status against current source; retain their detailed historical content and leave dated release notes intact.

## Phase 1 — P0 data safety and execution boundaries

### Uninstaller candidate safety

- [x] Reject empty, malformed, system/self, slash-containing, and traversal-like app identities before standard candidate construction.
- [x] Constrain returned standard candidates to the user's `Library` subtree.
- [x] Add a regression test for empty and traversal identities.
- [ ] Inspect symlink behavior at the actual Trash boundary and verify UI cannot bypass the planner.

### Download completion and resume

- [x] Harden `DownloadManagerService` and `DownloadEnginePolicy`: move URLSession's temporary download file into a durable staged file, clean `.pending` artifacts via `defer`, sanitize filenames, guard task context access, fix relative segment resume offsets, cancel per-download non-206 responses, handle `didCompleteWithError`, and keep existing destinations until replacement succeeds.
- [x] Replace integer-truncated segment speed division with floating-point elapsed-time math and add regression coverage for policy/math, staging/resume offsets, and error paths in `Tests/Unit/DownloadManagerTests.swift`.
- [ ] Add end-to-end live `URLSession` delegate integration tests (beyond pure `DownloadTransferMath`/`DownloadEnginePolicy` seams).

### Agent approval and restored automation

- [x] Replace Bash prefix-based auto-approval with a command/subcommand allowlist and reject shell metacharacters, newlines, and ambiguous prefixes.
- [x] Add bypass regression cases.
- [x] Exclude executable Menu Bar evolutions/schedules and command/tool/script paths (`com.katikati.menuBarHub.evolutions.v1`, `com.katikati.menuBarHub.schedules.v1`, `com.katikati.mediaResolver.tool`, `com.katikati.torrent.enginePath`, `com.katikati.commandbar.custom`, `com.katikati.launcher.scripts.enabled`) from `SettingsBackup` capture/restore so a restored snapshot cannot auto-run scripts or arbitrary binaries; handle duplicate safety backup filenames safely with `(n)` suffixes in `SettingsBackupService`.
- [ ] Audit WebDAV settings restoration and schedule/evolution execution end-to-end; validate scripts and require clear opt-in before restored executable automation can run.

### WebDAV merge and note-key preservation

- [x] Merge object-contained `items` and `entries` arrays by stable `id`, retaining local-only rows and merging remote-only rows.
- [x] Preserve local-only object fields while applying remote field updates.
- [x] Add a task-shaped nested merge regression test.
- [ ] Add a capture-log nested merge case and verify actual restore write ordering/rollback behavior.
- [x] Change file-key loading so read failures propagate; create with exclusive file creation and reread a concurrently-created key instead of overwriting it.

## Phase 2 — P1 runtime and interaction reliability

- [x] `control.sock`: bound client reads, handle short reads/writes and disconnects, move blocking `send()`/`close(client)` off `@MainActor`, set `SO_NOSIGPIPE` on the listening socket before `bind`/`listen` (closing clients if `setsockopt` fails), release lock files on startup failures, and serialize stop with queued accepts.
- [x] Add socket disconnect and split-write coverage (`testEarlyDisconnectDoesNotCrashAndSplitWriteSucceeds` in `Tests/Unit/WorkspaceControlServerTests.swift`).
- [ ] Review whether the two-second client timeout is appropriate for slow target actions and add stalled-client timeout tests.
- [x] Clipboard: gate concealed/ignored types, `IsSecureEventInputEnabled()`, `skipNextCopy` before `ClipboardPasteboardProcessor`, and text patterns before callbacks or link rewriting; track `lastCopiedOriginBundleID` and `lastCopyWasBlocked`.
- [x] Add monitor-level clipboard privacy tests (`ClipboardMonitorPrivacyTests` in `Tests/Unit/ClipboardHistoryTests.swift`) and register `ClipboardMonitor.swift` in `KatiKatiTests`.
- [x] Finder cut/copy: exact Command chord; Command-C cancels pending cut; modified paste passes through. Add regression coverage.
- [ ] Review Finder text-field focus filtering and add F2 only if the existing shortcut policy can do so without stealing native text editing.
- [x] Fix Dock window AppleScript targeting to use the numeric process ID instead of interpolated localized app names.
- [x] Correct the Settings Option-click explanation to state native Zoom behavior, with all 12 catalog translations updated.
- [ ] Check status-script restore path, authorization defaults, and schedule execution against current backup model and UI.

## Phase 3 — Complete and polish shipped features

- [x] Wire the Side Deck weather-handle preference into the rendered handle, or remove/migrate the preference if a weather-aware visual is no longer a product decision (`f86277b7`).
- [x] Wire live Dock density into widgets that currently use hardcoded heights; confirm `.active` Icon Studio trigger reaches Dock/Launcher render paths (`f86277b7`).
- [x] Make the README match current shipped Side Deck/EasyDict/Workspaces/Menu Bar surfaces and remove the retired Notch Downloads/Storage pages from its description.
- [ ] Refresh README screenshots after a current signed app build can be captured and reviewed.
- [x] Consolidate experimental/private API settings and terminology after checking the current Settings IA; retain the native Option-click behavior above (`9c7949fc`).
- [x] Add the missing keyboard/accessibility states on shipped Side Deck pages; ensure labels describe the action (including “Open Side Deck”) (`558c352f`, `9c7949fc`).
- [x] Verify groups and profile controls in current UI before adding editors or onboarding defaults (`558c352f`).

## Phase 4 — Genuine wishlist gaps

Deliver independently, with existing APIs and narrow acceptance criteria:

1. **Window management:** compact snap-zone picker (`SnapPickerController`, 12 zones with distinct accessible buttons), left/right tiling priority, shake-to-open picker guarded against file-drag pasteboard changes (`WindowSnapService`), per-display mode revert confirmation (`.forSession` provisional apply -> Keep to `.permanently`), and Menu Bar Hub display/arrangement submenus (`SN-1`–`SN-6`) are shipped and tested on `main` (`SnapPickerModelTests`, `WindowSnapTests`, `DisplayModeCatalogTests`).
2. **Side Deck:** inline full-height Command Bar & Launcher embedded cleanly inside `SideDeckQuickAccessView` using shared `CommandBarPanelController`/`LauncherPanelController` engines (`341cf7ef`).
3. **Window inspector (`winfo`):** shipped with off-main-thread AX + single `proc_pid_rusage` sampling (`WindowInspectorMath.cpuPercent` with `mach_timebase_info` + PID tracking), `NSScreen` Y-flip matching, cached screen metadata, Accessibility disclosure (`needsAccessibility`), and tests in `WindowInspectorMathTests`.
4. **Weather/date tools:** pure `DateCalculator` + `DateCalculatorView` wired into Calendar tiles/popovers (`DateCalculatorTests`) plus `.samsung`, `.orion`, and `.notBoring` weather skins in `WeatherChipPreset` / `WeatherChip` (`341cf7ef`).
5. **Terminal:** persistent drag-resize (`TerminalPanelSizeBounds`), Finder CWD sync, snippets menu, `TerminalThemePreset` palettes, and `TerminalBufferSearch` find bar shipped with `TerminalSupportTests` (`341cf7ef`).
6. **DMG installer artwork:** Finder-styled DMG layout with generated dark slate backdrop, CI/headless fallback (`KATIKATI_PLAIN_DMG=1`), and detach cleanup added to `Scripts/package_release.sh` (`14509653`).
7. **Google Home/Cast/Android:** separate discovery/permission/design investigation deferred before implementation because the platform and device protocol surface is broad.
8. **Menu Bar illustration work:** multi-layer SF-Symbol badge illustrations and per-slot accents added to `MenuBarCreativeHubView` 2×2 action tiles while keeping dynamic text contrast and localization intact (`14509653`).

## Phase 5 — Cleanup and release readiness

- [x] Prove every claimed dead symbol has zero production and test references; move or remove code in small slices (`28f8cc35`).
- [ ] Do not delete tracked archive evidence or change history without an explicit retention decision; document storage impact separately.
- [x] Deduplicate battery, clipboard, and process readers only after confirming ownership and poll lifetimes (`e79697f9`).
- [x] Audit main-thread DDC/HID/process calls with call-site/isolation evidence; move blocking work off the UI actor without changing hardware calibration (`e79697f9`).
- [x] Check translation key parity for any changed UI copy and register all added tests/sources in the manually maintained Xcode project.
- [x] Run focused regression suites for the completed slices and the repository's localization/debug-switch/input-hygiene gates.
- [x] Run `graphify update .` after source changes and reconcile generated graph status without discarding pre-existing worktree changes.

## Decisions and known limits

- Uninstaller continues to use Trash and a review sheet; it must not hard-delete.
- WebDAV-encrypted note payloads remain local-key encrypted and are not readable on another Mac unless the owner deliberately changes the key-sharing model.
- Menu Bar Hub evolutions/schedules (`com.katikati.menuBarHub.evolutions.v1`, `com.katikati.menuBarHub.schedules.v1`) and command/script/tool paths (`com.katikati.mediaResolver.tool`, `com.katikati.torrent.enginePath`, `com.katikati.commandbar.custom`, `com.katikati.launcher.scripts.enabled`) are intentionally omitted from `SettingsBackup` capture/restore until imported commands/scripts have a safe, explicit review and opt-in flow; those user settings currently require separate recreation after restore.
- `HydrationController.startTimer()` now guards `timer == nil` instead of invalidating an active timer before restarting (covered by `SydedockControllersTests`).
- Option-click on the green button remains native macOS Zoom when KatiKati's maximize interception is enabled; Settings copy was updated instead of inventing a new gesture.
- A restored executable schedule is a real risk to assess. The investigation does not support the broader claim that `statusScript` runs automatically when the Hub opens.
- Preserve existing graph outputs and clean working-tree state (`default.profraw` / `replica/` / `screenshots/` remain untracked local artifacts).

## Progress log

- 2026-11-27 (prior commit baseline `6b53ac2a` / `86701679`): Added initial SnApp picker, window inspector, display modes/arrangements, `AppRemovalPlanner`, `AgentApproval`, `WebDAVSyncPlan`, `KeyGuard`, and initial test registration.
- 2026-11-27 (Slice 1, `b2d5ae29`): Landed P0/P1 reliability & security hardening across `DownloadManagerService`/`DownloadEnginePolicy` (temp staging, `.pending` `defer` cleanup, filename sanitization, relative resume offsets, non-206 cancellation, `didCompleteWithError`), `SettingsBackup`/`SettingsBackupService` (6 excluded keys + `(n)` backup suffixes), `HydrationController` timer guard, `WorkspaceControlServer` off-`@MainActor` writes and early `SO_NOSIGPIPE`, `ClipboardMonitor` secure-input/privacy gating, and `FileNoteKeyProvider` exclusive file creation via `Darwin.link`. Verified 124 executed / 2 skipped (pre-existing) / 0 failures across 12 suites + all localization/debug/hygiene gates.
- 2026-11-27 (Slice 2): Fixed `SN-1`–`SN-6` across `SnapPickerController` (12 zones, individual accessible buttons, vertical anchor fix), `WindowSnapService` (file-drag guard), `WindowInspectorController` / `WindowInspectorMath` (off-main-thread AX + single `proc_pid_rusage` CPU math, Cocoa Y-flip, cached screens, `needsAccessibility`), `DisplayModeService` (`.forSession` + Revert confirmation, `option.id` refresh check, `CGCancelDisplayConfiguration`), `StatusTrioView` (per-display submenus, disabled incomplete arrangements), `EdgeExtraCards`/`Localizable.xcstrings` (`Decrease`/`Increase` labels), and Xcode `PBXGroup` + `NowPlayingService` registration in `KatiKatiTests`.
- 2026-11-27 (Slice 3): Reconciled stale claims across `HYBRID_PLAN.md`, `Docs/Plans/*`, `LANES.md`, `CHANGELOG.md`, `README.md`, and `README.zh-CN.md`.
- 2026-11-27 (Slices A–C, `bdc67c76` / `e79697f9` / `28f8cc35`): Hardened torrent/media/WebDAV/Spotify/symlink execution boundaries, eliminated main-thread DDC/HID/process stalls and duplicate pollers/idle timers, extracted Hub & Tendedero views, and pruned verified dead Swift symbols and unused target links.
- 2026-11-27 (Slices D–F, `f86277b7` / `9c7949fc` / `558c352f`): Wired SideDeck Weather Handle, `.active` Icon Studio badges, live `WidgetDensityPolicy`, and Finder F2 text-field focus guard; reorganized Settings (Widget Wings moved to Dock Layout, Experimental tab, unified Side Deck naming, fuzzy `SettingsSearchIndex`); added universal `followDockTheme`, SideDeck/EdgeBar keyboard navigation, App Groups onboarding & Settings editor, `captureWindow` shortcut, RAM squircle ring, and removed Pick Color.
- 2026-11-27 (Slices G–H, `341cf7ef` / `14509653`): Embedded `CommandBarView` & `LauncherView` in `SideDeckQuickAccessView`, added `.samsung`/`.orion`/`.notBoring` weather skins, pure `DateCalculator` & Calendar `DateCalculatorView`, resizable/themed/searchable Terminal with snippets & Finder CWD sync, illustrated Menu Bar Hub action tiles, and Finder-styled DMG installer packaging.
