import XCTest
@testable import KatiKati

/// 首次运行引导的弹出判据。
///
/// OB-1 之后这里锁的是**「要不要弹」与「弹出来给不给系统 Dock 选项」是两件事**：
/// 沙箱和 CFPreferences 抖动都只影响后者。旧实现把两者混成一条，于是一次读取失败或一次
/// 只读卷运行就能永久吞掉整扇引导，而用户完全无从察觉。
final class WelcomeGuideDecisionTests: XCTestCase {
    func testPresentsWhenDockIsVisibleAndNothingHasBeenSeen() {
        XCTAssertEqual(
            WelcomeGuideDecision.evaluate(
                hasSeenWelcome: false,
                canWriteDockPreferences: true,
                dockAutohideEnabled: false
            ),
            .present(offersNativeDock: true)
        )
    }

    func testAlreadySeenNeverPresentsAgain() {
        // 看过就是看过，后面几个条件都不该推翻它——包括用户看完之后又把 Dock 改回常驻。
        for canWrite in [true, false] {
            for dockAutohide in [true, false, nil] as [Bool?] {
                XCTAssertEqual(
                    WelcomeGuideDecision.evaluate(
                        hasSeenWelcome: true,
                        canWriteDockPreferences: canWrite,
                        dockAutohideEnabled: dockAutohide
                    ),
                    .skipAndMarkSeen,
                    "canWrite = \(canWrite), dockAutohideEnabled = \(String(describing: dockAutohide))"
                )
            }
        }
    }

    func testDockAlreadyHiddenSkipsAndMarksSeen() {
        // 引导没有意义了。标记掉，免得用户哪天故意把 Dock 调回常驻时，
        // 被一个「首次运行引导」突然拦住。
        XCTAssertEqual(
            WelcomeGuideDecision.evaluate(
                hasSeenWelcome: false,
                canWriteDockPreferences: true,
                dockAutohideEnabled: true
            ),
            .skipAndMarkSeen
        )
    }

    /// **OB-1 的行为变更。** 沙箱里写不了 Dock 偏好，只意味着第三幕不该出现那组系统 Dock
    /// 选项——引导本身（Dock、Island、菜单栏枢纽、权限、节奏）全都和沙箱无关，没有理由
    /// 让一台沙箱机器永远看不到产品首秀。
    func testSandboxedPresentsWithoutTheNativeDockOptions() {
        XCTAssertEqual(
            WelcomeGuideDecision.evaluate(
                hasSeenWelcome: false,
                canWriteDockPreferences: false,
                dockAutohideEnabled: false
            ),
            .present(offersNativeDock: false)
        )
    }

    /// `currentAutohideState()` 返回 nil 表示"这次没读到"，不表示"Dock 没自动隐藏"。
    /// 读取失败不再能吞掉引导：照弹，只是别把「已看过」写下去——那只该由用户自己结束时写。
    func testUnreadableDockStateStillPresents() {
        XCTAssertEqual(
            WelcomeGuideDecision.evaluate(
                hasSeenWelcome: false,
                canWriteDockPreferences: true,
                dockAutohideEnabled: nil
            ),
            .present(offersNativeDock: true)
        )
    }

    /// 沙箱 + 读不到：仍然弹，仍然不给那组选项。
    func testSandboxWithUnreadableStatePresentsWithoutOptions() {
        XCTAssertEqual(
            WelcomeGuideDecision.evaluate(
                hasSeenWelcome: false,
                canWriteDockPreferences: false,
                dockAutohideEnabled: nil
            ),
            .present(offersNativeDock: false)
        )
    }

    // MARK: - 跳过之后不能被晾着

    /// 全新 Mac、还没给辅助功能、用户在首秀里按了 Skip：恢复窗必须接手，否则任务条停在
    /// 受限模式，而屏幕上没有任何一扇窗解释权限该去哪开。
    func testSkipWithoutAccessibilityHandsOverToTheRecoveryWindow() {
        XCTAssertTrue(
            WelcomeGuideHandover.shouldPresentRecoveryWindow(
                isFirstRunDeferred: true,
                isTrusted: false,
                hasPresentation: true
            )
        )
    }

