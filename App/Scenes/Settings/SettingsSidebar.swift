import SwiftUI

extension SettingsTab {
    var hueColor: Color { Color(red: hue.red, green: hue.green, blue: hue.blue) }
}

/// The Settings window's only navigation (macOS System Settings style): search first, then one row
/// per section with a hue-coloured icon. Icons-only when the window is narrow or the user collapses it.
struct SettingsSidebar: View {
    @ObservedObject var tabState: SettingsTabState
    let isCompact: Bool
    @Binding var forcedCompact: Bool

    @State private var query = ""

    private var visibleTabs: [SettingsTab] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return SettingsTab.allCases }
        return SettingsTab.allCases.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 10) {
            if !isCompact {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
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
        .frame(width: isCompact ? SettingsMetrics.sidebarCollapsedWidth : SettingsMetrics.sidebarWidth)
        .background(.ultraThinMaterial)
    }

    private func row(_ tab: SettingsTab) -> some View {
        let selected = tabState.selected == tab
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { tabState.selected = tab }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tab.hueColor.gradient))
                if !isCompact {
                    Text(tab.title)
                        .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, isCompact ? 0 : 8)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: isCompact ? .center : .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? tab.hueColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(tab.title))
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
