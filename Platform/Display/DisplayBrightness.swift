import AppKit
import CoreGraphics
import IOKit
import os.lock

/// MD-5 — brightness for every display, not only the built-in panel.
///
/// Three backends, chosen per display:
/// 1. **Built-in panel** → the existing `DisplayServicesBrightness` (native brightness, never gamma).
/// 2. **External via DDC/CI** → the panel's own backlight over I2C, so the hardware OSD and the
///    slider agree. On Apple Silicon this is the private `IOAVService` API on `DCPAVServiceProxy`
///    nodes whose `Location` is `External`; it needs no entitlement, no root and raises no TCC
///    prompt. Clean-room implementation from the public MCCS/DDC-CI command set (`0x51` host
///    address, VCP `0x10` brightness, `0x62` volume); no third-party source is copied.
/// 3. **Software fallback** → a gamma transfer table on the display, used when DDC does not answer
///    (TVs, some hubs, virtual displays). The built-in panel never takes this path.
///
/// All I2C traffic runs on one serial queue and is coalesced: a slider drag offers many values and
/// only the last one per (display, VCP) is ever written, at most every 50 ms.
/// The raw DDC/CI transport. Every private symbol is looked up here, in this file only, so deleting
/// this file removes the whole private-API surface.
final class DDCTransport {
    typealias Service = CFTypeRef

    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias ReadFn = @convention(c) (CFTypeRef?, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> Int32
    private typealias WriteFn = @convention(c) (CFTypeRef?, UInt32, UInt32, UnsafeRawPointer?, UInt32) -> Int32

    /// DDC/CI's 7-bit I2C chip address, passed *unshifted*: `IOAVService` does the shifting
    /// itself. Passing `0x37 << 1` makes every transaction read back as one repeated garbage byte
    /// on real hardware (measured: `A1 A1 …`), which reads as "panel does not answer".
    private static let chipAddress: UInt32 = 0x37
    /// DDC/CI's fixed data address.
    private static let dataAddress: UInt32 = 0x51

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private static let create: CreateFn? = symbol("IOAVServiceCreateWithService")
    private static let readI2C: ReadFn? = symbol("IOAVServiceReadI2C")
    private static let writeI2C: WriteFn? = symbol("IOAVServiceWriteI2C")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    static var isSupported: Bool { create != nil && readI2C != nil && writeI2C != nil }

    /// External AV services in registry order. `Location == External` is what separates a real panel
    /// from the built-in one and from virtual displays.
    static func externalServices() -> [Service] {
        guard isSupported, let create else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var services: [Service] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External" else { continue }
            if let service = create(kCFAllocatorDefault, entry) { services.append(service.takeRetainedValue()) }
        }
        return services
    }

    /// Reads a VCP: current value and its maximum, or nil when the panel does not answer.
    ///
    /// Measured on this desk's LG: the first request after an idle gap is dropped, and an empty
    /// reply (`6E 80 BE …`, length byte 0) arrives as often as a real one — a 2026-11-26 run of
    /// back-to-back reads lost roughly one reply in three on both VCPs, whether or not the chip was
    /// primed first. So each attempt writes the request twice, several attempts are made before
    /// deciding the panel does not answer, and callers cache what they read instead of polling.
    static func read(_ service: Service, vcp: UInt8, attempts: Int = 4) -> (current: UInt16, maximum: UInt16)? {
        let request = DDCCommand.read(vcp: vcp)
        for _ in 0..<max(1, attempts) {
            guard write(service, request), write(service, request) else { continue }
            usleep(60_000)
            var reply = [UInt8](repeating: 0, count: 11)
            guard readBytes(service, &reply) else { continue }
            guard reply[0] == DDCCommand.destination, reply[2] == 0x02 else { continue }
            // The frame names the VCP it answers: matching it is what tells a real brightness reply
            // from the previous volume reply the panel repeated.
            guard reply[4] == vcp else { continue }
            guard reply[10] == DDCCommand.replyChecksum(Array(reply[0..<10])) else { continue }
            let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
            guard maximum > 0 else { continue }
            return (current, maximum)
        }
        return nil
    }

    /// Writes a VCP value. The caller has already clamped it to the panel's maximum.
    /// Sent twice: measured here, one Set VCP leaves the value unchanged and the repeat applies it,
    /// while the panel still drops neither a brightness nor a volume write.
    @discardableResult
    static func write(_ service: Service, vcp: UInt8, value: UInt16) -> Bool {
        let packet = DDCCommand.write(vcp: vcp, value: value)
        let first = write(service, packet)
        usleep(60_000)
        return write(service, packet) && first
    }