    func testNoHandoverWhenTheGrantLandedWithoutLeavingTheGuide() {
        XCTAssertFalse(
            WelcomeGuideHandover.shouldPresentRecoveryWindow(
                isFirstRunDeferred: true,
                isTrusted: true,
                hasPresentation: true
            )
        )
    }

    /// 「Show Setup Guide Again」是后置入口，关掉它不该凭空弹出一扇权限窗。
    func testReplayNeverHandsOverToTheRecoveryWindow() {
        XCTAssertFalse(
            WelcomeGuideHandover.shouldPresentRecoveryWindow(
                isFirstRunDeferred: false,
                isTrusted: false,
                hasPresentation: true
            )
        )
    }

    // MARK: - 勾选 → 要写哪几个键

    /// 这一步最容易把两个最小化选项接反，而只构造 `NativeDockRecommendations` 的测试抓不到，
    /// 所以四种组合逐字段断言。
    func testFullSelectionMapsToAllThreeWrites() {
        let recommendations = WelcomeGuideSelection.recommended.recommendations(hideDelay: 999)
        XCTAssertEqual(recommendations.autoHideDelay, 999)
        XCTAssertTrue(recommendations.minimizeEffectScale)
        XCTAssertTrue(recommendations.minimizeIntoAppIcon)
        XCTAssertFalse(recommendations.isEmpty)
    }

    func testHideOnlySelectionLeavesMinimizeKeysUntouched() {
        let recommendations = WelcomeGuideSelection(
            hidesDock: true,
            usesScaleMinimizeEffect: false,
            minimizesIntoAppIcon: false
        ).recommendations(hideDelay: 999)
        XCTAssertEqual(recommendations.autoHideDelay, 999)
        XCTAssertFalse(recommendations.minimizeEffectScale)
        XCTAssertFalse(recommendations.minimizeIntoAppIcon)
    }

    /// 不勾隐藏 = **完全不碰** autohide（nil），不是「写个默认值」。
    func testMinimizeOnlySelectionCarriesNoAutoHideDelay() {
        let recommendations = WelcomeGuideSelection(
            hidesDock: false,
            usesScaleMinimizeEffect: true,
            minimizesIntoAppIcon: true
        ).recommendations(hideDelay: 999)
        XCTAssertNil(recommendations.autoHideDelay)
        XCTAssertTrue(recommendations.minimizeEffectScale)
        XCTAssertTrue(recommendations.minimizeIntoAppIcon)
    }

    /// 两个最小化选项各自独立，别接反。
    func testEachMinimizeOptionMapsToItsOwnField() {
        let scaleOnly = WelcomeGuideSelection(
            hidesDock: false,
            usesScaleMinimizeEffect: true,
            minimizesIntoAppIcon: false
        ).recommendations(hideDelay: 999)
        XCTAssertTrue(scaleOnly.minimizeEffectScale)
        XCTAssertFalse(scaleOnly.minimizeIntoAppIcon)

        let iconOnly = WelcomeGuideSelection(
            hidesDock: false,
            usesScaleMinimizeEffect: false,
            minimizesIntoAppIcon: true
        ).recommendations(hideDelay: 999)
        XCTAssertFalse(iconOnly.minimizeEffectScale)
        XCTAssertTrue(iconOnly.minimizeIntoAppIcon)
    }

    func testEmptySelectionMapsToEmptyRecommendations() {
        let selection = WelcomeGuideSelection(
            hidesDock: false,
            usesScaleMinimizeEffect: false,
            minimizesIntoAppIcon: false
        )
        XCTAssertTrue(selection.isEmpty)
        XCTAssertTrue(selection.recommendations(hideDelay: 999).isEmpty)
    }
}
