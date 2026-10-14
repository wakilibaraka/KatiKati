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
}
