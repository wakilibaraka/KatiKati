import CoreGraphics
import Foundation

/// One workspace identity: a numbered workspace 1…10, or an opt-in named workspace A…Z (W-1).
///
/// Ported from spaceman's workspace identity. Nothing here knows about AppKit or Accessibility: the
/// engine decides what to do with these values, this file only names and orders them.
enum WorkspaceID: Hashable, Sendable {
    case numbered(Int)
    case named(Character)

    static let numberedRange: ClosedRange<Int> = 1...10

    /// The ten numbered workspaces, in order.
    static let allNumbered: [WorkspaceID] = numberedRange.map(WorkspaceID.numbered)

    /// Parses `"3"`, `"10"` or `"D"`. Returns nil for anything outside 1…10 or not an ASCII letter.
    init?(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(trimmed) {
            guard Self.numberedRange.contains(number) else { return nil }
            self = .numbered(number)
            return
        }
        let upper = trimmed.uppercased()
        guard upper.count == 1, let letter = upper.first, letter.isLetter, letter.isASCII else { return nil }
        self = .named(letter)
    }

    /// The persisted and printed form: `"1"`…`"10"`, or one letter.
    var token: String {
        switch self {
        case .numbered(let number): return String(number)
        case .named(let letter): return String(letter)
        }
    }

    /// Sort order: numbered first (1…10), then letters (A…Z).
    var sortIndex: Int {
        switch self {
        case .numbered(let number): return number
        case .named(let letter): return 1000 + Int(letter.asciiValue ?? 0)
        }
    }

    /// ANSI number-row key codes for 1…9 then 0, so the ten switch shortcuts need no second table.
    static let numberRowKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]

    /// The key code that switches to this workspace on the number row, if it has one.
    var shortcutKeyCode: UInt16? {
        guard case .numbered(let number) = self, Self.numberedRange.contains(number) else { return nil }
        return Self.numberRowKeyCodes[number - 1]
    }

    /// The numbered workspace a number-row key code selects.
    static func numbered(forKeyCode keyCode: UInt16) -> WorkspaceID? {
        guard let index = numberRowKeyCodes.firstIndex(of: keyCode) else { return nil }
        return .numbered(index + 1)
    }

}

extension WorkspaceID: Comparable {
    static func < (lhs: WorkspaceID, rhs: WorkspaceID) -> Bool { lhs.sortIndex < rhs.sortIndex }
}

extension WorkspaceID: Codable {
    init(from decoder: Decoder) throws {
        let token = try decoder.singleValueContainer().decode(String.self)
        guard let id = WorkspaceID(token: token) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown workspace token \(token)"
            ))
        }
        self = id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }
}

/// Which workspaces exist and which display each one belongs to (W-1).
///
/// Numbered workspaces always exist. Named workspaces are opt-in: a letter counts as enabled once
/// something refers to it (a route rule, an assignment, or a window parked in it), which is the same
/// rule spaceman uses. An unassigned workspace follows whichever display is showing it.
struct WorkspaceRegistry: Equatable, Sendable, Codable {
    /// Enabled workspaces, in listing order.
    var workspaces: [WorkspaceID]
    /// Workspace → display key (screen UUID or, failing that, the display name).
    var displays: [WorkspaceID: String]

    static let `default` = WorkspaceRegistry()

    init(
        workspaces: [WorkspaceID] = WorkspaceID.allNumbered,
        displays: [WorkspaceID: String] = [:]
    ) {
        self.workspaces = workspaces
        // Keep the list sorted and duplicate-free; a hand-written state file must not be able to
        // put the HUD into an inconsistent order.
        var seen = Set<WorkspaceID>()
        self.workspaces = workspaces.sorted().filter { seen.insert($0).inserted }
        self.displays = displays
    }

    /// The opt-in named workspaces (letters sort after every number).
    var named: [WorkspaceID] { workspaces.filter { $0.sortIndex >= 1000 } }

    func display(for workspace: WorkspaceID) -> String? { displays[workspace] }

