import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Studio Hub / Droppy Shelf tab: renders user-configured shelf widgets (File Tray, Pomodoro Focus,
/// Clipboard + Quick Note, System Stats) with Dynamic Glass / Liquid Glass / Solid OLED card chrome.
struct NotchToolsView: View {
    private let services = ProductivityServices.shared

    var body: some View {
        DroppyShelfView(services: services)
    }
}

struct DroppyShelfView: View {
    let services: ProductivityServices
    @AppStorage(DroppyShelfConfigStore.orderKey) private var orderRaw = ""
    @AppStorage(DroppyShelfConfigStore.hiddenKey) private var hiddenRaw = DroppyShelfConfigStore.encodeHidden(DroppyShelfConfigStore.defaultHidden)
    @AppStorage(DroppyShelfConfigStore.glassKey) private var glassRaw = DroppyGlassMaterial.dynamicGlass.rawValue
    @AppStorage(DroppyShelfConfigStore.accentKey) private var accentRaw = DroppyAccentTheme.oceanBlue.rawValue

    private var visibleWidgets: [DroppyShelfWidgetKind] {
        let hidden = DroppyShelfConfigStore.decodeHidden(hiddenRaw)
        return DroppyShelfConfigStore.decodeOrder(orderRaw).filter { !hidden.contains($0) }
    }

    private var glassMaterial: DroppyGlassMaterial {
        DroppyGlassMaterial(rawValue: glassRaw) ?? .dynamicGlass
    }

    private var accentTheme: DroppyAccentTheme {
        DroppyAccentTheme(rawValue: accentRaw) ?? .oceanBlue
    }

    private var accentColor: Color {
        NotchHexColor.rgba(accentTheme.hex).color
    }

    var body: some View {
        let widgets = visibleWidgets
        let compact = widgets.count > 3
        Group {
            if widgets.isEmpty {
                shelfCard(compact: false) {
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text(verbatim: "All shelf widgets are hidden — enable widgets in Notch Settings.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: compact ? 8 : NotchLayoutSpec.homeSpacing) {
                    ForEach(widgets) { kind in
                        shelfCard(compact: compact) {
                            widgetBody(for: kind)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func widgetBody(for kind: DroppyShelfWidgetKind) -> some View {
        switch kind {
        case .fileTray:
            DroppyFileTrayView(accentColor: accentColor)
        case .pomodoro:
            NotchFocusCard(focus: services.focus, timer: services.timer)
        case .clipboardNotes:
            NotchClipboardCard(clipboard: services.clipboard, tasks: services.tasks)
        case .systemStats:
            NotchSystemCard(monitor: services.systemMonitor)
        }
    }

    private func shelfCard<C: View>(compact: Bool, @ViewBuilder _ content: () -> C) -> some View {
        let shape = RoundedRectangle(cornerRadius: NotchLayoutSpec.cardRadius, style: .continuous)
        return content()
            .padding(compact ? 9 : NotchLayoutSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if glassMaterial == .liquidGlass {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(accentColor.opacity(0.08)))
                } else {
                    let opacity = glassMaterial == .dynamicGlass ? 0.11 : 0.06
                    shape.fill(Color.white.opacity(opacity))
                        .overlay(shape.fill(accentColor.opacity(glassMaterial == .dynamicGlass ? 0.05 : 0.0)))
                }
            }
            .overlay(shape.strokeBorder(accentColor.opacity(glassMaterial == .solidOLED ? 0.14 : 0.28), lineWidth: 1))
    }
}

private enum NotchToolsFallbackShelf {
    @MainActor static let shared = ShelfStore()
}

struct DroppyFileTrayView: View {
    let accentColor: Color
    @StateObject private var tray = DroppyFileTrayStore()
    @ObservedObject private var shelfStore = AppDelegate.shared?.shelfStore ?? NotchToolsFallbackShelf.shared
    @AppStorage(ShelfPolicy.syncNotchTrayKey) private var syncNotchTray = true
    @State private var isDropTargeted = false
    @State private var isBusy = false
    @State private var statusText: String?

    private struct TrayEntry: Identifiable {
        let id: String
        let path: String
        let isPinned: Bool
        var url: URL { URL(fileURLWithPath: path) }
        var fileName: String { url.lastPathComponent }
    }

    private var entries: [TrayEntry] {
        if syncNotchTray {
            return shelfStore.items.map { TrayEntry(id: $0.id.uuidString, path: $0.path, isPinned: $0.isPinned) }
        }
        return tray.items.map { TrayEntry(id: $0.id.uuidString, path: $0.path, isPinned: $0.isPinned) }
    }

    var body: some View {
        let items = entries
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text("File Tray")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                if !items.isEmpty {
                    Text(verbatim: "\(items.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(accentColor.opacity(0.28)))
                }
                Spacer(minLength: 0)
                if !items.isEmpty {
                    Button {
                        if syncNotchTray { shelfStore.clear() } else { tray.clearUnpinned() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: "Clear unpinned tray items"))
                }
                Button { pickFiles() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(accentColor.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: "Add files to tray"))
            }

            if items.isEmpty {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isDropTargeted ? accentColor : .white.opacity(0.45))
                    Text(verbatim: isDropTargeted ? "Release to stage" : "Drop files or click +")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(isDropTargeted ? accentColor : .white.opacity(0.18))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items) { item in
                            trayPill(item)
                        }
                    }
                }
                .frame(maxHeight: 58)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    transformChip("Zip") { runTransform(.zip) }
                    if items.contains(where: { FileTransformPlan.canRemoveBackground(for: $0.url) }) {
                        transformChip("Resize") { runTransform(.resize) }
                        Menu {
                            ForEach(ImageTargetFormat.allCases, id: \.rawValue) { fmt in
                                Button(fmt.rawValue.uppercased()) { ShelfActions.convertImage(items.map(\.url), format: fmt, into: shelfStore) }
                            }
                        } label: {
                            Text("Convert")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(accentColor.opacity(isBusy ? 0.12 : 0.28)))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    transformChip("PDF") { runTransform(.pdf) }
                    if let statusText {
                        Text(verbatim: statusText)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .lineLimit(1)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onDrop(of: [.fileURL, .plainText, .url], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func trayPill(_ item: TrayEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(nsImage: FolderIconResolver.resolve(item.path, size: 20))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                Spacer(minLength: 0)
                Button { togglePin(item) } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 8))
                        .foregroundStyle(item.isPinned ? accentColor : .white.opacity(0.55))
                }.buttonStyle(.plain)
                Button { removeEntry(item) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }.buttonStyle(.plain)
            }
            Text(verbatim: item.fileName)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(width: 96, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.09)))
        .onTapGesture { NSWorkspace.shared.open(item.url) }
        .onDrag { FileDragItemProvider.make(for: item.url) }
    }

    private func togglePin(_ entry: TrayEntry) {
        if syncNotchTray { shelfStore.togglePin(entry.path) }
        else if let uuid = UUID(uuidString: entry.id) { tray.togglePin(id: uuid) }
    }

    private func removeEntry(_ entry: TrayEntry) {
        if syncNotchTray { shelfStore.remove(entry.path) }
        else if let uuid = UUID(uuidString: entry.id) { tray.remove(id: uuid) }
    }

    private func transformChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(accentColor.opacity(isBusy ? 0.12 : 0.28)))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            if !syncNotchTray { tray.add(urls: panel.urls) }
            shelfStore.stash(paths: panel.urls.map(\.path))
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    guard let url else { return }
                    DispatchQueue.main.async {
                        if !syncNotchTray { tray.add(urls: [url]) }
                        shelfStore.stash(paths: [url.path])
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    DispatchQueue.main.async {
                        if let fileURL = shelfStore.stashText(text), !syncNotchTray {
                            tray.add(urls: [fileURL])
                        }
                    }
                }
            }
        }
        return accepted
    }

    private enum TransformKind { case zip, resize, pdf }

    private func runTransform(_ kind: TransformKind) {
        let urls = entries.map(\.url)
        guard !urls.isEmpty, !isBusy else { return }
        isBusy = true
        statusText = "Working…"
        Task {
            do {
                let output: URL = try await Task.detached(priority: .userInitiated) {
                    switch kind {
                    case .zip:
                        return try FileTransformEngine.zipFiles(urls)
                    case .resize:
                        guard let img = urls.first(where: { FileTransformPlan.canRemoveBackground(for: $0) }) else {
                            throw FileTransformEngine.TransformError.unreadableSource
                        }
                        return try FileTransformEngine.resizeImage(at: img)
                    case .pdf:
                        return try FileTransformEngine.mergePDFs(urls)
                    }
                }.value
                if !syncNotchTray { tray.add(urls: [output]) }
                shelfStore.stash(paths: [output.path])
                statusText = output.lastPathComponent
            } catch {
                statusText = "Failed"
                NSSound.beep()
            }
            isBusy = false
        }
    }
}

