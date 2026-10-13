import Foundation

/// Phase 13: edge-bar (deck) feel and look beyond the older per-key settings. One JSON blob in `com.katikati.edge.prefs`.

/// 13c: how much the button under the pointer grows. Raw values are stored; never rename them.
enum EdgeMagnifyAmount: String, CaseIterable, Codable, Sendable {
    case subtle, standard, bold
    var peak: Double {
        switch self {
        case .subtle: return 1.25
        case .standard: return 1.55
        case .bold: return 1.85
        }
    }
}

/// 13l: the edge bar's button artwork. `classic` is the original look.
enum EdgeIconSet: String, CaseIterable, Codable, Sendable { case classic, modern, realistic }

/// 13l: the plate behind every edge-bar flyout. `modern` is the default; `glass` is the earlier frosted look as a preset.
enum EdgeFlyoutStyle: String, CaseIterable, Codable, Sendable { case modern, glass }

struct EdgeBarPrefs: Equatable, Codable, Sendable {
    static let key = "com.katikati.edge.prefs"
    static let openDelayRange: ClosedRange<Double> = 0...1.5
    static let defaultOpenDelay = 0.4
    static let defaultSensitivity = 0.25

    /// Seconds the pointer must stay on the edge pill before the bar opens (13a).
    var openDelay = EdgeBarPrefs.defaultOpenDelay
    /// 0…1 — how generous the edge hot zone is (13j).
    var sensitivity = EdgeBarPrefs.defaultSensitivity
    var magnifyAmount = EdgeMagnifyAmount.standard
    var iconSet = EdgeIconSet.classic
    var flyoutStyle = EdgeFlyoutStyle.modern

    func clamped() -> EdgeBarPrefs {
        var p = self
        p.openDelay = openDelay.isFinite ? min(max(openDelay, Self.openDelayRange.lowerBound), Self.openDelayRange.upperBound) : Self.defaultOpenDelay
        p.sensitivity = sensitivity.isFinite ? min(max(sensitivity, 0), 1) : Self.defaultSensitivity
        return p
    }

    /// Extra hot-zone padding around the resting pill. The default sensitivity reproduces the older fixed (2, 6) inset.
    var zoneInset: (dx: Double, dy: Double) {
        let s = clamped().sensitivity
        return (dx: 8 * s, dy: 24 * s)
    }

    static func load(_ defaults: UserDefaults = .standard) -> EdgeBarPrefs {
        guard let data = defaults.data(forKey: key), let p = try? JSONDecoder().decode(EdgeBarPrefs.self, from: data) else { return EdgeBarPrefs() }
        return p.clamped()
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(clamped()) { defaults.set(data, forKey: Self.key) }
    }
}

/// 13a/13d: the pointer must rest on the pill for `delay` before the bar opens, and a pointer left sitting on the pill after
/// the bar folded (or while another bar is busy) does nothing until it leaves and comes back.
struct EdgeDwell: Equatable, Sendable {
    private var enteredAt: Date?
    private(set) var armed = true

    /// Feed one poll. Returns true exactly when the dwell completes.
    mutating func update(inside: Bool, now: Date, delay: TimeInterval) -> Bool {
        guard inside else { enteredAt = nil; armed = true; return false }
        guard armed else { return false }
        let start = enteredAt ?? now
        enteredAt = start
        guard now.timeIntervalSince(start) >= delay else { return false }
        enteredAt = nil
        return true
    }

    /// The bar is open (or folding): ignore the pointer until it leaves the zone.
    mutating func disarm() { enteredAt = nil; armed = false }
}