    mutating func setDisplay(_ display: String?, for workspace: WorkspaceID) {
        guard workspaces.contains(workspace) else { return }
        if let display, !display.isEmpty {
            displays[workspace] = display
        } else {
            displays.removeValue(forKey: workspace)
        }
    }

    /// Enables a named workspace. Numbered ones are always enabled.
    mutating func enable(_ workspace: WorkspaceID) {
        guard !workspaces.contains(workspace) else { return }
        workspaces = (workspaces + [workspace]).sorted()
    }

    /// The workspaces a display lists: those assigned to it, or every unassigned one. A display that
    /// has no workspaces assigned to it at all lists all of them, which is the single-display case.
    func workspaces(on displayKey: String) -> [WorkspaceID] {
        let assigned = workspaces.filter { displays[$0] == displayKey }
        let unassigned = workspaces.filter { displays[$0] == nil }
        let listed = assigned + unassigned
        // Nothing assigned anywhere: every workspace follows every display, which is the
        // single-display case. A workspace assigned to another display is that display's alone.
        return listed.isEmpty ? workspaces : listed.sorted()
    }

    /// Next/previous workspace on a display, stopping at either end. Spaceman stops rather than
    /// wrapping, and a wrapping shortcut that jumps from 10 back to 1 by accident is worse than one
    /// that does nothing at the edge.
    func step(from workspace: WorkspaceID, by offset: Int, on displayKey: String) -> WorkspaceID? {
        let list = workspaces(on: displayKey)
        guard let index = list.firstIndex(of: workspace) else { return nil }
        let target = index + offset
        guard list.indices.contains(target) else { return nil }
        return list[target]
    }
}

/// One workspace's window ownership: which windows are in it, per display, in join order (W-1).
///
/// Deliberately not a `TilingTree`: persisted state carries *which workspace a window belongs to*,
/// never its tile position or split weights. That is spaceman's documented limit too (its own
/// limitations file: remembered placements restore workspace and floating state, not tile position),
/// and it is the honest one — a window's Accessibility identity does not survive the app relaunching.
struct WorkspaceLayout: Equatable, Sendable, Codable {
    /// Display key → windows, in the order they joined.
    var windows: [String: [WindowID]]
    /// Display key → the window that had focus when the workspace was last left.
    var focus: [String: WindowID]

    init(windows: [String: [WindowID]] = [:], focus: [String: WindowID] = [:]) {
        self.windows = windows
        self.focus = focus
    }

    func windows(on displayKey: String) -> [WindowID] { windows[displayKey] ?? [] }

    func contains(_ id: WindowID) -> Bool {
        windows.values.contains { $0.contains(id) }
    }

    /// The display this layout holds `id` on, if it holds it at all.
    func displayKey(of id: WindowID) -> String? {
        windows.first { $0.value.contains(id) }?.key
    }

    var allWindowIDs: [WindowID] { windows.keys.sorted().flatMap { windows[$0] ?? [] } }

    /// Adds a window once, keeping its existing position if it is already here.
    mutating func assign(_ id: WindowID, to displayKey: String) {
        var list = windows[displayKey] ?? []
        guard !list.contains(id) else { return }
        list.append(id)
        windows[displayKey] = list
    }

    /// Removes a window from every display, and clears it as the remembered focus.
    mutating func remove(_ id: WindowID) {
        // Snapshot the keys: mutating a dictionary while iterating its own `keys` view traps.
        for key in Array(windows.keys) {
            windows[key]?.removeAll { $0 == id }
            if windows[key]?.isEmpty == true { windows.removeValue(forKey: key) }
        }
        for (key, value) in focus where value == id {
            focus.removeValue(forKey: key)
        }
    }

    mutating func setFocus(_ id: WindowID?, on displayKey: String) {
        if let id, contains(id) {
            focus[displayKey] = id
        } else {
            focus.removeValue(forKey: displayKey)
        }
    }

    /// The remembered focus, or the first window on that display when it has none.
    func focusTarget(on displayKey: String) -> WindowID? {
        if let remembered = focus[displayKey], (windows[displayKey] ?? []).contains(remembered) {
            return remembered
        }
        return windows[displayKey]?.first
    }
}

