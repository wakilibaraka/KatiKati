import AppKit
import SwiftUI

/// Port plan #5b (2026-10-27): shows Claude Code's permission questions as a floating card and answers
/// them. Claude's `PermissionRequest` hook runs `katikati-approve`, which drops the request in
/// `approvals/pending/` and waits for `approvals/decided/<id>` (protocol and script: `AgentApproval`).
/// While this service runs it touches `approvals/alive`; without a fresh `alive` the script prints
/// nothing and Claude asks in the terminal, so quitting KatiKati never leaves Claude waiting.
///
/// Opt-in and inert when off: no timer, no watcher, no panel.
@MainActor
final class ClaudeApprovalService: ObservableObject {
    static let shared = ClaudeApprovalService()
    nonisolated static let enabledKey = "com.katikati.agent.approvals"

    @Published private(set) var requests: [AgentApprovalRequest] = []

    private let directory: URL
    private var heartbeat: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var sweep: Timer?
    private lazy var panel = ClaudeApprovalPanelController(service: self)

    init(directory: URL = AgentApproval.directory()) {
        self.directory = directory
    }

    private var pendingDirectory: URL { directory.appendingPathComponent("pending", isDirectory: true) }
    private var decidedDirectory: URL { directory.appendingPathComponent("decided", isDirectory: true) }
    private var aliveURL: URL { directory.appendingPathComponent("alive") }

    var isRunning: Bool { heartbeat != nil }

    /// Called once at launch: running again only if the person turned it on earlier.
    func startIfEnabled() {
        if UserDefaults.standard.bool(forKey: Self.enabledKey) { start() }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: decidedDirectory, withIntermediateDirectories: true)
        removeAbandonedFiles()
        touchAlive()

        heartbeat = Timer.scheduledTimer(withTimeInterval: AgentApproval.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.touchAlive() }
        }

        let fd = open(pendingDirectory.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.rescan() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watcher = source
        }
        rescan()
    }

    func stop() {
        heartbeat?.invalidate(); heartbeat = nil
        sweep?.invalidate(); sweep = nil
        watcher?.cancel(); watcher = nil
        // No fresh `alive` means the script hands every question back to the terminal at once.
        try? FileManager.default.removeItem(at: aliveURL)
        requests = []
        panel.hide()
    }

    private func touchAlive() {
        FileManager.default.createFile(atPath: aliveURL.path, contents: Data())
    }

    /// Requests and answers left by a crashed run. Never read: they would show a card for a question
    /// whose script is long gone.
    private func removeAbandonedFiles() {
        for folder in [pendingDirectory, decidedDirectory] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        }
    }

    // MARK: - Requests

    private func rescan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: pendingDirectory.path)) ?? []
        let now = Date()
        var present: [AgentApprovalRequest] = []
        for name in names where name.hasSuffix(".json") {
            let id = String(name.dropLast(5))
            guard AgentApproval.isSafeID(id), let created = AgentApproval.created(fromID: id),
                  !AgentApproval.isExpired(created: created, now: now) else { continue }
            if let known = requests.first(where: { $0.id == id }) { present.append(known); continue }
            guard let data = try? Data(contentsOf: pendingDirectory.appendingPathComponent(name)),
                  let request = AgentApproval.parse(id: id, data: data, created: created) else { continue }
            present.append(request)
        }
        present.sort { $0.created < $1.created }
        if present != requests { requests = present }
        updatePanel()
    }

    /// Answers a request. The script deletes its own pending file when it prints the answer.
    func decide(_ request: AgentApprovalRequest, _ decision: AgentApprovalDecision) {
        guard AgentApproval.isSafeID(request.id) else { return }
        try? decision.rawValue.write(to: decidedDirectory.appendingPathComponent(request.id), atomically: true, encoding: .utf8)
        requests.removeAll { $0.id == request.id }
        updatePanel()
    }

    private func updatePanel() {
        if requests.isEmpty {
            sweep?.invalidate(); sweep = nil
            panel.hide()
        } else {
            panel.show()
            // Questions the script gave up on disappear on their own; a slow timer only while one is showing.
            if sweep == nil {
                sweep = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.rescan() }
                }
            }
        }
    }
}

// MARK: - Card

@MainActor
private final class ClaudeApprovalPanelController {
    private weak var service: ClaudeApprovalService?
    private var panel: NSPanel?

    init(service: ClaudeApprovalService) { self.service = service }

    func show() {
        guard let service else { return }
        let panel = self.panel ?? makePanel(service: service)
        self.panel = panel
        let size = (panel.contentView as? NSHostingView<ClaudeApprovalCardView>)?.fittingSize ?? NSSize(width: 420, height: 120)
        panel.setContentSize(NSSize(width: 420, height: size.height))
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 210, y: frame.maxY - panel.frame.height - 8))
        }
        // Never `makeKey`/activate: a question must not steal the keystrokes the person is typing.
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel(service: ClaudeApprovalService) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: ClaudeApprovalCardView(service: service))
        return panel
    }
}

private struct ClaudeApprovalCardView: View {
    @ObservedObject var service: ClaudeApprovalService

    var body: some View {
        if let request = service.requests.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Claude Code asks to use").font(.system(size: 12)).foregroundColor(.secondary)
                    Text(verbatim: request.toolName).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    if service.requests.count > 1 {
                        Text(verbatim: "+\(service.requests.count - 1)").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
                Text(verbatim: request.summary)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let cwd = request.cwd {
                    Text(verbatim: (cwd as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1).truncationMode(.head)
                }
                HStack {
                    Spacer(minLength: 0)
                    Button { service.decide(request, .deny) } label: { Text("Deny") }
                    Button { service.decide(request, .allow) } label: { Text("Allow") }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
            .frame(width: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            EmptyView()
        }
    }
}
