import XCTest
@testable import KatiKati

/// 服务层只是后台队列的包装：真值来自注入的后端，读在后台队列上（菜单路径不许在主线程做系统 I/O）。
final class LaunchAtLoginServiceTests: XCTestCase {
    @MainActor
    func testServiceReadsAndWritesThroughTheInjectedBackend() async throws {
        let backend = LaunchAtLoginStub(state: .on)
        let service = LaunchAtLoginService(backend: backend)

        let state = await service.currentState()
        XCTAssertEqual(state, .on)

        try service.setEnabled(false)
        XCTAssertEqual(backend.setCalls, [false])
        backend.state = .off
        let after = await service.currentState()
        XCTAssertEqual(after, .off)
    }

    /// `readState()` 必须离开主线程：状态来自 `SMAppService`，菜单打开时同步读会卡住一次系统调用。
    @MainActor
    func testServiceReadsOffTheMainThread() async {
        let backend = LaunchAtLoginStub(state: .off)
        let service = LaunchAtLoginService(backend: backend)

        _ = await service.currentState()
        XCTAssertEqual(backend.readOnMainThread, [false])
    }
}

private final class LaunchAtLoginStub: LaunchAtLoginBackend, @unchecked Sendable {
    var state: LaunchAtLoginState
    var setCalls: [Bool] = []
    var readOnMainThread: [Bool] = []

    init(state: LaunchAtLoginState) {
        self.state = state
    }

    func readState() -> LaunchAtLoginState {
        readOnMainThread.append(Thread.isMainThread)
        return state
    }

    func setEnabled(_ enabled: Bool) throws {
        setCalls.append(enabled)
    }

    func openSettings() {}
}