/// Every workspace's ownership in one value (W-1). Pure: assigning, moving and removing windows is
/// all this does; parking frames and AX writes belong to the engine.
struct WorkspaceStore: Equatable, Sendable, Codable {
    var layouts: [WorkspaceID: WorkspaceLayout]

    init(layouts: [WorkspaceID: WorkspaceLayout] = [:]) {
        self.layouts = layouts
    }

    /// The workspace a window belongs to, if it has been assigned one.
    func workspace(of id: WindowID) -> WorkspaceID? {
        layouts.first { $0.value.contains(id) }?.key
    }

    func layout(_ workspace: WorkspaceID) -> WorkspaceLayout { layouts[workspace] ?? WorkspaceLayout() }

    /// The display a window is owned on. Ownership is per display, so this is how the engine notices
    /// a window that has moved to the other screen.
    func displayKey(of id: WindowID) -> String? {
        for workspace in layouts.keys.sorted() {
            if let key = layouts[workspace]?.displayKey(of: id) { return key }
        }
        return nil
    }

    mutating func assign(_ id: WindowID, to workspace: WorkspaceID, on displayKey: String) {
        remove(id)
        var layout = layouts[workspace] ?? WorkspaceLayout()
        layout.assign(id, to: displayKey)
        layouts[workspace] = layout
    }

    /// Moves a window to another workspace and returns the workspace it came from.
    @discardableResult
    mutating func move(_ id: WindowID, to workspace: WorkspaceID, on displayKey: String) -> WorkspaceID? {
        let previous = self.workspace(of: id)
        guard previous != workspace else { return previous }
        assign(id, to: workspace, on: displayKey)
        return previous
    }

    mutating func remove(_ id: WindowID) {
        for key in Array(layouts.keys) {
            layouts[key]?.remove(id)
            if layouts[key]?.windows.isEmpty == true, layouts[key]?.focus.isEmpty == true {
                layouts.removeValue(forKey: key)
            }
        }
    }

    mutating func setFocus(_ id: WindowID?, in workspace: WorkspaceID, on displayKey: String) {
        guard var layout = layouts[workspace] else { return }
        layout.setFocus(id, on: displayKey)
        layouts[workspace] = layout
    }

    func windows(in workspace: WorkspaceID, on displayKey: String) -> [WindowID] {
        layouts[workspace]?.windows(on: displayKey) ?? []
    }

    func focusTarget(in workspace: WorkspaceID, on displayKey: String) -> WindowID? {
        layouts[workspace]?.focusTarget(on: displayKey)
    }

    /// Every window on `displayKey` outside `workspace`: the set a switch has to park.
    func windowsOutside(_ workspace: WorkspaceID, on displayKey: String) -> [WindowID] {
        layouts
            .filter { $0.key != workspace }
            .sorted { $0.key < $1.key }
            .flatMap { $0.value.windows(on: displayKey) }
    }
}

/// What one workspace switch does on one display (W-1).
///
/// The engine parks `park`, reveals `reveal`, then retiles and focuses `focus`. Keeping this as a
/// value means the whole switch is testable without a window, a screen or Accessibility permission.
struct WorkspaceTransitionPlan: Equatable, Sendable {
    var leaving: WorkspaceID
    var entering: WorkspaceID
    var displayKey: String
    /// Windows that were showing and now belong off screen, in park order.
    var park: [WindowID]
    /// Windows that now belong on screen, in reveal order.
    var reveal: [WindowID]
    /// The window to focus once the switch settles.
    var focus: WindowID?

    static func plan(
        store: WorkspaceStore,
        leaving: WorkspaceID,
        entering: WorkspaceID,
        displayKey: String
    ) -> WorkspaceTransitionPlan {
        WorkspaceTransitionPlan(
            leaving: leaving,
            entering: entering,
            displayKey: displayKey,
            park: store.windows(in: leaving, on: displayKey),
            reveal: store.windows(in: entering, on: displayKey),
            focus: store.focusTarget(in: entering, on: displayKey)
        )
    }

    /// A switch to the workspace already showing is not a transition.
    var isEmpty: Bool { leaving == entering }
}
