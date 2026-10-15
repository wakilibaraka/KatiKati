import AppKit
import CoreAudio
import CoreMediaIO

// Phase 36h — "is a camera / microphone in use right now?" Reads two CoreAudio / CoreMediaIO properties.
// It never opens a device, captures nothing, and needs no permission. The caller polls it only while the
// helper is on.

enum PrivacyUseProbe {
    static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != kAudioObjectUnknown else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &size, &running) == noErr && running != 0
    }

    static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids) == noErr else { return false }
        return ids.contains { id in
            var running: UInt32 = 0
            var runningSize: UInt32 = 0
            var runningAddress = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            return CMIOObjectGetPropertyData(id, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &runningSize, &running) == noErr && running != 0
        }
    }
}

/// The two dots, click-through, parked beside the notch / under the top edge.
@MainActor
final class PrivacyDotController {
    private var panel: NSPanel?
    private var shown: PrivacyDots?

    func update(_ dots: PrivacyDots) {
        guard dots != shown else { return }
        shown = dots
        guard !dots.isEmpty else { panel?.orderOut(nil); return }
        let host = NSHostingView(rootView: PrivacyDotsView(dots: dots))
        let size = host.fittingSize
        host.setFrameSize(size)
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.level = .statusBar; p.ignoresMouseEvents = true; p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            self.panel = p
            return p
        }()
        panel.contentView = host
        panel.setContentSize(size)
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX + 110, y: screen.frame.maxY - size.height - 4))
        }
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil); panel = nil; shown = nil }
}

import SwiftUI

struct PrivacyDotsView: View {
    let dots: PrivacyDots
    var body: some View {
        HStack(spacing: 4) {
            if dots.camera { Circle().fill(Color.green).frame(width: 8, height: 8).accessibilityLabel(Text("Camera in use")) }
            if dots.microphone { Circle().fill(Color.orange).frame(width: 8, height: 8).accessibilityLabel(Text("Microphone in use")) }
        }
        .padding(4)
    }
}
