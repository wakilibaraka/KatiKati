import AppKit
import SwiftUI

/// Calculator tile — a vibrant keypad board (chunky keys, hero result) driving the same
/// `CalculatorEngine` as the typed expression: both input paths edit one string, so they can't
/// disagree. Parens and the decimal comma stay reachable by typing.
struct CalculatorTile: View {
    let env: TileEnv
    let width: CGFloat
    let height: CGFloat
    @State private var expression = ""

    private var result: String {
        guard !expression.isEmpty else { return "0" }
        return CalculatorEngine.evaluate(expression).map(CalculatorEngine.format) ?? "…"
    }

    var body: some View {
        BandTile(env: env, kind: .calculator, width: width, height: height, header: { Text("Calculator") }, content: {
            VStack(spacing: 6) {
                TextField("Expression", text: $expression).textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium)).foregroundColor(env.secondary)
                    .frame(height: 14)
                Text(verbatim: result)
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundColor(env.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(1).minimumScaleFactor(0.5)
                VStack(spacing: 5) {
                    keyRow(["C", "⌫", "%", "÷"])
                    keyRow(["7", "8", "9", "×"])
                    keyRow(["4", "5", "6", "−"])
                    keyRow(["1", "2", "3", "+"])
                    // 0 spans two columns: the nested HStack keeps every key the same width.
                    HStack(spacing: 5) {
                        key("0")
                        HStack(spacing: 5) {
                            key(".")
                            key("=")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        })
    }

    private func keyRow(_ keys: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { key($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Digits sit on quiet blocks, operators on the accent — the colour-block rhythm of an
    /// iPadOS widget keypad. Glyphs are verbatim (numerals and symbols, never localized).
    private func key(_ label: String) -> some View {
        let isOp = "C⌫%÷×−+=".contains(label)
        return Button { tap(label) } label: {
            Text(verbatim: label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(isOp ? env.onAccent(.calculator) : env.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOp ? env.accent(.calculator) : env.text.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(label == "⌫" ? Text("Delete") : Text(verbatim: label))
    }

    private func tap(_ label: String) {
        switch label {
        case "C": expression = ""
        case "⌫": if !expression.isEmpty { expression.removeLast() }
        case "=": if let v = CalculatorEngine.evaluate(expression) { expression = CalculatorEngine.format(v) }
        default: expression.append(label)
        }
    }
}