private func cardTitle(_ symbol: String, _ title: Text) -> some View {
    HStack(spacing: 5) {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
        title.font(.system(size: 11, weight: .semibold))
        Spacer(minLength: 0)
    }
    .foregroundStyle(.white.opacity(0.6))
}

private func smallButton(_ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.white.opacity(0.14)))
    }
    .buttonStyle(.plain)
}

private func chip(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(verbatim: title).font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.14)))
    }
    .buttonStyle(.plain)
}

// MARK: Focus & timers

struct NotchFocusCard: View {
    @ObservedObject var focus: FocusTimerController
    @ObservedObject var timer: CountdownTimerController

    private var phaseLabel: String {
        switch focus.model.phase {
        case .focus: return "FOCUS"
        case .shortBreak: return "BREAK"
        case .longBreak: return "REST"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Focus").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
                Text(verbatim: phaseLabel)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(focus.model.isRunning ? .orange : .white.opacity(0.65))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill((focus.model.isRunning ? Color.orange : Color.white).opacity(0.16)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: NotchLayoutSpec.clockText(Double(focus.model.remaining)))
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                if timer.model.isRunning {
                    Text(verbatim: NotchLayoutSpec.clockText(Double(timer.model.remaining)))
                        .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.cyan)
                }
            }
            HStack(spacing: 8) {
                smallButton(focus.model.isRunning ? "pause.fill" : "play.fill") { focus.toggle() }
                smallButton("forward.end.fill") { focus.skip() }
                smallButton("arrow.counterclockwise") { focus.reset() }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    ForEach(0..<FocusTimerModel.cycleLength, id: \.self) { index in
                        Circle()
                            .fill(index < focus.model.completedInCycle ? Color.orange : Color.white.opacity(0.2))
                            .frame(width: 5, height: 5)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach([5, 15, 25], id: \.self) { minutes in
                    chip("\(minutes)m") { timer.set(seconds: minutes * 60); timer.toggle() }
                }
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: Clipboard + quick note

struct NotchClipboardCard: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var tasks: TasksController
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Clipboard").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
                if clipboard.isRecording {
                    Text(verbatim: "\(clipboard.history.entries.count) clips")
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            if !clipboard.isRecording {
                chip(String(localized: "Turn On Clipboard History")) { clipboard.setRecording(true) }
            } else if clipboard.history.entries.isEmpty {
                Text("Nothing copied yet").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(Array(clipboard.history.entries.prefix(3))) { entry in
                    Button { clipboard.copy(entry) } label: {
                        Text(verbatim: entry.text.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 11)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            TextField(String(localized: "Quick note"), text: $note, onCommit: {
                let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                tasks.add(text)
                note = ""
            })
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.1)))
        }
        .foregroundStyle(.white)
    }
}

// MARK: System

struct NotchSystemCard: View {
    @ObservedObject var monitor: SystemMonitorController
    @ObservedObject private var keyGuard = KeyGuardService.shared
    @AppStorage(WeatherUnits.temperatureKey) private var tempUnit: TemperatureUnit = .celsius

