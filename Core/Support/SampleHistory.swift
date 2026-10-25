import Foundation

/// Fixed-length rolling window of samples behind the dock's sparklines (CPU / RAM / disk).
struct SampleHistory: Equatable, Sendable {
    let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int = 30) { self.capacity = max(1, capacity) }

    mutating func append(_ value: Double) {
        values.append(value.isFinite ? max(0, value) : 0)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    /// Samples scaled to 0...1, left-padded with zeros to `capacity` so a young window draws on the right edge.
    /// `ceiling` pins the scale (percentages pass 1); `nil` scales to the window's peak.
    func normalized(ceiling: Double? = nil) -> [Double] {
        let top = ceiling ?? (values.max() ?? 0)
        let scaled = values.map { top > 0 ? min(1, $0 / top) : 0 }
        return Array(repeating: 0, count: capacity - scaled.count) + scaled
    }

    var latest: Double { values.last ?? 0 }
}
