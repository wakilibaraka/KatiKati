import AppKit
import SwiftUI

// Storage page, two halves: the largest personal files (photos, video, music, documents, archives) and the
// biggest cache and developer folders. The scan runs only while the page is on screen; a row reveals its
// item in Finder. Folders in ~/Desktop, ~/Documents and ~/Downloads need Full Disk Access to be read, offered
// as a door to System Settings and never prompted from code.

struct NotchStoragePageView: View {
    @ObservedObject private var scanner = StorageScanService.shared

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
