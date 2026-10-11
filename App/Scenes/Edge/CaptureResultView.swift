import SwiftUI

/// What the Capture button found: scanned codes first (links open only on click), then the recognised text.
struct CaptureResultView: View {
    @ObservedObject private var capture = ProductivityServices.shared.capture
    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let size = ProductivityFlyout.size(.capture)
        let env = TileEnv(palette: palette, isDark: colorScheme == .dark)
        BandTile(env: env, kind: .focus, width: size.width - 16, height: size.height - 16, header: {
            Text("Capture")
        }, content: {
            switch capture.state {
            case .idle, .working:
                Text("Select an area on screen…").font(.system(size: 12, weight: .semibold)).foregroundColor(env.secondary).padding(.top, 4)
            case .cancelled:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing captured").font(.system(size: 12, weight: .semibold))
                    Text("If the selector did not appear, allow Screen Recording for KatiKati in System Settings.")
                        .font(.system(size: 11)).foregroundColor(env.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings") { AgendaPane.openPrivacy("Privacy_ScreenCapture") }.font(.system(size: 11))
                }.padding(.top, 4)
            case let .done(text, codes):
                if text.isEmpty && codes.isEmpty {
                    Text("No text or code found").font(.system(size: 12, weight: .semibold)).foregroundColor(env.secondary).padding(.top, 4)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(codes, id: \.self) { code in codeRow(code, env: env) }
                            if !text.isEmpty { textBlock(text, env: env) }
                        }
                    }
                }
            }
        })
        .padding(8)
    }

    private func codeRow(_ code: String, env: TileEnv) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label { Text("QR Code") } icon: { Image(systemName: "qrcode") }
                .font(.system(size: 10, weight: .bold)).foregroundColor(env.secondary)
            Text(verbatim: code).font(.system(size: 12)).lineLimit(4).textSelection(.enabled)
            HStack(spacing: 10) {
                Button("Copy") { Self.copy(code) }
                if let url = CaptureRules.openableURL(code) { Button("Open") { NSWorkspace.shared.open(url) } }
            }.font(.system(size: 11))
        }
    }

    private func textBlock(_ text: String, env: TileEnv) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label { Text("Text") } icon: { Image(systemName: "text.viewfinder") }
                .font(.system(size: 10, weight: .bold)).foregroundColor(env.secondary)
            Text(verbatim: text).font(.system(size: 12)).textSelection(.enabled)
            Button("Copy") { Self.copy(text) }.font(.system(size: 11))
        }
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
