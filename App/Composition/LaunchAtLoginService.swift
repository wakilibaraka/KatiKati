import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case off
    case on
    case requiresApproval
}

struct LaunchAtLoginMenuPresentation: Equatable {
    var title: String
    var isEnabled: Bool
    var isChecked: Bool
    var showsSettingsItem: Bool

    init(title: String, isEnabled: Bool, isChecked: Bool, showsSettingsItem: Bool) {
        self.title = title
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.showsSettingsItem = showsSettingsItem
    }

    init(state: LaunchAtLoginState) {
        switch state {
        case .off:
            title = String(localized: "Open at Login")
            isEnabled = true
            isChecked = false
            showsSettingsItem = false
        case .on:
            title = String(localized: "Open at Login")
            isEnabled = true
            isChecked = true
            showsSettingsItem = false
        case .requiresApproval:
            title = String(localized: "Open at Login (Pending Approval)")
            isEnabled = true
            isChecked = false
            showsSettingsItem = true
        }
    }
}

enum LaunchAtLoginMenuModel {
    static func requestedEnabledValue(afterSelecting state: LaunchAtLoginState) -> Bool? {
        switch state {
        case .off, .requiresApproval:
            return true
        case .on:
            return false
        }
    }
}

@MainActor
protocol LaunchAtLoginServicing {
    func currentState() async -> LaunchAtLoginState
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

/// 真正碰系统的那一层：`SMAppService`（`ModernLoginItemBackend`），也是唯一的后端。
///
/// `readState()` 会在 `LaunchAtLoginService` 的后台队列上被调用（菜单路径不许在主线程做系统 I/O），
/// 所以实现不能依赖主线程；`setEnabled` / `openSettings` 仍在主线程被调用。
protocol LaunchAtLoginBackend: Sendable {
    func readState() -> LaunchAtLoginState
    func setEnabled(_ enabled: Bool) throws
    func openSettings()
}

@MainActor
final class LaunchAtLoginService: LaunchAtLoginServicing {
    private let backend: any LaunchAtLoginBackend
    private let readerQueue = DispatchQueue(label: "com.katikati.app.launch-at-login-reader", qos: .userInitiated)

    init(backend: any LaunchAtLoginBackend = LaunchAtLoginService.systemBackend()) {
        self.backend = backend
    }

    func currentState() async -> LaunchAtLoginState {
        let backend = backend
        let readerQueue = readerQueue
        return await withCheckedContinuation { continuation in
            readerQueue.async {
                continuation.resume(returning: backend.readState())
            }
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        try backend.setEnabled(enabled)
    }

    func openSystemSettings() {
        backend.openSettings()
    }

    /// 两条路注册的都是**当前正在运行的 bundle**：开发构建上勾选会把登录项钉在 `build/DerivedData/…` 上
    /// （规矩见 `.claude/rules/build-and-release.md`）。
    nonisolated static func systemBackend() -> any LaunchAtLoginBackend {
        ModernLoginItemBackend()
    }
}

/// `SMAppService.mainApp`。`register()` 后可能停在 `.requiresApproval`，
/// 要用户去「系统设置 → 通用 → 登录项与扩展」批准，这不是失败。
struct ModernLoginItemBackend: LaunchAtLoginBackend {
    func readState() -> LaunchAtLoginState {
        Self.mapStatus(SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func mapStatus(_ status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .off
        @unknown default:
            return .off
        }
    }
}
