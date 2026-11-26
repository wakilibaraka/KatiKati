import CoreGraphics
import Foundation

/// MD-5 — pure display-control rules. Everything here is AppKit- and IOKit-free so it is
/// dual-compiled into the unit tests; the private-API transport and the gamma fallback live in
/// `Platform/Display/DisplayBrightness.swift`.

/// Settings keys and bounds for per-display brightness.
enum DisplayBrightnessConfig {
    /// Feature gate. Off → no DDC node is opened and externals keep the software fallback.
    static let ddcKey = "com.katikati.display.ddc.v1"
    /// Optional `displayUUID → index` override for the DDC node order (a desk where the registry
    /// order does not match the display order).
    static let mapKey = "com.katikati.display.ddcMap"
    /// Software dimming never goes below this, so a mis-set slider cannot make a display unusable.
    static let gammaMinimum: CGFloat = 0.15

    static func ddcEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: ddcKey) as? Bool) ?? true
    }
}

/// Which display a per-display control speaks for. Pure, so both brightness and volume share one
/// rule and the tests pin it: the display containing the pointer, else the main display, else the
/// first. A pointer in a dead wall (the 164 pt band beside a stacked desk) falls back rather than
/// snapping to the nearest display by distance — the user is not pointing at anything.
enum DisplayTargetRule {
    static func index(cursor: CGPoint, frames: [CGRect], mainIndex: Int?) -> Int? {
        guard !frames.isEmpty else { return nil }
        if let index = frames.firstIndex(where: { $0.contains(cursor) }) { return index }
        if let mainIndex, frames.indices.contains(mainIndex) { return mainIndex }
        return 0
    }
}

/// Whether a per-display dock should wear the focus rim. Pure so the rule is pinned: only when a
/// second display exists (one display has nothing to disambiguate, and its pixels stay untouched),
/// and only on the display macOS reports as focused (`NSScreen.main`, the key-window screen).
enum ActiveDockCue {
    static func shows(stripUUID: String?, activeUUID: String?, screenCount: Int) -> Bool {
        guard screenCount > 1, let stripUUID, let activeUUID else { return false }
        return stripUUID == activeUUID
    }
}

/// The two encodings a per-display value travels through: the coalescer's 0–255 byte and the
/// panel's own raw range (its VCP reply's `maximum`, usually 100 — not 255). Keeping both
/// conversions in one place is what stops a 100 % slider from writing 39 % on a panel whose maximum
/// is 100: encode against the panel range, then scale again as if the byte were a 0–255 fraction,
/// and the value shrinks by `maximum / 255`.
enum DDCValue {
    /// A control level (0…1) as the 0–255 byte the coalescer throttles.
    static func byte(for level: Double) -> UInt8 {
        UInt8((min(max(level, 0), 1) * 255).rounded())
    }

    /// A 0–255 byte as the panel's raw range, rounded and clamped to `maximum`.
    static func raw(byte: UInt8, maximum: UInt16) -> UInt16 {
        guard maximum > 0 else { return 0 }
        let scaled = (UInt32(byte) * UInt32(maximum) + 127) / 255
        return UInt16(min(scaled, UInt32(maximum)))
    }
}

/// The DDC/CI packets that travel over the AV service's I2C tunnel, in one pure place so the byte
/// layout is pinned by tests instead of only by hardware. Every message is framed by the display
/// address (`0x6E`) and the host address (`0x51`); both are folded into the trailing XOR checksum.
enum DDCCommand {
    /// Destination byte: the monitor's DDC/CI address.
    static let destination: UInt8 = 0x6E
    /// Source byte: this host.
    static let source: UInt8 = 0x51

    /// "Get VCP Feature" request. The reply (11 bytes) carries the maximum in bytes 6…7 and the
    /// current value in bytes 8…9.
    static func read(vcp: UInt8) -> [UInt8] {
        var bytes: [UInt8] = [0x82, 0x01, vcp]
        bytes.append(checksum(bytes))
        return bytes
    }

    /// "Set VCP Feature" request. `value` is already in the panel's raw range (`DDCValue`).
    static func write(vcp: UInt8, value: UInt16) -> [UInt8] {
        let high = UInt8(truncatingIfNeeded: value >> 8)
        let low = UInt8(truncatingIfNeeded: value & 0xFF)
        var bytes: [UInt8] = [0x84, 0x03, vcp, high, low]
        bytes.append(checksum(bytes))
        return bytes
    }

    /// XOR of the destination, the source and every payload byte.
    static func checksum(_ payload: [UInt8]) -> UInt8 {
        payload.reduce(destination ^ source, ^)
    }

    /// The checksum a display's reply carries: the same XOR with `0x50` substituted for the two
    /// address bytes. Pinned by the reply this desk's LG panel returns.
    static func replyChecksum(_ reply: [UInt8]) -> UInt8 {
        reply.reduce(0x50, ^)
    }
}

