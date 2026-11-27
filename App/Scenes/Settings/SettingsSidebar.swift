import SwiftUI

extension SettingsTab {
    var hueColor: Color { Color(red: hue.red, green: hue.green, blue: hue.blue) }
}

private enum SidebarSection: Identifiable {
    case system([SettingsTab])
    case surfaces([SettingsTab])
    case workspace([SettingsTab])
    case input([SettingsTab])
    case productivity([SettingsTab])
    case advanced([SettingsTab])

    var id: String {
        switch self {
        case .system: return "system"
        case .surfaces: return "surfaces"
        case .workspace: return "workspace"
        case .input: return "input"
        case .productivity: return "productivity"
        case .advanced: return "advanced"
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .system(let tabs),
             .surfaces(let tabs),
             .workspace(let tabs),
             .input(let tabs),
             .productivity(let tabs),
             .advanced(let tabs):
            return tabs
        }
    }

    var headerText: Text? {
        switch self {
        case .system: return Text("System & Bars")
        case .surfaces: return Text("Surfaces & Shelves")
        case .workspace: return Text("Window & Workspace")
        case .input: return Text("Input & Shortcuts")
        case .productivity: return Text("Productivity & AI")
        case .advanced: return Text("Advanced")
        }
    }
}

/// The Settings window's only navigation (macOS System Settings style): search first, then one row
/// per section with a hue-coloured icon. Icons-only when the window is narrow or the user collapses it.
struct SettingsSidebar: View {
    @ObservedObject var tabState: SettingsTabState
    let isCompact: Bool
    @Binding var forcedCompact: Bool
    /// Bumped by the shell (⌘F) to put the cursor in the search field.
    var focusSearch = 0

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var isToggleHovered = false
    @State private var hoveredTab: SettingsTab?

    private static let sections: [SidebarSection] = [
        .system([.general, .menuBar, .appearance, .wallpaper, .dockItems, .appIcons]),
        .surfaces([.barWidgets, .shelf, .desktop, .weather, .music, .notch, .notifications, .sideDeck, .edgeBars]),
        .workspace([.tiling, .windowManagement, .launcher, .commandBar, .controlCenter]),
        .input([.shortcuts, .keyboard, .keyVisualizer, .mouse, .mouseGestures, .radialDial, .quitApps]),
        .productivity([.aiTracking, .downloads, .clipboard, .tools]),
        .advanced([.experimental, .advanced])
    ]

    private var visibleTabs: [SettingsTab] {
        SettingsSearchIndex.matchingTabs(for: query, in: SettingsTab.allCases)
    }

    var body: some View {
        VStack(spacing: 6) {
            topBar

            if !isCompact {
                searchField
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCompact {
                        ForEach(Self.sections) { section in
                            if let header = section.headerText {
                                HStack(spacing: 6) {
                                    header
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, 14)
                                .padding(.bottom, 2)
                            }
                            ForEach(section.tabs, id: \.self) { tab in
                                row(tab)
                            }
                        }
                    } else {
                        ForEach(visibleTabs, id: \.self) { tab in
                            row(tab)
                        }
                        if visibleTabs.isEmpty {
                            Text("No matching section")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 12)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 0)
        .onChange(of: focusSearch) { _ in searchFocused = true }
        .frame(width: isCompact ? SettingsMetrics.sidebarCollapsedWidth : SettingsMetrics.sidebarWidth)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var topBar: some View {
        if isCompact {
            VStack(spacing: 4) {
                // Reserves top space for macOS traffic lights in fullSizeContentView
                Color.clear.frame(height: 32)
                toggleButton
            }
            .padding(.top, 4)
        } else {
            HStack(spacing: 0) {
                // 72pt reserves safe clearance for the macOS window close/minimize/zoom buttons
                Spacer().frame(width: 72)
                Spacer()
                toggleButton
            }
            .padding(.trailing, 10)
            .frame(height: 38)
        }
    }

    private var toggleButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { forcedCompact.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isToggleHovered ? Color.primary : Color.secondary)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isToggleHovered ? 0.09 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(Text("Collapse or expand the sidebar"))
        .accessibilityLabel(Text("Toggle sidebar"))
        .onHover { isToggleHovered = $0 }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(searchFocused ? Color.accentColor : Color.secondary)

            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
                .onSubmit { if let first = visibleTabs.first, !query.isEmpty { open(first) } }
                .accessibilityLabel(Text("Search settings"))

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Text("Clear search"))
                .accessibilityLabel(Text("Clear search"))
            } else {
                Text(verbatim: "⌘F")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(searchFocused ? 0.09 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(searchFocused ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal, 10)
    }

    private func open(_ tab: SettingsTab) {
        tabState.findQuery = SettingsSearchIndex.resolvedRowQuery(for: tab, userQuery: query)
        tabState.selected = tab
    }

    private func row(_ tab: SettingsTab) -> some View {
        let selected = tabState.selected == tab
        let isPill = selected && !isCompact
        let isHovered = hoveredTab == tab && !selected

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { open(tab) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(isPill ? AnyShapeStyle(Color.white.opacity(0.24)) : AnyShapeStyle(tab.hueColor.gradient))
                    )
                    .shadow(color: isPill ? tab.hueColor.opacity(0.35) : .clear, radius: 3, x: 0, y: 1)

                if !isCompact {
                    Text(tab.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .white : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, isCompact ? 0 : 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: isCompact ? .center : .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? tab.hueColor : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isPill ? Color.white.opacity(0.22) : Color.clear, lineWidth: 0.75)
            )
            .shadow(color: isPill ? tab.hueColor.opacity(0.32) : .clear, radius: 5, x: 0, y: 1.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(tab.title))
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { isHovered in
            if isHovered {
                hoveredTab = tab
            } else if hoveredTab == tab {
                hoveredTab = nil
            }
        }
    }
}
