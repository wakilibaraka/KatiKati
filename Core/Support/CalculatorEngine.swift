import Foundation

/// Tiny expression evaluator for the Calculator tile: `+ - * / %`, parentheses, unary minus, decimals; `x`, `×`, `÷`
/// are accepted as operators. Returns nil for anything malformed or non-finite (never traps).
enum CalculatorEngine {
    static func evaluate(_ text: String) -> Double? {
        var p = Parser(chars: Array(normalise(text)))
        guard let v = p.expression(), p.atEnd, v.isFinite else { return nil }
        return v
    }

    /// `0.1 + 0.2` → `0.3`; at most 15 significant digits, no trailing zeros, no exponent for ordinary sizes.
    /// Integer values up to `9e15` (`2^53 - 1`) are returned directly before scaling by `1e9` so `value * 1e9`
    /// never overflows IEEE-754 53-bit significand precision on large results.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 9e15 { return String(Int64(value)) }
        let intPart = value.rounded(.towardZero)
        let fracPart = ((value - intPart) * 1e9).rounded() / 1e9
        let r = intPart + fracPart
        if r == r.rounded(), abs(r) < 9e15 { return String(Int64(r)) }
        var s = String(format: "%.9f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func normalise(_ t: String) -> String {
        t.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "x", with: "*").replacingOccurrences(of: "X", with: "*")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        var atEnd: Bool { i >= chars.count }

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while let c = peek, c == "+" || c == "-" {
                i += 1
                guard let r = term() else { return nil }
                v = c == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() -> Double? {
            guard var v = factor() else { return nil }
            while let c = peek, c == "*" || c == "/" {
                i += 1
                guard let r = factor() else { return nil }
                if c == "/" { if r == 0 { return nil }; v /= r } else { v *= r }
            }
            return v
        }

        mutating func factor() -> Double? {
            if peek == "-" { i += 1; return factor().map { -$0 } }
            if peek == "+" { i += 1; return factor() }
            guard var v = primary() else { return nil }
            while peek == "%" { i += 1; v /= 100 }
            return v
        }

        mutating func primary() -> Double? {
            if peek == "(" {
                i += 1
                guard let v = expression(), peek == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            var dot = false
            while let c = peek, c.isASCII, c.isNumber || (c == "." && !dot) {
                if c == "." { dot = true }
                i += 1
            }
            guard i > start else { return nil }
            return Double(String(chars[start..<i]))
        }

        var peek: Character? { i < chars.count ? chars[i] : nil }
    }
}
