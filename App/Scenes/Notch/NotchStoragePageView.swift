import AppKit
import SwiftUI

// Storage page: the largest folders and files on the Mac, biggest first. The scan runs only while the page
// is on screen; a row reveals its item in Finder. Whole-disk reach needs Full Disk Access, offered as a door
// to System Settings and never prompted from code.

struct NotchStoragePageView: View {
    @ObservedObject private var scanner = StorageScanService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if scanner.items.isEmpty {
                message(scanner.state == .scanning ? Text("Scanning…") : Text("Nothing Large Found"))
            } else {
                rows
            }
            if !scanner.hasFullDiskAccess { accessDoor }
        }
        .padding(NotchDesignSpec.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
        )
        .onAppear { scanner.scan() }
        .onDisappear { scanner.cancel() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Storage")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            if scanner.state == .scanning { ProgressView().controlSize(.mini) }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(scanner.items) { item in
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                            .resizable().frame(width: 14, height: 14)
                        Text(verbatim: item.name)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(width: 110, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.12))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.cyan)
                                        .frame(width: geo.size.width * StorageScanMath.share(item, of: scanner.items.first))
                                }
                        }
                        .frame(height: 4)
                        Text(verbatim: ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                            .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 56, alignment: .trailing)
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

    private func message(_ text: Text) -> some View {
        text.font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