    private static func write(_ service: Service, _ bytes: [UInt8]) -> Bool {
        guard let writeI2C else { return false }
        let result = bytes.withUnsafeBufferPointer { buffer in
            writeI2C(service, chipAddress, dataAddress, buffer.baseAddress, UInt32(buffer.count))
        }
        return result == 0
    }

    private static func readBytes(_ service: Service, _ bytes: inout [UInt8]) -> Bool {
        guard let readI2C else { return false }
        let result = bytes.withUnsafeMutableBufferPointer { buffer in
            readI2C(service, chipAddress, dataAddress, buffer.baseAddress, UInt32(buffer.count))
        }
        return result == 0
    }
}

/// Software dimming through a display's gamma transfer table. Restored exactly on quit and whenever a
/// display is set back to full.
enum GammaDim {
    static func clamp(_ level: Double) -> Double {
        min(max(level, Double(DisplayBrightnessConfig.gammaMinimum)), 1)
    }

    @discardableResult
    static func apply(_ level: Double, to displayID: CGDirectDisplayID) -> Bool {
        let value = Float(clamp(level))
        return CGSetDisplayTransferByFormula(displayID, 0, value, 1, 0, value, 1, 0, value, 1) == .success
    }

    static func restore(_ displayID: CGDirectDisplayID) {
        CGSetDisplayTransferByFormula(displayID, 0, 1, 1, 0, 1, 1, 0, 1, 1)
    }
}

/// Per-display brightness and the cursor assist. Lazily built (no I/O until a slider asks), all DDC
/// work on one serial queue, never on the main thread and never during a slider drag.
@MainActor
final class DisplayBrightness {
    static let shared = DisplayBrightness()
    static let didUpdateNotification = Notification.Name("com.katikati.displayBrightnessDidUpdate")

    private struct ServiceBox: @unchecked Sendable {
        let value: DDCTransport.Service
    }

    private let queue = DispatchQueue(label: "com.katikati.display.ddc", qos: .userInitiated)
    private var coalescer = DDCWriteCoalescer()
    private var flushWork: DispatchWorkItem?
    private var services: [String: DDCTransport.Service] = [:]
    private var maximums: [String: UInt16] = [:]
    private var ddcLevels: [String: Double] = [:]
    private var gammaLevels: [CGDirectDisplayID: Double] = [:]
    /// VCP `0x62` readback, cached per display so a view build never blocks on I2C twice.
    private var volumeLevels: [String: Double] = [:]
    private var volumeMaximums: [String: UInt16] = [:]
    private var volumeProbed: Set<String> = []
    private var volumeProbeFailures: [String: Int] = [:]
    private var lastVolumeProbe: [String: Date] = [:]
    private var probingVolumeUUIDs: Set<String> = []
    private var probed = false
    private var isProbing = false
    private var lastProbeAttempt = Date.distantPast
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?