/// Public MCCS/DDC-CI VCP codes used here.
enum DisplayVCP {
    static let brightness: UInt8 = 0x10
    static let volume: UInt8 = 0x62
    /// Capability-string read; used only by the manual probe.
    static let capabilities: UInt8 = 0xDF
}

/// Pure last-value-wins throttle for DDC writes, tested without any I/O: a slider drag offers many
/// values, only the newest per (display, VCP) is ever written, and never more often than the panel
/// can take.
struct DDCWriteCoalescer: Equatable, Sendable {
    struct Key: Hashable, Sendable {
        let displayUUID: String
        let vcp: UInt8
    }

    struct Write: Equatable, Sendable {
        let key: Key
        let value: UInt8
    }

    /// DDC/CI needs ~40 ms between transactions; anything faster is dropped, never queued.
    static let minimumInterval: TimeInterval = 0.05

    /// The newest value per key that has not been written yet.
    private(set) var pending: [Key: UInt8] = [:]
    private(set) var lastSentAt: [Key: Date] = [:]

    /// Offers a value. Returns a write to issue now when the throttle window is open, otherwise nil
    /// and keeps only the newest value for `flush`.
    mutating func offer(displayUUID: String, vcp: UInt8, value: UInt8, at now: Date) -> Write? {
        let key = Key(displayUUID: displayUUID, vcp: vcp)
        pending[key] = value
        if let previous = lastSentAt[key], now.timeIntervalSince(previous) < Self.minimumInterval {
            return nil
        }
        return take(key, at: now)
    }

    /// Writes whose throttle window has opened since the last call.
    mutating func flush(at now: Date) -> [Write] {
        pending.keys.sorted {
            $0.displayUUID == $1.displayUUID ? $0.vcp < $1.vcp : $0.displayUUID < $1.displayUUID
        }.compactMap { key in
            guard let previous = lastSentAt[key] else { return take(key, at: now) }
            guard now.timeIntervalSince(previous) >= Self.minimumInterval else { return nil }
            return take(key, at: now)
        }
    }

    /// Forgets every pending write and throttle stamp (display change, quit).
    mutating func reset() {
        pending.removeAll()
        lastSentAt.removeAll()
    }

    private mutating func take(_ key: Key, at now: Date) -> Write? {
        guard let value = pending.removeValue(forKey: key) else { return nil }
        lastSentAt[key] = now
        return Write(key: key, value: value)
    }
}

/// Maps external displays (in their UUID order) to the DDC service list, honouring the optional
/// `com.katikati.display.ddcMap` override when the registry order does not match the desk.
enum DDCServiceOrder {
    static func resolve(externals: [String], serviceCount: Int, overrides: [String: Int] = [:]) -> [String?] {
        guard serviceCount > 0 else { return [] }
        var slots = [String?](repeating: nil, count: serviceCount)
        var pending: [String] = []
        for uuid in externals {
            if let index = overrides[uuid], slots.indices.contains(index), slots[index] == nil {
                slots[index] = uuid
            } else {
                pending.append(uuid)
            }
        }
        for uuid in pending {
            guard let free = (0..<serviceCount).first(where: { slots[$0] == nil }) else { break }
            slots[free] = uuid
        }
        return slots
    }

    static func storedOverrides(_ defaults: UserDefaults = .standard) -> [String: Int] {
        (defaults.dictionary(forKey: DisplayBrightnessConfig.mapKey) as? [String: Int]) ?? [:]
    }
}

/// Pure plan for "jump the cursor to the next display" and for crossing mismatched edges.
enum CursorCrossingPlan {
    /// Maps the pointer onto `target` by its fraction of `current`, entering just inside the edge it
    /// travels toward, so a dead-wall overhang never matters.
    static func jump(from cursor: CGPoint, current: CGRect, target: CGRect, inset: CGFloat = 2) -> CGPoint {
        guard current.width > 0, current.height > 0, target.width > 0, target.height > 0 else { return cursor }
        let step = max(0, inset)
        let fx = min(max((cursor.x - current.minX) / current.width, 0), 1)
        let fy = min(max((cursor.y - current.minY) / current.height, 0), 1)
        if abs(target.midX - current.midX) >= abs(target.midY - current.midY) {
            let x = target.midX >= current.midX ? target.minX + step : target.maxX - step
            let y = target.minY + fy * target.height
            return CGPoint(x: x, y: min(max(y, target.minY + step), target.maxY - step))
        }
        let y = target.midY >= current.midY ? target.minY + step : target.maxY - step
        let x = target.minX + fx * target.width
        return CGPoint(x: min(max(x, target.minX + step), target.maxX - step), y: y)
    }

    /// A point no display contains (the 164 pt band beside a stacked desk, for example).
    static func isDeadWall(_ point: CGPoint, screens: [CGRect]) -> Bool {
        !screens.contains { $0.contains(point) }
    }
}
