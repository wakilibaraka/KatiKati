# Mission Control overlays: what has worked, what has died

Research for the decision to ship Mission Control as **experimental**, with the fragile inputs off by default.
Accessed 2026-11-22.

## The landscape

| Product | What it does | How it works | Outcome / lesson |
| --- | --- | --- | --- |
| [Mission Control Plus](https://www.fadel.io/missioncontrolplus) | Close/minimize/quit the window under the pointer, arrow-key navigation inside the overview | Accessibility permission plus the private `_AXUIElementGetWindow` symbol; sold outside the Mac App Store ([author on HN](https://news.ycombinator.com/item?id=21013034)) | Still sold for macOS 12–26 at US$8.99. A narrow, additive action layer is viable, and people pay for it; the private symbol is why it cannot be sandboxed. |
| [CloseUp](https://github.com/oomol-lab/CloseUp) / [Open Mission Control](https://github.com/oomol-lab/CloseUp) | The same action layer, open source | Accessibility, no Dock injection | Free GPL alternatives exist, so the feature alone is not a moat; polish and trust matter. |
| [TotalSpaces2/3](https://blog.binaryage.com/totalfinder-totalspaces-future) | A grid of Spaces, custom transitions, drag windows between Spaces | Code injection into Dock/WindowServer, SIP disabled | **Discontinued.** Apple Silicon and later macOS releases made SIP-off injection impractical; the vendor explicitly cites missing Apple APIs and added protections. Deep reimplementation of Spaces is a dead end. |
| [SpacesManager](https://github.com/michaeltorbert/spaces-manager) | Menu-bar names for Spaces, stable UUID keys | Deliberately avoids Dock injection; uses CGS/SkyLight to read IDs, so it is unshippable on the App Store | Stable UUID-based naming is impossible with public APIs alone. App Store review rejects CGS symbols, and the sandbox blocks the WindowServer connection they need. App Store apps that do name Spaces use sequential counters, which break on reorder/delete. |
| [ActiveSpace](https://github.com/PerpetualBeta/ActiveSpace) | Shows the current Space, switches by click | Sends macOS's own "Switch to Desktop N" shortcuts; no private window-server calls | Durable across OS updates precisely because it delegates to Apple. Public-API-only designs survive; private ones need maintenance. |
| [GridLion / "macOS needs its Spaces grid back"](https://mjtsai.com/blog/2026/06/03/macos-needs-its-spaces-grid-back) | Instant Space switching with a grid model | Accessibility + Screen Recording; excluded from the Mac App Store | Even a well-received utility is limited by permissions and distribution, not by demand. |
| [ShiftPlus](https://shiftplus.app/blog/macos-spaces-without-disabling-sip) | Restores apps to their Space | One SkyLight call (`SLSManagedDisplaySetCurrentSpace`) works with SIP on; window-move calls fail silently | Some Space operations can be done safely with SIP on, but window-move APIs are not among them. |

## Why the successful ones succeed

1. **They add a layer, they do not replace Mission Control.** Close buttons, keyboard actions and names in a
   separate HUD are additive; users keep Apple's overview and Apple's animations.
2. **They lean on Accessibility and public notifications.** The action layer uses each window's own
   Accessibility buttons, which is supported and survives releases.
3. **They keep the private surface small.** Mission Control Plus needs one private symbol; ActiveSpace needs
   none. Every additional private hook is another thing a macOS release can break.
4. **They are honest about distribution.** No App Store, no sandbox, and the permission ask is explained up
   front. Users of these tools accept Accessibility; they do not accept silent failure.

## Why the ambitious ones fail

1. **SIP-off code injection does not survive Apple Silicon.** TotalSpaces is the clearest case: a beloved
   product that could not be ported because its core mechanism was injection.
2. **App Store rules forbid the useful parts.** Private CGS/SkyLight symbols and sandboxed WindowServer
   access are disqualifying; the workarounds (sequential Space counters) are exactly the fragile naming
   users complain about.
3. **Detection is undocumented.** There is no Mission Control API. Reading the Dock's AX tree worked on
   some releases and returned nothing on macOS 26; reading the WindowServer list is a fallback, not a
   contract. Any product built on it needs a graceful "unavailable" state and a way to turn it off.
4. **Global keyboard capture is a separate permission with its own failure mode.** Input Monitoring can be
   revoked, and synthetic events are not delivered to a background app while Mission Control owns the
   keyboard. Keyboard features therefore cannot be the default path.

## What KatiKati does with this

- **No injection, no SIP changes, no Dock patching.** The overlay only reads the WindowServer/AX and acts
  through each window's Accessibility buttons, like the surviving products.
- **Experimental label.** Detection depends on undocumented WindowServer behaviour (the Dock publishes no
  usable AX windows on macOS 26) and has only been exercised on one display without Stage Manager.
- **Fragile inputs off by default.** Keyboard navigation, type-to-filter and hover key shortcuts are opt-in;
  the border/group overlay is off; Traffic Light (no border) is the default look. Naming, colours and the
  mouse action cluster remain on, because those are the parts that work and that people pay for.
- **Stable naming is deliberately scoped.** Names are keyed to the Space ID for our own overlay, not written
  into Apple's Mission Control labels, because that would require the Dock injection that killed TotalSpaces.
