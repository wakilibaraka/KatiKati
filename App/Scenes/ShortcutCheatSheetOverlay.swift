import AppKit
import SwiftUI

/// The floating Shortcut Cheat Sheet panel. Non-activating so it never steals focus from
/// the target app while reading its menu bar shortcuts; supports search, live modifier highlighting,
/// pinning, and Markdown export.
@MainActor
final class ShortcutCheatSheetOverlayController {
    private var panel: NSPanel?
    private unowned let service: ShortcutCheatSheetService

    init(service: ShortcutCheatSheetService) {
        self.service = service
    }

    func show() {
        let panel = self.panel ?? makePanel()
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyableCheatSheetPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true

        let host = NSHostingView(rootView: ShortcutCheatSheetView(service: service))
        host.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        ))
    }
}

private final class KeyableCheatSheetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct ShortcutCheatSheetView: View {
    @ObservedObject var service: ShortcutCheatSheetService
    @State private var selectedModifiers: KeyModifiers = []
    @State private var copiedMarkdown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeModifiers: KeyModifiers {
        selectedModifiers.union(service.liveModifiers)
    }

    private var filteredCategories: [ShortcutCheatSheetCategory] {
        ShortcutCheatSheetBuilder.filter(
            categories: service.categories,
            query: service.searchQuery,
            requiredModifiers: activeModifiers
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.25)
            bodyContent
        }
        .frame(width: 820, height: 520)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
        .onExitCommand { service.hide() }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            if let icon = service.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: service.appName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(verbatim: "\(filteredCategories.reduce(0) { $0 + $1.items.count }) shortcuts")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filter shortcuts", text: $service.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 170)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.07)))

            modifierPills

            Button {
                service.copyMarkdown()
                copiedMarkdown = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copiedMarkdown = false }
            } label: {
                Label(copiedMarkdown ? "Copied" : "Markdown", systemImage: copiedMarkdown ? "checkmark" : "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                service.isPinned.toggle()
            } label: {
                Image(systemName: service.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(service.isPinned ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(service.isPinned ? "Unpin overlay" : "Pin overlay open")

            Button {
                service.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modifierPills: some View {
        HStack(spacing: 4) {
            modifierPill("⌘", mod: .command)
            modifierPill("⌥", mod: .option)
            modifierPill("⌃", mod: .control)
            modifierPill("⇧", mod: .shift)
        }
    }

    private func modifierPill(_ glyph: String, mod: KeyModifiers) -> some View {
        let isOn = activeModifiers.contains(mod)
        return Button {
            if selectedModifiers.contains(mod) {
                selectedModifiers.remove(mod)
            } else {
                selectedModifiers.insert(mod)
            }
        } label: {
            Text(verbatim: glyph)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isOn ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if service.isLoading && filteredCategories.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Reading menu shortcuts…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredCategories.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text("No matching shortcuts")
                    .font(.system(size: 13, weight: .medium))
                Text("Grant Accessibility permission or clear your filter to inspect app menus.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 235, maximum: 280), alignment: .top)], spacing: 14) {
                    ForEach(filteredCategories) { category in
                        categoryCard(category)
                    }
                }
                .padding(16)
            }
        }
    }

    private func categoryCard(_ category: ShortcutCheatSheetCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: category.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(category.items) { item in
                Button {
                    service.activate(item)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: item.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            if !item.subtitle.isEmpty {
                                Text(verbatim: item.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(verbatim: item.shortcut)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}
