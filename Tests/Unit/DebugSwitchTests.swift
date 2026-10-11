import XCTest

/// `DebugSwitch` 的极性锁：迁移前各调用点的 `!= "0"` / `== "1"` 语义必须逐字保留。
final class DebugSwitchTests: XCTestCase {
    func testKillSwitchIsOnUnlessExplicitlyZero() {
        let s = DebugSwitch.eventAxAsync
        XCTAssertEqual(s.kind, .killSwitch)
        XCTAssertTrue(s.isEnabled(in: [:]))
        XCTAssertTrue(s.isEnabled(in: [s.rawValue: "1"]))
        XCTAssertTrue(s.isEnabled(in: [s.rawValue: "false"]), "只有字面 \"0\" 才关，与迁移前一致")
        XCTAssertFalse(s.isEnabled(in: [s.rawValue: "0"]))
    }

    func testTraceIsOffUnlessExplicitlyOne() {
        let s = DebugSwitch.hoverTrace
        XCTAssertEqual(s.kind, .trace)
        XCTAssertFalse(s.isEnabled(in: [:]))
        XCTAssertFalse(s.isEnabled(in: [s.rawValue: "true"]), "只有字面 \"1\" 才开，与迁移前一致")
        XCTAssertTrue(s.isEnabled(in: [s.rawValue: "1"]))
    }

    func testAcceptedBalancedInsetsAreEnabledWithoutLaunchOverrides() {
        let control = DebugSwitch.stripBalancedInsets
        XCTAssertTrue(control.isEnabled(in: [:]))
        XCTAssertTrue(control.isEnabled(in: [control.rawValue: "1"]))
        XCTAssertFalse(control.isEnabled(in: [control.rawValue: "0"]))
    }

    func testValueReturnsRawStringOrNil() {
        let s = DebugSwitch.reconcileAxTimeoutMs
        XCTAssertEqual(s.kind, .value)
        XCTAssertNil(s.value(in: [:]))
        XCTAssertEqual(s.value(in: [s.rawValue: " 250 "]), " 250 ")
    }

    func testEveryCaseHasDockPrefixAndUniqueRawValue() {
        let raws = DebugSwitch.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)
        for raw in raws { XCTAssertTrue(raw.hasPrefix("DOCK_"), raw) }
    }

    /// Dev permission bypass: trace polarity, off by default (=1 only), never a kill switch —
    /// a wrong polarity here would silently skip onboarding for real users.
    func testDevSkipPermissionsIsTracePolarity() {
        let s = DebugSwitch.devSkipPermissions
        XCTAssertEqual(s.rawValue, "DOCK_DEV_SKIP_PERMISSIONS")
        XCTAssertEqual(s.kind, .trace)
        XCTAssertFalse(s.isEnabled(in: [:]))
        XCTAssertFalse(s.isEnabled(in: [s.rawValue: "0"]))
        XCTAssertFalse(s.isEnabled(in: [s.rawValue: "true"]), "只有字面 \"1\" 才开，同 trace 口径")
        XCTAssertTrue(s.isEnabled(in: [s.rawValue: "1"]))
    }

    /// 「不可能误打开发动机」的另一半：除字面 `"1"` 之外的一切取值都必须是关。
    /// 手写 `launchctl setenv DOCK_DEV_SKIP_PERMISSIONS true` 是很自然的误用，
    /// 而 killSwitch 极性（`!= "0"`）下那正好是「开」——所以极性只能是 `.trace`。
    func testDevSkipPermissionsTurnsOnOnlyForLiteralOne() {
        let s = DebugSwitch.devSkipPermissions
        let raw = s.rawValue
        XCTAssertEqual(s.kind, .trace, "改成 killSwitch 极性的话，没设这个变量的正式用户会被整体跳过授权引导")
        for value in ["", "0", "false", "true", "TRUE", "on", "yes", "y", "1.0", "01", " 1", "1 ", "+1"] {
            XCTAssertFalse(s.isEnabled(in: [raw: value]), "\(raw)=\(value) 不该开")
        }
        XCTAssertFalse(s.isEnabled(in: [:]))
        XCTAssertTrue(s.isEnabled(in: [raw: "1"]))
    }

    /// 生产调用点（AppDelegate / AccessibilityPermissionModel / PermissionRecoveryCoordinator）
    /// 读的是无参 `isEnabled()`，也就是**真进程环境**。这里真设一次再真清一次，
    /// 证明极性在执行路径上也是「关 → 开 → 关」，并且不会漏到后面的测试里去。
    func testDevSkipPermissionsProcessEnvironmentRoundTrip() {
        let s = DebugSwitch.devSkipPermissions
        defer { unsetenv(s.rawValue) }

        XCTAssertFalse(s.isEnabled())
        setenv(s.rawValue, "1", 1)
        XCTAssertTrue(s.isEnabled())
        unsetenv(s.rawValue)
        XCTAssertFalse(s.isEnabled())
        setenv(s.rawValue, "true", 1)
        XCTAssertFalse(s.isEnabled(), "进程环境里也只有字面 1 才算开")
    }
}
