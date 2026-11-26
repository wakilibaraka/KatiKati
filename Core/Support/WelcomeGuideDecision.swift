import Foundation

/// 首次运行要不要弹那扇六幕引导。
///
/// 纯决策，不碰 I/O，可单测。调用方（`AppDelegate`）负责读系统 Dock 状态、弹窗、写标记。
///
/// ## OB-1：引导不再取决于系统 Dock 的读取结果
///
/// 旧实现里「读不到系统 Dock 状态」和「沙箱里写不了 Dock 偏好」都会把整扇窗吞掉：前者靠
/// `skipWithoutMarking` 下次再判，后者直接把 `hasSeenWelcome` 置位。那套取舍在引导**只是**
/// 「建议隐藏系统 Dock」一句话时成立；现在它是产品首秀，为了让一个身体不出现的按钮而扣掉
/// 整个首秀，代价失衡。
///
/// 所以判据拆成两件事：
///
/// - **要不要弹**：只看「看过没有」和「系统 Dock 是不是已经自动隐藏了」。
/// - **弹出来要不要给那组系统 Dock 选项**：`canWriteDockPreferences`，只影响这一幕的内容，
///   不影响这一幕存不存在。给一个按不动的按钮仍然是不给。
///
/// 仍然保留的一条：**Dock 已经自动隐藏就不弹**。那些人早已按 README 的推荐配好了，再弹一次
/// 纯属噪音——而且这正是「Show Setup Guide Again」入口的全部受众，那条入口直通 `showWelcomeWindow()`。
enum WelcomeGuideDecision {
    enum Outcome: Equatable {
        /// 弹引导。`offersNativeDock == false` 时（沙箱 / 只读卷）第三幕不带那组系统 Dock 选项。
        case present(offersNativeDock: Bool)
        /// 不弹，并且**记下已看过**——这台机器以后都不用再问了。
        case skipAndMarkSeen
    }

    /// - Parameters:
    ///   - hasSeenWelcome: `AppSettingsStore.hasSeenWelcome`
    ///   - canWriteDockPreferences: `NativeDockPreferencesService.isAvailable`（非沙箱）
    ///   - dockAutohideEnabled: 系统 Dock 当前是否自动隐藏；`nil` = **读不到**，不再当成「该弹」
    ///     或「不该弹」的依据，只影响系统 Dock 选项那一块
    static func evaluate(
        hasSeenWelcome: Bool,
        canWriteDockPreferences: Bool,
        dockAutohideEnabled: Bool?
    ) -> Outcome {
        // 看过就是看过。这一条必须排在最前面：它是用户已经表达过的意思
        //（无论他当时点的是「应用推荐设置」还是「跳过」），后面几条都不该推翻它。
        if hasSeenWelcome { return .skipAndMarkSeen }

        // 已经是自动隐藏了，引导没有意义。顺手标记，免得用户哪天把 Dock 改回常驻时
        // 被一个「首次运行引导」突然拦住——那时他显然是故意要 Dock 回来的。
        if dockAutohideEnabled == true { return .skipAndMarkSeen }

        return .present(offersNativeDock: canWriteDockPreferences)
    }
}
