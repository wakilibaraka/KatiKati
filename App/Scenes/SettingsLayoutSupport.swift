import SwiftUI

extension QuickToggleID {
    /// Literal `Text` per case so the localization checker sees every key.
    var title: Text {
        switch self {
        case .darkMode: return Text("Dark Mode")
        case .keepAwake: return Text("Keep Awake")
        case .hideDesktopIcons: return Text("Hide Desktop")
        case .showHiddenFiles: return Text("Hidden Files")
        case .dockAutoHide: return Text("Dock Auto-hide")
        case .pathBar: return Text("Path Bar")
        case .muteMic: return Text("Mute Mic")
        case .emptyTrash: return Text("Empty Trash")
        case .ejectDisks: return Text("Eject Disks")
        case .wifi: return Text("Wi-Fi")
        case .bluetooth: return Text("Bluetooth")
        case .nightShift: return Text("Night Shift")
        case .trueTone: return Text("True Tone")
        case .vpn: return Text("VPN")
        case .screenSaver: return Text("Screen Saver")
        case .lockScreen: return Text("Lock Screen")
        case .relaunchFinder: return Text("Relaunch Finder")
        case .screenMirroring: return Text("Screen Mirroring")
        }
    }
}

/// Records one key combination (at least one of ⌃ ⌥ ⇧ ⌘). A local key monitor lives only while recording.
struct ShortcutRecorderButton: View {
    let onRecord: (ShortcutKey) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            if recording { Text("Press keys…") } else { Text("Record") }
        }
        .buttonStyle(SettingsGelButtonStyle(prominent: recording))
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }   // Esc cancels
            let f = event.modifierFlags
            var mods: UInt8 = 0
            if f.contains(.control) { mods |= ShortcutKey.control }
            if f.contains(.option) { mods |= ShortcutKey.option }
            if f.contains(.shift) { mods |= ShortcutKey.shift }
            if f.contains(.command) { mods |= ShortcutKey.command }
            let key = ShortcutKey(keyCode: event.keyCode, modifiers: mods)
            if key.isValid { onRecord(key); stop() }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
