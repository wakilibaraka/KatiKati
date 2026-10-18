import Foundation

/// 目录变更监视：`open(path, O_EVTONLY)` + `DispatchSourceFileSystemObject`，
/// ~0.3s 防抖后回主线程回调。封面刷新、废纸篓空/满、弹窗实时刷新共用。
///
/// fd 生命周期：fd 只在 source 的 cancel handler 里 close（绝不先 close 再 cancel，
/// 否则 fd 可能被复用后误关别人的）；`stop()` 幂等，deinit 兜底。
final class DirectoryWatcher {
    /// `open()` 永远不在调用线程跑：TCC 保护的目录（~/Downloads 等）首次 open 会弹系统授权框，
    /// 而这个调用会阻塞调用线程直到用户作答 —— 老构造器在主线程调它，pinned Downloads 的首启直接
    /// 冻住首屏（48a walk；`DownloadsMonitor.start` 早就是后台 open 的先例）。所有调用方走 `start(...)`。
    private static let openQueue = DispatchQueue(label: "com.katikati.directory-watcher-open", qos: .utility)

    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval
    private let onChange: () -> Void

    /// fd 在后台队列打开：ready 的 watcher 回主队列，打不开就是 nil —— 调用方照旧按
    /// “nil = 下一次 sync/display 重试”处理。回调保证在主线程。
    static func start(
        path: String,
        debounce: TimeInterval = 0.3,
        onChange: @escaping () -> Void,
        completion: @escaping (DirectoryWatcher?) -> Void
    ) {
        openQueue.async {
            let watcher = DirectoryWatcher(path: path, debounce: debounce, onChange: onChange)
            DispatchQueue.main.async { completion(watcher) }
        }
    }

    /// 同步 open：只许在 `start` 的后台队列里调。source 的队列仍是 main，所以构造完成后
    /// 的一切接触（事件、防抖、`stop()`、deinit）都在主线程，跨线程的只有这次移交。
    private init?(path: String, debounce: TimeInterval, onChange: @escaping () -> Void) {
        self.debounceInterval = debounce
        self.onChange = onChange

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setCancelHandler { close(fd) }
        source.setEventHandler { [weak self] in self?.scheduleChange() }
        source.resume()
        self.source = source
    }

    /// 主队列上防抖：事件风暴（批量拷贝）只触发一次回调。
    private func scheduleChange() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.source != nil else { return }
            self.onChange()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
    }

    deinit {
        debounceWorkItem?.cancel()
        source?.cancel()
    }
}
