# Phase 47b/47c — a live walk of the two new notch pages (2026-10-16)

Both pages were switched on, the app was built and launched the normal way, and the notch was opened by
hovering it with a real mouse move, so every step below is the path a user takes — not a test seam.

## How it was driven

| step | mechanism |
| --- | --- |
| the two page switches | `defaults write com.katikati.app com.katikati.notch.mirror -bool true` and `… com.katikati.notch.notifications -bool true` (the same keys the Settings toggles write) |
| the app | `Scripts/build_and_run.sh run` (own build of `main` @ `113718f`, `open`ed so TCC attributes it to KatiKati) |
| opening the notch | a `CGEventPost` mouse move to (855, 25) — the closed capsule's centre; `NotchHoverMachine`'s 0.12 s dwell then opens the panel |
| stepping pages | `CGEventPost` clicks at the page buttons' own accessibility centres (Camera Mirror (758, 18), Notifications (786, 19)) |
| reading the result | the app's accessibility tree through System Events (role / help / value / frame), `screencapture -R 535,0,640,190`, and `log show --predicate 'process == "KatiKati"'` |

The panel's own frame is the anchor for every coordinate: closed `[749,0 212x38]`, open `[535,0 640x190]`
(logical points, top-left origin). Every capture below was taken with the frame re-read immediately before
and after, so a collapsed panel cannot masquerade as a page.

## Camera mirror (page 8, `com.katikati.notch.mirror`)

- Opening the page raised macOS's camera prompt (this app's first camera ask). The grant landed at
  `08:28:41`: `AVCaptureSessionDidStartRunningNotification`, and the log shows the FaceTime HD Camera
  opened at `1920x1080 @ 15–30 fps`.
- **The preview is live.** Two frames two seconds apart, cropped to the panel:

  | | camera mirror | notifications page (control) |
  | --- | --- | --- |
  | unique colours | 36,601 | 319 |
  | pixels changed >8 between two frames 2 s apart | 6,878 of 486,400 (max delta 106) | 0 of 486,400 (max delta 0) |

  The page's own words on screen: the selected page button reads `Camera Mirror`, and the one header row
  reads `System Default` (the resolved camera; this machine has exactly one, so the `Choose Camera`
  dropdown — which only appears above one device — was not exercised live).
- **The camera stops with the page.** Leaving the mirror for the notifications page at `09:01:54` produced
  `CMIODeviceStopStream` + `AVCaptureSessionDidStopRunningNotification`; the start at `09:01:16–17` was the
  page's own `onAppear`. The camera light is therefore tied to the page being on screen, as designed.
- The mirrored picture is occluded in the middle by the hardware notch's own column (x 789–921 on this
  1710 × 1112 screen), exactly as every other page keeps that column clear. Not a defect — the notch is
  physical — but it is what the live picture looks like.

Files: `camera-mirror-1.png`, `camera-mirror-2.png` (the two frames), `camera-mirror-ax.txt` (the tree).

## Notifications (page 9, `com.katikati.notch.notifications`)

- The page renders, under the selected `Notifications` button, exactly:

  ```
  AXStaticText [583,55 75x15]  V=Notifications          (page title)
  AXStaticText [1138,56 7x14]  V=0                      (history count)
  AXStaticText [800,96 109x15] V=Accessibility Is Off   (the fail-closed headline)
  AXButton     [795,116 120x14]                         (the System Settings door)
  ```

- **This is the fail-closed branch, because this build has no Accessibility grant.**
  `NotificationMirrorService.canReadBanners` is `AXIsProcessTrusted()`; `Scripts/build_and_run.sh` warns
  `no signing identity found; keeping Xcode's build signature` on this machine, so the launchd-launched
  Debug app is a different code identity from the installed release and carries no grant of its own. The
  page states the missing grant and offers the door instead of showing an empty list — which is what the
  code promised, observed live.
- Consequently the two halves behind that grant were **not** exercised: live banner text (an AXObserver on
  Notification Center) and the history read from `group.com.apple.usernoted` (Full Disk Access). A test
  banner was fired at the page while it was open (`osascript -e 'display notification …'`) and correctly
  did not appear, since the page is not reading banners in this state.

Files: `notifications-1.png`, `notifications-2.png`, `notifications-ax.txt`.

## What is still unproven

- Banner mirroring and the history list, for the reason above — they need Accessibility and Full Disk
  Access granted to this build (`KatiKati` in System Settings › Privacy & Security), after which the walk
  is worth repeating.
- The `Choose Camera` dropdown with more than one camera (an iPhone via Continuity or an external camera).
- The denied-camera branch (`Camera Access Is Off`): the grant exists now, and a denial cannot be
  produced from outside the app.
