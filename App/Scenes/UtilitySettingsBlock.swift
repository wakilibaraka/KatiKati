import SwiftUI

/// Phase 8e — Settings row for the menu utilities that need a switch (the link cleaner; the colour picker
/// is a menu action and needs none). Same plain-row shape as `LiveIslandSettingsBlock`.
struct UtilitySettingsBlock: View {
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        HStack {
            Text("Clean Copied Links")
            Spacer(minLength: 12)
            Toggle("Clean Copied Links", isOn: Binding(get: { store.linkCleanerEnabled }, set: { store.setLinkCleanerEnabled($0) }))
                .toggleStyle(.switch).labelsHidden()
        }
    }
}
