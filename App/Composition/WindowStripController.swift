import AppKit
import Combine
import SwiftUI

/// The desktop window box: a glass card of open windows that lives **on the desktop, underneath every
/// window**, so it never covers or blocks an app. Click a window to bring it forward. The panel is
/// non-activating, so clicking the box never takes focus away from the app you were in.
// shortcut: primary display, left edge only; other edges/displays when someone asks.
@MainActor
final class WindowStripController: ObservableObject {
    static let enabledKey = WindowStripReserve.enabledKey

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let appName: String?
        let bundleID: String?
        let isActive: Bool
    }

    /// The box is a card, not an edge rail: it keeps a margin off the work area's corner, hugs its
    /// rows so it never shows an empty slab, and stops growing before it would own the screen.
    enum Box {
        static let width: CGFloat = 264
        static let margin: CGFloat = 12
        static let maxHeight: CGFloat = 560
        static let minHeight: CGFloat = 132
        /// One row (icon + two text lines + padding) plus the 2 pt gap under it.
        static let rowHeight: CGFloat = 42
        /// The row's own height, before the gap.
        static let rowContentHeight: CGFloat = 40
        /// List top and bottom padding.
        static let listPadding: CGFloat = 14
        /// Header, divider, footer and the card's own padding.
        static let chrome: CGFloat = 84

        /// The scroller's height: exactly the rows while they fit, capped so the card cannot own
        /// the display.
        static func listHeight(for count: Int) -> CGFloat {
            count == 0 ? 0 : min(CGFloat(count) * rowHeight + listPadding, maxHeight - chrome)
        }

        /// The panel is exactly as tall as the card, so no invisible strip can swallow a click.
        static func contentHeight(for count: Int) -> CGFloat {
            let list = count == 0 ? 74 : listHeight(for: count)
            return min(maxHeight, max(minHeight, chrome + list))
        }
    }

    @Published private(set) var items: [Item] = []

    private let runtime: AppRuntime
    private var panel: NSPanel?
    private var sinks: [AnyCancellable] = []
    private var observers: [NSObjectProtocol] = []

    init(runtime: AppRuntime) { self.runtime = runtime }

    func start() {
        sinks.append(runtime.$snapshot.sink { [weak self] in self?.update($0) })
        let defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }
        // The work area moves when the Dock, the menu bar or a display changes; the box follows it.
        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }
        observers = [defaultsObserver, screenObserver]
        apply()
    }

    func activate(_ id: String) { runtime.activate(windowID: id) }

    private func update(_ snapshot: DockSnapshot) {
        let next = snapshot.orderedWindowIDs.compactMap { id -> Item? in
            guard let w = snapshot.windows[id] else { return nil }
            switch w.status {
            case .closedPending, .disappeared: return nil
            default: break
            }
            return Item(
                id: id.rawValue,
                title: w.title,
                appName: w.bundleIdentifier.map(AppDisplayNameResolver.displayName(for:)),
                bundleID: w.bundleIdentifier,
                isActive: w.status == .active
            )
        }
        if next != items {
            items = next
            // The card hugs its rows, so the panel's height changes with the list.
            apply()
        }
    }

    private func apply() {
        let on = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if !on {
            guard panel != nil else { return }
            panel?.orderOut(nil); panel = nil
            TilingEngine.shared.reapplyForWorkAreaChange()
            return
        }
        guard let screen = NSScreen.screens.first else { return }
        let frame = frame(on: screen)
        if let panel { panel.setFrame(frame, display: true); return }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Just under every normal window: the box is part of the desktop, so it can never sit on top
        // of a window the user is reading. It still takes clicks wherever no window covers it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: WindowBoxView(controller: self))
        panel.orderFrontRegardless()
        self.panel = panel
        TilingEngine.shared.reapplyForWorkAreaChange()
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        let height = min(Box.contentHeight(for: items.count), max(Box.minHeight, area.height - Box.margin * 2))
        return NSRect(
            x: area.minX + Box.margin,
            y: area.maxY - height - Box.margin,
            width: Box.width,
            height: height
        )
    }
}

/// The card itself: a header with a count, one row per window in the switcher's list order, and the
/// drawer shortcut as a quiet footer. Rows keep the switcher's list grammar (icon, title, app) so the
/// box and the Option-Tab switcher read as the same surface.
private struct WindowBoxView: View {
    @ObservedObject var controller: WindowStripController
    @State private var hoveredID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 12)
            if controller.items.isEmpty {
                emptyState
            } else {
                rows
            }
            footer
        }
        .frame(maxWidth: .infinity)
        .background(card)
        .padding(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Windows"))
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Windows")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.7)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(verbatim: "\(controller.items.count)")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    private var rows: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(controller.items) { item in
                    row(item)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
        }
        .frame(height: WindowStripController.Box.listHeight(for: controller.items.count))
    }

    private func row(_ item: WindowStripController.Item) -> some View {
        let hovered = hoveredID == item.id
        return Button { controller.activate(item.id) } label: {
            HStack(spacing: 9) {
                icon(item)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.title)
                        .font(.system(size: 12, weight: item.isActive ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let appName = item.appName, appName != item.title {
                        Text(verbatim: appName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 4)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                    .opacity(item.isActive ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: WindowStripController.Box.rowContentHeight)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(item.isActive
                          ? Color.accentColor.opacity(hovered ? 0.24 : 0.16)
                          : Color.primary.opacity(hovered ? 0.09 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil }
        }
        .help(Text(verbatim: item.title))
    }

    @ViewBuilder
    private func icon(_ item: WindowStripController.Item) -> some View {
        Group {
            if let bundleID = item.bundleID {
                Image(nsImage: AppIconResolver.icon(for: bundleID))
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "macwindow")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
        }
        .frame(width: 22, height: 22)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No open windows")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(verbatim: "⌃⌥W")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            Text("Drawer")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 11)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.34), Color.white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
    }
}
