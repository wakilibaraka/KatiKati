import SwiftUI

extension SettingsTab {
    var hueColor: Color { Color(red: hue.red, green: hue.green, blue: hue.blue) }
}

extension SettingsTab {
    /// Words a reader might search for besides the title (not localized; matched as typed).
    var searchTerms: String {
        switch self {
        case .general: return "launch login language updates menu bar diagnostics"
        case .appearance: return "theme layout mode position bar height spacing icons dark light colour accent"
        case .dockItems: return "dock widgets chips order size presets motion reorder"
        case .widgets: return "pane tiles calendar glass clock tile colors notes stopwatch look"
        case .weather: return "units temperature wind forecast warnings hero animations"
        case .notch: return "island skin style open panel"
        case .notifications: return "battery charging low power peripheral bluetooth history banners"
        case .edgeBars: return "dock side bar auto hide edge"
        case .tiling: return "tiling snap gaps preset layout bsp monocle"
        case .windowManagement: return "window chips floating apps behaviour"
        case .launcher: return "search apps files spotlight"
        case .commandBar: return "command bar hints script commands"
        case .controlCenter: return "panel tiles toggles anchor width"
        case .shortcuts: return "hotkey keyboard keys record hyper caps lock snap"
        case .radialDial: return "pie menu wheel theme"
        case .downloads: return "torrent bittorrent seed upload quiet hours aria2"
        case .tools: return "clipboard color picker teleprompter calculator"
        case .info: return "about version licence help"
        case .advanced: return "reset debug permissions accessibility screen recording"
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

    private var visibleTabs: [SettingsTab] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return SettingsTab.allCases }
        return SettingsTab.allCases.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.searchTerms.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 10) {
            if !isCompact {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit { if let first = visibleTabs.first, !query.isEmpty { open(first) } }
                        .accessibilityLabel(Text("Search settings"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
                .padding(.horizontal, 12)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
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
                .padding(.horizontal, 8)
            }
            Button {
                withAnimation(.snappy) { forcedCompact.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .help(Text("Collapse or expand the sidebar"))
            .accessibilityLabel(Text("Toggle sidebar"))
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .onChange(of: focusSearch) { _ in searchFocused = true }
        .frame(width: isCompact ? SettingsMetrics.sidebarCollapsedWidth : SettingsMetrics.sidebarWidth)
        .background(.ultraThinMaterial)
    }

    private func open(_ tab: SettingsTab) {
        tabState.findQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        tabState.selected = tab
    }

    private func row(_ tab: SettingsTab) -> some View {
        let selected = tabState.selected == tab
        // A selected full-width row is the hue itself, so its tile goes translucent.
        let isPill = selected && !isCompact
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { open(tab) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isPill ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(tab.hueColor.gradient))
                    )
                if !isCompact {
                    Text(tab.title)
                        .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .white : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, isCompact ? 0 : 8)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: isCompact ? .center : .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? tab.hueColor : Color.clear)
            )
            .shadow(color: isPill ? tab.hueColor.opacity(0.35) : .clear, radius: 6, x: 0, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(tab.title))
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
