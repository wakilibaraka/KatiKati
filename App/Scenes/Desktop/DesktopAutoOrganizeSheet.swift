import AppKit
import SwiftUI

/// Native non-blocking window controller hosting the Preview-First Desktop Auto-Organize sheet.
@MainActor
final class DesktopAutoOrganizeWindowController {
    private var window: NSWindow?

    func present(
        onApply: @escaping (DesktopOrganizePlan, Bool) throws -> DesktopOrganizeUndoRecord,
        onUndo: @escaping () -> Int
    ) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = DesktopAutoOrganizeSheet(
            onApply: onApply,
            onUndo: onUndo,
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "Auto-Organize Folder…")
        win.contentViewController = hosting
        win.center()
        win.isReleasedWhenClosed = false
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }
}

/// Preview-First Desktop Auto-Organize sheet: dry-run bucket preview, toggles, apply, and 1-click Undo.
struct DesktopAutoOrganizeSheet: View {
    let onApply: (DesktopOrganizePlan, Bool) throws -> DesktopOrganizeUndoRecord
    let onUndo: () -> Int
    let onClose: () -> Void

    @State private var sourceURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop", isDirectory: true)
    @State private var destinationURL = DesktopAutoOrganizeExecutor.defaultDestinationRootURL
    @State private var includeFolders = false
    @State private var createBoxes = true
    @State private var enabledCategories = Set(DesktopAutoStackCategory.allCases)

    @State private var plan: DesktopOrganizePlan?
    @State private var permissionDenied = false
    @State private var errorMessage: String?
    @State private var hasUndo = DesktopAutoOrganizeExecutor.loadLastUndoRecord() != nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                pathRow(
                    title: Text("Source Folder"),
                    url: sourceURL,
                    canCreate: false
                ) { chosen in
                    sourceURL = chosen
                    refreshPreview()
                }
                pathRow(
                    title: Text("Destination Folder"),
                    url: destinationURL,
                    canCreate: true
                ) { chosen in
                    destinationURL = chosen
                    refreshPreview()
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.45)))

            HStack(spacing: 16) {
                Toggle("Include Folders", isOn: $includeFolders)
                Toggle("Create Desktop Boxes for Categories", isOn: $createBoxes)
            }
            .onChange(of: includeFolders) { _, _ in refreshPreview() }

            Text("Preview")
                .font(.headline)

            previewArea

            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                if hasUndo {
                    Button("Undo Last Organize") {
                        _ = onUndo()
                        hasUndo = DesktopAutoOrganizeExecutor.loadLastUndoRecord() != nil
                        refreshPreview()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Organize Files") { runApply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedMoveCount == 0)
            }
        }
        .padding(18)
        .frame(minWidth: 480, minHeight: 460)
        .onAppear { refreshPreview() }
    }

    @ViewBuilder
    private var previewArea: some View {
        if permissionDenied {
            VStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Folder access is required to preview files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Grant Access") {
                    chooseFolder(initial: sourceURL, canCreate: false) { chosen in
                        sourceURL = chosen
                        refreshPreview()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let plan {
            if plan.buckets.isEmpty {
                Text("No files match the selected categories.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(plan.buckets) { bucket in
                        bucketRow(bucket)
                    }
                }
                .listStyle(.inset)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func bucketRow(_ bucket: DesktopOrganizeBucket) -> some View {
        let isOn = Binding(
            get: { enabledCategories.contains(bucket.category) },
            set: { checked in
                if checked { enabledCategories.insert(bucket.category) }
                else { enabledCategories.remove(bucket.category) }
            }
        )
        return Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: bucket.category.symbolName)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: bucket.category.localizedTitle)
                        .font(.body.weight(.medium))
                    Text(verbatim: bucket.items.prefix(3).map(\.filename).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(verbatim: "\(bucket.items.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
        }
    }

    private func pathRow(
        title: Text,
        url: URL,
        canCreate: Bool,
        onChosen: @escaping (URL) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            title.font(.subheadline.weight(.medium))
                .frame(width: 120, alignment: .leading)
            Text(verbatim: (url.path as NSString).abbreviatingWithTildeInPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button("Choose…") {
                chooseFolder(initial: url, canCreate: canCreate, onChosen: onChosen)
            }
            .controlSize(.small)
        }
    }

    private var selectedMoveCount: Int {
        guard let plan else { return 0 }
        return plan.buckets
            .filter { enabledCategories.contains($0.category) }
            .reduce(0) { $0 + $1.items.count }
    }

    private func refreshPreview() {
        errorMessage = nil
        permissionDenied = false
        let options = DesktopOrganizeOptions(
            sourceDirectory: sourceURL,
            destinationRoot: destinationURL,
            includeFolders: includeFolders,
            enabledCategories: Set(DesktopAutoStackCategory.allCases),
            createBoxesForCategories: createBoxes
        )
        Task.detached(priority: .userInitiated) {
            do {
                let built = try DesktopAutoOrganizeExecutor.scanAndPlan(options: options)
                await MainActor.run { self.plan = built }
            } catch {
                await MainActor.run {
                    if FolderContentsLoader.isPermissionDenied(error) {
                        self.permissionDenied = true
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                    self.plan = nil
                }
            }
        }
    }

    private func runApply() {
        guard let plan else { return }
        let filtered = DesktopOrganizePlan(
            sourceDirectory: plan.sourceDirectory,
            destinationRoot: plan.destinationRoot,
            buckets: plan.buckets.filter { enabledCategories.contains($0.category) },
            skippedNames: plan.skippedNames
        )
        do {
            _ = try onApply(filtered, createBoxes)
            hasUndo = DesktopAutoOrganizeExecutor.loadLastUndoRecord() != nil
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseFolder(
        initial: URL,
        canCreate: Bool,
        onChosen: @escaping (URL) -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = canCreate
        panel.directoryURL = initial
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onChosen(url)
    }
}
