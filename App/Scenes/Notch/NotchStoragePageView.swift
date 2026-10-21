import AppKit
import SwiftUI

// Storage page, two halves: the largest personal files (photos, video, music, documents, archives) and the
// biggest cache and developer folders. The scan runs only while the page is on screen; a row reveals its
// item in Finder. Folders in ~/Desktop, ~/Documents and ~/Downloads need Full Disk Access to be read, offered
// as a door to System Settings and never prompted from code.

struct NotchStoragePageView: View {
    @ObservedObject private var scanner = StorageScanService.shared
    @ObservedObject private var cleaner = CleanerService.shared

    var body: some View {
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            card(symbol: "photo.on.rectangle.angled", title: Text("Files"), items: scanner.files, showsDoor: true)
            card(symbol: "hammer.fill", title: Text("Developer & Cache"), items: scanner.dev, showsDoor: false)
        }
        .onAppear { scanner.scan() }
        .onDisappear { scanner.cancel() }
    }

    private func card(symbol: String, title: Text, items: [StorageItem], showsDoor: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                title
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if scanner.state == .scanning { ProgressView().controlSize(.mini) }
            }
            if items.isEmpty {
                (scanner.state == .scanning ? Text("Scanning…") : Text("Nothing Large Found"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rows(items)
            }
            if !showsDoor { reviewCaches }
            if showsDoor && !scanner.hasFullDiskAccess { accessDoor }
        }
        .padding(NotchDesignSpec.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
        )
    }

    private func rows(_ items: [StorageItem]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(items) { item in
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                            .resizable().frame(width: 14, height: 14)
                        Text(verbatim: item.name)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                            .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 55d: dry-run first. The confirmation lists the folders and their total; only its destructive button
    /// moves them to the Trash. No timer and no automatic deletion.
    private var reviewCaches: some View {
        Button { reviewCachesTapped() } label: {
            cleaner.isScanning ? Text("Scanning…") : Text("Review Caches…")
        }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.cyan)
            .disabled(cleaner.isScanning)
    }

    private func reviewCachesTapped() {
        cleaner.scan {
            let candidates = cleaner.candidates
            guard !candidates.isEmpty else {
                let empty = NSAlert()
                empty.messageText = String(localized: "Nothing to Clean")
                empty.informativeText = String(localized: "No cache folder older than a week and larger than 50 MB was found.")
                NSApp.activate(ignoringOtherApps: true)
                empty.runModal()
                return
            }
            let total = ByteCountFormatter.string(fromByteCount: CleanupPlan.totalBytes(candidates), countStyle: .file)
            let preview = candidates.prefix(8).map { candidate in
                "• \(candidate.name) — \(ByteCountFormatter.string(fromByteCount: candidate.bytes, countStyle: .file))"
            }.joined(separator: "\n")
            let alert = NSAlert()
            alert.messageText = String(localized: "Move Caches to the Trash?")
            alert.informativeText = String(format: String(localized: "%d items, %@. They are moved to the Trash, so you can put them back; apps rebuild them as needed.\n\n%@"),
                                           candidates.count, total, preview)
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Move to Trash"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let outcome = cleaner.clean(candidates)
            let done = NSAlert()
            done.messageText = String(localized: "Caches Moved to the Trash")
            let moved = String(format: String(localized: "%d items, %@."), outcome.moved,
                               ByteCountFormatter.string(fromByteCount: outcome.bytes, countStyle: .file))
            let failed = outcome.failed > 0
                ? " " + String(format: String(localized: "%d could not be moved."), outcome.failed)
                : ""
            done.informativeText = moved + failed
            NSApp.activate(ignoringOtherApps: true)
            done.runModal()
        }
    }

    private var accessDoor: some View {
        Button(String(localized: "Allow Full Disk Access for the Whole Disk")) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.cyan)
    }
}
