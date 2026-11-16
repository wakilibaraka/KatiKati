import Foundation

/// Phase 21b: the answer rows a launcher shows above app matches — the math result and the web-search
/// shortcut. Pure: the view renders it, the platform layer runs it (copy for math, open for web).
enum LauncherAnswer: Equatable, Sendable {
    case math(expression: String, value: String)
    case web(query: String)
}

enum LauncherAnswers {
    /// Answers for the routed query, or none for plain app search. `.math` yields a row only when the
    /// expression evaluates; `.web` yields one for any non-empty term.
    static func answers(for query: LauncherQuery) -> [LauncherAnswer] {
        switch query {
        case .math(let expression):
            guard let value = CalculatorEngine.evaluate(expression) else { return [] }
            return [.math(expression: expression, value: CalculatorEngine.format(value))]
        case .web(let terms):
            return terms.isEmpty ? [] : [.web(query: terms)]
        default:
            return []
        }
    }

    /// Evaluates prefix-free inline math only when the query contains at least one digit, an arithmetic operator,
    /// and no non-math letters. This prevents hyphenated app or model names (e.g. claude-3-5, utf-8) from triggering math.
    static func inlineMathAnswer(for text: String) -> LauncherAnswer? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains(where: { $0.isNumber }) else { return nil }
        let operators = CharacterSet(charactersIn: "+*/%^×÷")
        let hasPrimaryOp = trimmed.rangeOfCharacter(from: operators) != nil
        let hasInfixMinus = trimmed.contains(" - ") || trimmed.range(of: #"\d\s*-\s*\d"#, options: .regularExpression) != nil
        guard hasPrimaryOp || hasInfixMinus else { return nil }

        // Reject any letters other than multiplication 'x'/'X'
        let disallowedLetters = CharacterSet.letters.subtracting(CharacterSet(charactersIn: "xX"))
        guard trimmed.rangeOfCharacter(from: disallowedLetters) == nil else { return nil }

        guard let value = CalculatorEngine.evaluate(trimmed) else { return nil }
        return .math(expression: trimmed, value: CalculatorEngine.format(value))
    }
}
