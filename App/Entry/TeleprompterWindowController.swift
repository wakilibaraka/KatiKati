import AppKit
import SwiftUI

// Phase 37b — the floating teleprompter window. Resizable, always on top, and kept out of screen
// captures and shares (`sharingType = .none`) so reading from it never shows up in a recording.

@MainActor
final class TeleprompterWindowController {
    static let shared = TeleprompterWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            w.title = String(localized: "Teleprompter")
            w.level = .floating
            w.isReleasedWhenClosed = false
            w.sharingType = .none
            w.hidesOnDeactivate = false
            w.backgroundColor = .black
            w.contentView = NSHostingView(rootView: TeleprompterView())
            w.setFrameAutosaveName("KatiKatiTeleprompter")
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() { window?.orderOut(nil); TeleprompterModel.shared.pause() }
}