    var body: some View {
        let snap = monitor.snapshot
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.medium").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("System").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
                if let wx = WeatherPanelHost.service?.currentState,
                   wx.cityName != WeatherState.empty.cityName,
                   wx.conditionText != WeatherState.empty.conditionText {
                    HStack(spacing: 3) {
                        Image(systemName: wx.symbolName)
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text(verbatim: WeatherUnits.degrees(wx.temperatureCelsius, tempUnit))
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                }
            }
            meter("cpu", Text("CPU"), snap.cpu)
            meter("memorychip", Text("Memory"), snap.memory.fraction)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                chip(keyGuard.isVisualizerEnabled ? "Keys On" : "Keys") {
                    if !keyGuard.isVisualizerEnabled, !KeyGuardService.hasPermission {
                        KeyGuardService.requestPermission()
                    }
                    keyGuard.setVisualizer(!keyGuard.isVisualizerEnabled)
                }
                chip("Shortcuts") {
                    ShortcutCheatSheetService.shared.toggle(pinned: true)
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { monitor.acquire() }
        .onDisappear { monitor.release() }
    }

    private func meter(_ symbol: String, _ title: Text, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: symbol).font(.system(size: 10))
                title.font(.system(size: 11))
                Spacer()
                Text(verbatim: SystemMonitorFormat.percent(fraction)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(fraction > 0.85 ? Color.orange : Color.white).frame(width: geo.size.width * min(1, max(0, fraction)))
                }
            }
            .frame(height: 4)
        }
    }
}
