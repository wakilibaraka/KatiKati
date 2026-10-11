import CoreGraphics
import Foundation

/// Pure helpers for the Capture button (Phase 7A-P5): turning recognised text blocks into reading-order text, and
/// deciding which scanned payloads may be offered as links.
enum CaptureRules {
    struct Block: Equatable, Sendable {
        var text: String
        /// Normalised bounding box, Vision convention: origin bottom-left, y grows upward.
        var box: CGRect
    }

    /// Reading order: top to bottom; blocks whose vertical centres are within a line's height count as one line and
    /// read left to right. Blank blocks are dropped; lines are joined with newlines.
    static func readingOrder(_ blocks: [Block]) -> String {
        let usable = blocks.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let sorted = usable.sorted { $0.box.midY > $1.box.midY }
        var lines: [[Block]] = []
        for block in sorted {
            if let last = lines.last, let ref = last.first, abs(ref.box.midY - block.box.midY) < max(ref.box.height, block.box.height) * 0.5 {
                lines[lines.count - 1].append(block)
            } else {
                lines.append([block])
            }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }

    /// Only web links are offered as clickable; everything else (Wi-Fi codes, `tel:`, custom schemes) is shown as text.
    static func openableURL(_ payload: String) -> URL? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Distinct non-empty payloads in scan order.
    static func uniquePayloads(_ payloads: [String]) -> [String] {
        var seen = Set<String>()
        return payloads.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
