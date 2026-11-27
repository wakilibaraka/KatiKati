import XCTest
@testable import KatiKati

final class UsageThresholdPolicyTests: XCTestCase {
    func testFiresOnceAt80AndOnceAt95PerResetWindow() {
        var policy = UsageThresholdPolicy()
        let reset1 = Date(timeIntervalSince1970: 1_800_000_000)
        let reset2 = Date(timeIntervalSince1970: 1_800_018_000)

        func limits(_ pct: Double, reset: Date) -> [AgentProvider: AgentLimits] {
            [.claude: AgentLimits(
                provider: .claude,
                windows: [AgentLimitWindow(id: "5h", kind: .session, minutes: 300, scope: nil, usedPercent: pct, resetsAt: reset)],
                observedAt: Date()
            )]
        }

        XCTAssertTrue(policy.evaluate(limits: limits(79, reset: reset1)).isEmpty)

        let warn = policy.evaluate(limits: limits(82, reset: reset1))
        XCTAssertEqual(warn, [AIUsageAlert(provider: .claude, usedPercent: 82, resetsAt: reset1, severity: .warning)])

        // Repeating at 85% does not re-fire 80%.
        XCTAssertTrue(policy.evaluate(limits: limits(85, reset: reset1)).isEmpty)

        // Crossing 95% fires critical once.
        let crit = policy.evaluate(limits: limits(96, reset: reset1))
        XCTAssertEqual(crit, [AIUsageAlert(provider: .claude, usedPercent: 96, resetsAt: reset1, severity: .critical)])
        XCTAssertTrue(policy.evaluate(limits: limits(99, reset: reset1)).isEmpty)

        // New reset window allows alerting again.
        let nextWindow = policy.evaluate(limits: limits(81, reset: reset2))
        XCTAssertEqual(nextWindow.count, 1)
        XCTAssertEqual(nextWindow.first?.severity, .warning)
    }

    func testJumpPastBothThresholdsEmitsSingleCriticalAlert() {
        var policy = UsageThresholdPolicy()
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let limits: [AgentProvider: AgentLimits] = [
            .codex: AgentLimits(
                provider: .codex,
                windows: [AgentLimitWindow(id: "5h", kind: .session, minutes: 300, scope: nil, usedPercent: 97, resetsAt: reset)],
                observedAt: Date()
            )
        ]
        let first = policy.evaluate(limits: limits)
        XCTAssertEqual(first, [AIUsageAlert(provider: .codex, usedPercent: 97, resetsAt: reset, severity: .critical)])
        XCTAssertTrue(policy.evaluate(limits: limits).isEmpty)
    }
}