    private init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.invalidateDisplayCaches() }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    private func invalidateDisplayCaches() {
        services.removeAll()
        maximums.removeAll()
        ddcLevels.removeAll()
        volumeLevels.removeAll()
        volumeMaximums.removeAll()
        volumeProbed.removeAll()
        volumeProbeFailures.removeAll()
        lastVolumeProbe.removeAll()
        probingVolumeUUIDs.removeAll()
        probed = false
        isProbing = false
        lastProbeAttempt = .distantPast
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }

    // MARK: Non-isolated bridges

    /// Read for SwiftUI property initializers, which are evaluated on the main thread but are not
    /// actor-isolated.
    nonisolated static func levelForCursorScreen() -> Double? {
        MainActor.assumeIsolated { shared.level() }
    }

    /// Write for the same call sites: brightness always acts on the display under the pointer.
    nonisolated static func setOnCursorScreen(_ level: Double) {
        MainActor.assumeIsolated { shared.set(level) }
    }

    /// Volume read for the same call sites. Nil when the panel does not answer VCP `0x62` — the
    /// slider is then hidden, exactly as the brightness slider hides when its read fails.
    nonisolated static func volumeForCursorScreen() -> Double? {
        MainActor.assumeIsolated { shared.volume() }
    }

    nonisolated static func setVolumeOnCursorScreen(_ level: Double) {
        MainActor.assumeIsolated { shared.setVolume(level) }
    }

    // MARK: Target

    /// The display a brightness key, a volume slider or the cursor jump speaks for: the one under
    /// the pointer, else the main display, else the first (`DisplayTargetRule`). This is what makes
    /// F1/F2 useful on a two-display desk.
    static func targetScreen(screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        let mainIndex = NSScreen.main.flatMap { main in screens.firstIndex { $0 === main } }
        guard let index = DisplayTargetRule.index(cursor: NSEvent.mouseLocation,
                                                  frames: screens.map(\.frame),
                                                  mainIndex: mainIndex) else { return nil }
        return screens[index]
    }

    // MARK: Level

    func level(for screen: NSScreen? = nil) -> Double? {
        guard let screen = screen ?? Self.targetScreen(), let id = screen.displayID else { return nil }
        if CGDisplayIsBuiltin(id) != 0 { return DisplayServicesBrightness.current(for: id) }
        guard let uuid = DisplayIdentity.uuidString(for: screen) else { return nil }
        probeIfNeeded()
        if let ddc = ddcLevels[uuid] { return ddc }
        return gammaLevels[id] ?? 1
    }

    func canControlCursorScreen() -> Bool {
        level(for: Self.targetScreen()) != nil
    }

    func set(_ level: Double, for screen: NSScreen? = nil) {
        guard let screen = screen ?? Self.targetScreen(), let id = screen.displayID else { return }
        let clamped = min(max(level, 0), 1)
        if CGDisplayIsBuiltin(id) != 0 {
            DisplayServicesBrightness.set(clamped, for: id)
            return
        }
        guard let uuid = DisplayIdentity.uuidString(for: screen) else { return }
        probeIfNeeded()
        if let service = services[uuid], let maximum = maximums[uuid], DisplayBrightnessConfig.ddcEnabled() {
            ddcLevels[uuid] = clamped
            offerDDC(uuid: uuid, vcp: DisplayVCP.brightness, level: clamped, maximum: maximum, service: service)
            // Post immediately so the Notch HUD tracks key presses without waiting for the 50 ms DDC coalesce.
            DisplayServicesBrightness.postChange(clamped, for: id)
        } else if GammaDim.apply(clamped, to: id) {
            let applied = GammaDim.clamp(clamped)
            gammaLevels[id] = applied
            DisplayServicesBrightness.postChange(applied, for: id)
        }
    }

    // MARK: Volume (VCP 0x62)

    /// The external display's own volume, read once per display and cached. Nil for the built-in
    /// panel (its volume is the system output's) and for any panel that does not answer `0x62`, so
    /// callers hide the control — the graceful degradation the brightness path has when a read
    /// fails, without a software stand-in (gamma can dim, it cannot make a speaker quieter).
    func volume(for screen: NSScreen? = nil) -> Double? {
        guard let screen = screen ?? Self.targetScreen(), let id = screen.displayID,
              CGDisplayIsBuiltin(id) == 0,
              let uuid = DisplayIdentity.uuidString(for: screen) else { return nil }
        probeIfNeeded()
        if !volumeProbed.contains(uuid), !probingVolumeUUIDs.contains(uuid), let service = services[uuid] {
            if let last = lastVolumeProbe[uuid], Date().timeIntervalSince(last) < 3 {
                return volumeLevels[uuid]
            }
            lastVolumeProbe[uuid] = Date()
            probingVolumeUUIDs.insert(uuid)
            let box = ServiceBox(value: service)
            queue.async { [weak self] in
                let reading = DDCTransport.read(box.value, vcp: DisplayVCP.volume)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.probingVolumeUUIDs.remove(uuid)
                    guard let reading else {
                        let failures = (self.volumeProbeFailures[uuid] ?? 0) + 1
                        self.volumeProbeFailures[uuid] = failures
                        if failures >= 2 { self.volumeProbed.insert(uuid) }
                        return
                    }
                    self.volumeMaximums[uuid] = reading.maximum
                    self.volumeLevels[uuid] = Double(reading.current) / Double(reading.maximum)
                    self.volumeProbed.insert(uuid)
                    NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
                }
            }
        }
        return volumeLevels[uuid]
    }

    func isVolumeAvailable(for screen: NSScreen? = nil) -> Bool { volume(for: screen) != nil }

    /// Writes go through the same coalescer as brightness: last value wins per (display, VCP), at
    /// most one transaction per 50 ms, on the serial queue.
    func setVolume(_ level: Double, for screen: NSScreen? = nil) {
        guard let screen = screen ?? Self.targetScreen(), let id = screen.displayID,
              CGDisplayIsBuiltin(id) == 0,
              let uuid = DisplayIdentity.uuidString(for: screen) else { return }
        probeIfNeeded()
        if !volumeProbed.contains(uuid) {
            _ = volume(for: screen)
        }
        guard let service = services[uuid], let maximum = volumeMaximums[uuid] else { return }
        let clamped = min(max(level, 0), 1)
        volumeLevels[uuid] = clamped
        offerDDC(uuid: uuid, vcp: DisplayVCP.volume, level: clamped, maximum: maximum, service: service)
    }

    /// Puts back every software dim and clears the caches (quit path).
    func restoreAll() {
        flushWork?.cancel()
        flushWork = nil
        coalescer.reset()
        for (id, _) in gammaLevels { GammaDim.restore(id) }
        gammaLevels.removeAll()
        invalidateDisplayCaches()
    }

    // MARK: Cursor assist

    /// Moves the pointer to the next (`step > 0`) or previous display at the same fraction of its
    /// edge, so the pointer lands where the user was looking rather than at a corner.
    @discardableResult
    func jumpCursor(step: Int = 1, screens: [NSScreen] = NSScreen.screens) -> Bool {
        guard screens.count > 1, let primary = screens.first else { return false }
        let cursor = NSEvent.mouseLocation
        guard let index = screens.firstIndex(where: { $0.frame.contains(cursor) }) else { return false }
        let target = screens[DisplayMove.destination(from: index, count: screens.count, step: step)]
        let cocoa = CursorCrossingPlan.jump(from: cursor, current: screens[index].frame, target: target.frame)
        let quartz = CGPoint(x: cocoa.x, y: primary.frame.maxY - cocoa.y)
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(quartz)
        CGAssociateMouseAndMouseCursorPosition(1)
        return true
    }

    // MARK: DDC

    /// Opens the services asynchronously on `queue`, matching them to external displays and
    /// recording VCP `0x10` without blocking `@MainActor`.
    private func probeIfNeeded() {
        guard !probed, !isProbing, DisplayBrightnessConfig.ddcEnabled() else { return }
        guard Date().timeIntervalSince(lastProbeAttempt) > 3 else { return }
        lastProbeAttempt = Date()
        let externalUUIDs = NSScreen.screens.compactMap { screen -> String? in
            guard let id = screen.displayID, CGDisplayIsBuiltin(id) == 0 else { return nil }
            return DisplayIdentity.uuidString(for: screen) ?? ""
        }
        guard !externalUUIDs.isEmpty else { return }
        isProbing = true
        let overrides = DDCServiceOrder.storedOverrides()
        queue.async { [weak self] in
            let found = DDCTransport.externalServices()
            let order = DDCServiceOrder.resolve(externals: externalUUIDs,
                                                serviceCount: found.count,
                                                overrides: overrides)
            var matched: [(uuid: String, service: ServiceBox, max: UInt16, level: Double)] = []
            for (index, service) in found.enumerated() {
                guard let uuid = order[index], !uuid.isEmpty else { continue }
                guard let reading = DDCTransport.read(service, vcp: DisplayVCP.brightness) else { continue }
                matched.append((uuid, ServiceBox(value: service), reading.maximum, Double(reading.current) / Double(reading.maximum)))
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isProbing = false
                for item in matched {
                    self.services[item.uuid] = item.service.value
                    self.maximums[item.uuid] = item.max
                    self.ddcLevels[item.uuid] = item.level
                }
                self.probed = !matched.isEmpty
                if !matched.isEmpty {
                    NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
                }
            }
        }
    }

    private func offerDDC(uuid: String, vcp: UInt8, level: Double, maximum: UInt16, service: DDCTransport.Service) {
        let raw = DDCValue.byte(for: level)
        let now = Date()
        if let write = coalescer.offer(displayUUID: uuid, vcp: vcp, value: raw, at: now) {
            send(write, service: service, maximum: maximum)
            return
        }
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            for write in self.coalescer.flush(at: Date()) {
                guard let service = self.services[write.key.displayUUID],
                      let max = self.maximums[write.key.displayUUID] else { continue }
                self.send(write, service: service, maximum: max)
            }
        }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DDCWriteCoalescer.minimumInterval, execute: work)
    }

    private func send(_ write: DDCWriteCoalescer.Write, service: DDCTransport.Service, maximum: UInt16) {
        let value = DDCValue.raw(byte: write.value, maximum: maximum)
        queue.async {
            let succeeded = DDCTransport.write(service, vcp: write.key.vcp, value: value)
            guard succeeded, write.key.vcp == DisplayVCP.brightness, maximum > 0 else { return }
            DispatchQueue.main.async {
                guard let id = NSScreen.screens.first(where: {
                    DisplayIdentity.uuidString(for: $0) == write.key.displayUUID
                })?.displayID else { return }
                DisplayServicesBrightness.postChange(Double(value) / Double(maximum), for: id)
            }
        }
    }
}
