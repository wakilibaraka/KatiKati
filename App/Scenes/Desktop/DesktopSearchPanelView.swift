import AppKit
import SwiftUI

private struct DesktopSearchRowFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Unified results for files, apps, Settings pages, notes and to-dos, with ⌘/⇧ multi-select,
/// a rubber-band selection rectangle and batch actions.
struct DesktopSearchPanelView: View {
    @ObservedObject var service: DesktopSearchService
    let onDismiss: () -> Void

    @ObservedObject private var manager = DesktopCanvasManager.shared
    @FocusState private var searchFocused: Bool
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var bandRect: CGRect?
    @State private var confirmTrash = false
    @State private var actionError: String?

    private let space = "desktopSearchResults"

    private var folderBoxes: [DesktopWidgetItem] {
        (manager.activeCoordinator?.store.items ?? [])
            .filter { $0.kind == .folder && !$0.isHidden && $0.backingPath != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 760, height: 500)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .alert(Text("Move to Trash?"), isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) {
                DesktopSearchActions.confirmAndTrash(service.selectedResults)
                onDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected files will be moved to the Trash.")
        }
        .alert(Text("Could Not Move"), isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(verbatim: actionError ?? "")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "Search files, apps, settings, notes and to-dos",
                text: Binding(get: { service.query }, set: { service.setQuery($0) })
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($searchFocused)
            .onSubmit { service.submit() }

            if service.isSearching {
                ProgressView().controlSize(.small)
            }
            if !service.query.isEmpty {
                Button {
                    service.setQuery("", immediate: true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear Search"))
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var content: some View {
        if service.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            idleContent
        } else if service.results.isEmpty {
            VStack(spacing: 8) {
                if service.isSearching {
                    ProgressView()
                    Text("Searching…").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No Results").font(.headline)
                    Text("Try a file name, an app, a Settings page, a note or a to-do.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            resultsList
        }
    }

    private var idleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !service.favorites.items.isEmpty {
                    chipSection(Text("Favorites")) {
                        ForEach(service.favorites.items) { favorite in
                            chip(favorite.result.title, symbol: favorite.result.symbol) {
                                service.setQuery(favorite.result.title, immediate: true)
                            }
                        }
                    }
                }
                if !service.history.queries.isEmpty {
                    chipSection(Text("Recent Searches")) {
                        ForEach(service.history.queries, id: \.self) { query in
                            chip(query, symbol: "clock.arrow.circlepath") {
                                service.setQuery(query, immediate: true)
                                service.submit()
                            }
                        }
                        Button("Clear") { service.clearHistory() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if service.favorites.items.isEmpty && service.history.queries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Search Everything").font(.headline)
                        Text("Spotlight files, installed apps, Settings pages, your notes and to-dos — ranked together.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Click a row, ⌘-click to add, ⇧-click for a range, or drag a rectangle across rows for a batch.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(service.results) { result in
                    resultRow(result)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(DesktopSearchRowFramesKey.self) { rowFrames = $0 }
        .overlay(alignment: .topLeading) {
            if let bandRect {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1))
                    .frame(width: bandRect.width, height: bandRect.height)
                    .offset(x: bandRect.minX, y: bandRect.minY)
                    .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named(space))
                .onChanged { value in
                    let rect = CGRect(
                        x: min(value.startLocation.x, value.location.x),
                        y: min(value.startLocation.y, value.location.y),
                        width: abs(value.location.x - value.startLocation.x),
                        height: abs(value.location.y - value.startLocation.y)
                    )
                    bandRect = rect
                    service.rubberBand(rect, rowFrames: rowFrames)
                }
                .onEnded { _ in bandRect = nil }
        )
    }

    private func resultRow(_ result: DesktopSearchResult) -> some View {
        let selected = service.selection.isSelected(result.id)
        return HStack(spacing: 10) {
            Image(systemName: result.symbol)
                .font(.system(size: 16))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: result.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(verbatim: result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(providerLabel(result.provider))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.quaternary))
            Button {
                service.toggleFavorite(result)
            } label: {
                Image(systemName: service.isFavorite(result.id) ? "star.fill" : "star")
                    .foregroundStyle(service.isFavorite(result.id) ? Color.yellow : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Favorite"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { service.tap(result.id) }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DesktopSearchRowFramesKey.self,
                    value: [result.id: proxy.frame(in: .named(space))]
                )
            }
        )
    }

    @ViewBuilder
    private var footer: some View {
        let selected = service.selectedResults
        HStack(spacing: 8) {
            if selected.isEmpty {
                Text("⏎ Open · ⌘C Copy · Drag to select")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Command Bar") {
                    onDismiss()
                    AppDelegate.shared?.presentCommandBar(query: service.query)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else {
                Text(verbatim: String(format: String(localized: "%lld selected"), selected.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(DesktopSearchBatchAction.available(for: selected), id: \.rawValue) { action in
                    batchButton(action, selected: selected)
                }
                Button("Clear") { service.clearSelection() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func batchButton(_ action: DesktopSearchBatchAction, selected: [DesktopSearchResult]) -> some View {
        switch action {
        case .moveToBox:
            Menu {
                if folderBoxes.isEmpty {
                    Text("No Desktop folder boxes")
                } else {
                    ForEach(folderBoxes) { box in
                        Button {
                            if let error = DesktopSearchActions.move(selected, toBox: box) {
                                actionError = error
                            } else {
                                onDismiss()
                            }
                        } label: {
                            Text(verbatim: box.title)
                        }
                    }
                }
            } label: {
                Text("Move to Box")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.caption)
        case .trash:
            Button("Move to Trash") { confirmTrash = true }
                .buttonStyle(.borderless)
                .font(.caption)
        case .open:
            Button("Open") { perform(action, selected: selected) }
                .buttonStyle(.borderless)
                .font(.caption)
        case .reveal:
            Button("Reveal") { perform(action, selected: selected) }
                .buttonStyle(.borderless)
                .font(.caption)
        case .copy:
            Button("Copy") { perform(action, selected: selected) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private func perform(_ action: DesktopSearchBatchAction, selected: [DesktopSearchResult]) {
        switch action {
        case .open:
            DesktopSearchActions.open(selected)
            onDismiss()
        case .reveal:
            DesktopSearchActions.reveal(selected)
            onDismiss()
        case .copy:
            _ = DesktopSearchActions.copy(selected)
        case .moveToBox, .trash:
            break
        }
    }

    private func providerLabel(_ provider: DesktopSearchProvider) -> String {
        switch provider {
        case .app: return String(localized: "App")
        case .setting: return String(localized: "Settings")
        case .note: return String(localized: "Note")
        case .todo: return String(localized: "To-Do")
        case .file: return String(localized: "File")
        }
    }

    private func chipSection<Content: View>(_ title: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content() }
            }
        }
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(verbatim: title)
                    .lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.quaternary))
        }
        .buttonStyle(.plain)
    }
}

