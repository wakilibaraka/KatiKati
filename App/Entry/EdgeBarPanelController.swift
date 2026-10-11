import AppKit
import Combine
import SwiftUI

/// The deck settings one panel needs (snapshot taken by the orchestrator; `Equatable` so an unchanged
/// snapshot makes `update` a no-op).
struct DeckSettings: Equatable {
    var scale: Double = 1
    var keepOpen = false
    var openOnHover = false
    var tabPreview = true
    var tileStyle: EdgeTileStyle = .glass
    var tabFont = ""
    var yRatio: Double = 0.5
}

/// One deck per `EdgeSlotSet.SlotKey` (Phase 7A-D2): a pill of colour dashes at rest that fans into shingled
/// paper tabs and round buttons when the pointer reaches the edge — after noty's deck (MIT, NOTICE §5).
/// Non-activating, all-Spaces panel, resized per state (never animated; content animates two frames later).
/// Owned by `TaskbarScreenOrchestrator`; never part of `units`. Pointer input arrives from the orchestrator's
/// existing mouse poll (`pollMouse`), so there is no extra global monitor.
@MainActor
final class EdgeBarPanelController {
    let slotKey: EdgeSlotSet.SlotKey
    private let service: SystemStatusService
    private let popup = EdgeFlyoutController()
    private let notesPopup = EdgeNotesPopupController()
    /// Creates the notes controller on first use (§1.7e); nil if the store/key is unavailable.
    private let notesProvider: () -> NotesController?
    private let nowPlayingProvider: () -> NowPlayingService

    private let model = DeckViewModel()
    private(set) var panel: NSPanel?
    private var notesCancellable: AnyCancellable?
    private weak var observedNotes: NotesController?

    private var content: [EdgeBarContent] = []
    private var settings = DeckSettings()
    private var visibleFrame: CGRect = .zero
    private var screenFrame: CGRect = .zero
    private var isHidden = true
    private var state: DeckState = .rest
    private var context = DeckContext()
    private var lastActivity = Date()
    private var lastKeepOpen = false
    private var idleTimer: Timer?
    private var exitWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    private var revealWork: DispatchWorkItem?
    private var hoverID: String?
    private var hoverWork: DispatchWorkItem?
    private var previewID: String?

    init(slotKey: EdgeSlotSet.SlotKey, service: SystemStatusService, notes: @escaping () -> NotesController?,
         nowPlaying: @escaping () -> NowPlayingService) {
        self.slotKey = slotKey
        self.service = service
        self.notesProvider = notes
        self.nowPlayingProvider = nowPlaying
        model.onRight = slotKey.side == .right
        model.onTab = { [weak self] id, rect in self?.tabTapped(id, localRect: rect) }
        model.onButton = { [weak self] button, rect in self?.buttonTapped(button, localRect: rect) }
        notesPopup.onDismiss = { [weak self] outside in self?.notesSheetClosed(outsideClick: outside) }
        model.onReorder = { [weak self] id, slots in self?.notesProvider()?.move(id: id, by: slots) }
        model.onPillDrag = { [weak self] moving in self?.pillDrag(moving: moving) }
        model.onDragging = { [weak self] dragging in
            self?.context.isDragging = dragging
            if dragging { self?.cancelHover() }
        }
        model.onContext = { [weak self] action, id in self?.contextAction(action, id: id) }
    }

    /// Called with (side, ratio) when an ⌥-drag of the pill ends, to persist the new height.
    var onYRatioChanged: ((EdgeSide, Double) -> Void)?
    private var liveRatio: Double?
    private var effectiveRatio: CGFloat { CGFloat(liveRatio ?? settings.yRatio) }

    /// `DOCK_EDGE_FAN=1`: decks start fanned (inspection aid: behaves like keep-open).
    private static let forceFan = DebugSwitch.edgeFan.isEnabled(in: ProcessInfo.processInfo.environment)

    var allSpacesPanels: [NSPanel] { panel.map { [$0] } ?? [] }
    private var side: EdgeSide { slotKey.side }

    // MARK: Update (orchestrator → controller)

    /// Idempotent: repositions, rebuilds items and shows/hides without disturbing an open fan.
    func update(screen: NSScreen?, visible: Bool, content: [EdgeBarContent], settings: DeckSettings) {
        guard visible, let screen, !content.isEmpty else {
            hide()
            return
        }
        let settingsChanged = self.settings != settings
        let contentChanged = self.content != content
        self.settings = settings
        self.content = content
        visibleFrame = screen.visibleFrame
        screenFrame = screen.frame
        let keepOpen = settings.keepOpen || Self.forceFan
        context.keepOpen = keepOpen
        context.openOnHover = settings.openOnHover

        if contentChanged || settingsChanged || panel == nil { rebuildItems() }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        if keepOpen != lastKeepOpen {
            lastKeepOpen = keepOpen
            apply(.keepOpenChanged)
        }
        applyFrame()
        if isHidden {
            panel.orderFrontRegardless()
            isHidden = false
        }
    }

    func hide() {
        guard !isHidden else { return }
        popup.dismiss()
        notesPopup.dismiss(notify: false)
        stopTimers()
        panel?.orderOut(nil)
        isHidden = true
        state = .rest
        model.state = .rest
        model.showsFan = false
        model.revealed = false
    }

    func tearDown() {
        popup.tearDown()
        notesPopup.tearDown()
        stopTimers()
        notesCancellable = nil
        panel?.orderOut(nil)
        panel = nil
        isHidden = true
    }

    // MARK: Items

    private func rebuildItems() {
        model.scale = settings.scale
        model.tileStyle = settings.tileStyle
        model.tabFont = settings.tabFont

        var buttons: [DeckButton] = []
        var hasNotes = false
        for item in content {
            switch item {
            case .notes: hasNotes = true; buttons.append(.newNote)
            case .status: buttons += StatusKind.allCases.map(DeckButton.status)
            case let .widget(tile): buttons.append(.widget(tile))
            }
        }
        if hasNotes { buttons.append(.settings) }
        model.buttons = buttons
        model.accentDashes = buttons.map { NotePalette.entry(at: $0.accent) }

        if hasNotes, let notes = notesProvider() {
            if observedNotes !== notes {
                observedNotes = notes
                model.tabs = notes.notes.filter { !$0.archived }
                notesCancellable = notes.$notes.receive(on: DispatchQueue.main).sink { [weak self] list in
                    self?.model.tabs = list.filter { !$0.archived }
                    self?.applyFrame()
                }
            }
        } else if !hasNotes {
            model.tabs = []
            notesCancellable = nil
            observedNotes = nil
        }
    }

    // MARK: Frames

    private func applyFrame() {
        guard let panel else { return }
        let m = model.metrics
        let frame: CGRect
        if model.showsFan {
            let stack = model.layout(panelHeight: visibleFrame.height).stackHeight
            frame = DeckGeometry.fanFrame(m, side: side, visible: visibleFrame, stackHeight: stack,
                                          itemCount: model.pillItemCount, yRatio: effectiveRatio)
        } else {
            frame = DeckGeometry.restFrame(m, side: side, visible: visibleFrame, itemCount: model.pillItemCount,
                                           yRatio: effectiveRatio)
        }
        panel.ignoresMouseEvents = !model.showsFan
        guard panel.frame != frame else { return }
        // The frame and its content must reach the window server together — never animate the panel.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(frame, display: true, animate: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        CATransaction.commit()
    }

    private func restZone() -> CGRect {
        DeckGeometry.restFrame(model.metrics, side: side, visible: visibleFrame, itemCount: model.pillItemCount,
                               yRatio: effectiveRatio).insetBy(dx: -2, dy: -6)
    }

    // MARK: Pointer (existing orchestrator mouse poll)

    func pollMouse(_ mouse: CGPoint) {
        guard !isHidden, panel != nil else { return }
        switch state {
        case .rest:
            let option = NSEvent.modifierFlags.contains(.option)
            // ⌥ over the pill = grab it (panel takes mouse events); otherwise hovering fans the deck.
            if liveRatio == nil { panel?.ignoresMouseEvents = !(option && restZone().contains(mouse)) }
            if restZone().contains(mouse), !option, liveRatio == nil { apply(.pointerEntered) }
        case .fan, .expanded:
            let inside = (panel?.frame.insetBy(dx: -8, dy: -8).contains(mouse) ?? false)
                || popup.isShown || notesPopup.isShown
            if inside {
                lastActivity = Date()
                exitWork?.cancel()
                exitWork = nil
                trackHover(mouse)
            } else if state == .fan, exitWork == nil {
                cancelHover()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.exitWork = nil
                    let m = NSEvent.mouseLocation
                    if !(self.panel?.frame.insetBy(dx: -8, dy: -8).contains(m) ?? false), !self.popup.isShown {
                        self.apply(.pointerExitConfirmed)
                    }
                }
                exitWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + DeckTiming.exitConfirmDelay, execute: work)
            }
        }
    }

    // MARK: ⌥-drag the pill (vertical only: notes/widgets are bound to their edges)

    private func pillDrag(moving: Bool) {
        guard state == .rest, let panel else { return }
        if moving {
            if liveRatio == nil { NSCursor.closedHand.push() }
            let h = DeckGeometry.pillHeight(model.metrics, itemCount: model.pillItemCount)
            let ratio = DeckGeometry.yRatio(forPointerY: NSEvent.mouseLocation.y, pillHeight: h, visible: visibleFrame)
            liveRatio = Double(ratio)
            applyFrame()
        } else if let ratio = liveRatio {
            NSCursor.pop()
            liveRatio = nil
            onYRatioChanged?(side, ratio)
            settings.yRatio = ratio
            applyFrame()
            panel.ignoresMouseEvents = true
        }
    }

    // MARK: Hover (preview card / hover-to-open), driven by the same mouse poll

    private func tabUnderPointer(_ mouse: CGPoint) -> String? {
        guard let panel, model.showsFan else { return nil }
        return model.tabFrames.first { _, local in
            CGRect(x: panel.frame.minX + local.minX, y: panel.frame.maxY - local.maxY, width: local.width, height: local.height)
                .contains(mouse)
        }?.key
    }

    private func trackHover(_ mouse: CGPoint) {
        guard state == .fan, !context.isDragging else { cancelHover(); return }
        let over = tabUnderPointer(mouse)
        if over == hoverID { return }
        hoverWork?.cancel(); hoverWork = nil
        hoverID = over
        guard let id = over else {
            // Left the tab: drop a preview unless the pointer moved onto the card itself.
            if previewID != nil, !(popup.isShown && popup.frame.insetBy(dx: -4, dy: -4).contains(mouse)) { dismissPreview() }
            return
        }
        if previewID != nil, previewID != id { dismissPreview() }
        let delay = settings.openOnHover ? DeckTiming.hoverOpenDelay : DeckTiming.previewDelay
        guard settings.openOnHover || settings.tabPreview else { return }
        let work = DispatchWorkItem { [weak self] in self?.hoverRested(id) }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hoverRested(_ id: String) {
        guard hoverID == id, state == .fan, !context.isDragging,
              let panel, let local = model.tabFrames[id], let notes = notesProvider() else { return }
        let anchor = CGRect(x: panel.frame.minX + local.minX, y: panel.frame.maxY - local.maxY, width: local.width, height: local.height)
        if settings.openOnHover {
            apply(.hoverRested(id))
            if state == .expanded(id) {
                popup.dismiss()
                notesPopup.toggle(anchor: anchor, side: side, visibleFrame: visibleFrame, controller: notes, select: id)
            }
        } else if let note = notes.note(id: id) {
            previewID = id
            popup.toggle(
                id: "preview.\(id)", anchor: anchor, side: side, visibleFrame: visibleFrame, size: DeckPreviewCard.size,
                content: AnyView(DeckPreviewCard(note: note, onRight: side == .right, onOpen: { [weak self] in
                    self?.dismissPreview()
                    self?.tabTapped(id, localRect: local)
                }))
            )
        }
    }

    private func dismissPreview() {
        previewID = nil
        popup.dismiss()
    }

    private func cancelHover() {
        hoverWork?.cancel(); hoverWork = nil
        hoverID = nil
        if previewID != nil { dismissPreview() }
    }

    private func contextAction(_ action: DeckContextAction, id: String) {
        guard let notes = notesProvider() else { return }
        switch action {
        case .togglePin: notes.togglePin(id: id)
        case let .color(i): notes.setColor(id: id, i)
        case .archive:
            notes.setArchived(id: id, true)
            apply(.noteRemoved(id))
        case .delete:
            notes.delete(id: id)
            apply(.noteRemoved(id))
        }
    }

    // MARK: State machine glue

    private func apply(_ event: DeckEvent) {
        let next = DeckStateMachine.reduce(state, event, context)
        if next != state { transition(to: next) }
    }

    private func transition(to new: DeckState) {
        let old = state
        guard old != new, panel != nil else { return }
        state = new
        model.state = new
        lastActivity = Date()
        shrinkWork?.cancel(); shrinkWork = nil
        revealWork?.cancel(); revealWork = nil

        if new.rank >= old.rank {
            if !model.showsFan {
                // Resize first, reveal two display frames later (animating the resize drags the deck across the screen).
                model.showsFan = true
                applyFrame()
                let work = DispatchWorkItem { [weak self] in
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { self?.model.revealed = true }
                }
                revealWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 / 60.0, execute: work)
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { model.revealed = true }
            }
        } else if new == .rest {
            // Let the exit animation play at full size, then shrink the panel to the pill.
            model.revealed = false
            model.showAll = false
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.state == .rest else { return }
                self.model.showsFan = false
                self.applyFrame()
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
        if new != .rest, new.expandedID == nil { notesPopup.dismiss(notify: false) }
        if new == .rest { popup.dismiss() }
        updateIdleWatch()
    }

    private func updateIdleWatch() {
        let resting = context.restingState
        if state.rank > resting.rank, idleTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.idleTick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            idleTimer = timer
        } else if state.rank <= resting.rank {
            idleTimer?.invalidate()
            idleTimer = nil
        }
    }

    private func idleTick() {
        if popup.isShown || notesPopup.isShown { lastActivity = Date(); return }
        context.openNoteIsPinned = state.expandedID.flatMap { id in model.tabs.first { $0.id == id }?.pinned } ?? false
        apply(.idle(Date().timeIntervalSince(lastActivity)))
    }

    private func stopTimers() {
        idleTimer?.invalidate(); idleTimer = nil
        hoverWork?.cancel(); hoverWork = nil
        exitWork?.cancel(); exitWork = nil
        shrinkWork?.cancel(); shrinkWork = nil
        revealWork?.cancel(); revealWork = nil
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        let panel = NonConstrainingPanel(
            contentRect: CGRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = PanelCollectionBehavior.standard
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: DeckRootView(model: model))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    // MARK: Taps

    /// SwiftUI reports frames in top-left view space; convert to bottom-left screen space.
    private func screenRect(_ localRect: CGRect) -> CGRect? {
        guard let panel else { return nil }
        return CGRect(x: panel.frame.minX + localRect.minX, y: panel.frame.maxY - localRect.maxY,
                      width: localRect.width, height: localRect.height)
    }

    private func tabTapped(_ id: String, localRect: CGRect) {
        guard let anchor = screenRect(localRect), let notes = notesProvider() else { return }
        popup.dismiss()
        lastActivity = Date()
        let wasOpen = state == .expanded(id)
        apply(.tabClicked(id))
        if wasOpen {
            notesPopup.dismiss(notify: false)
        } else {
            notesPopup.toggle(anchor: anchor, side: side, visibleFrame: visibleFrame, controller: notes, select: id)
        }
    }

    private func notesSheetClosed(outsideClick: Bool) {
        apply(outsideClick ? .outsideClick : .escape)
    }

    private func buttonTapped(_ button: DeckButton, localRect: CGRect) {
        guard let anchor = screenRect(localRect) else { return }
        lastActivity = Date()
        switch button {
        case .newNote:
            guard let notes = notesProvider() else { return }
            let note = notes.create()
            popup.dismiss()
            apply(.tabClicked(note.id))
            notesPopup.toggle(anchor: anchor, side: side, visibleFrame: visibleFrame, controller: notes, select: note.id)
        case .settings:
            (NSApp.delegate as? AppDelegate)?.openSettings(selecting: .layout)
        case let .status(kind):
            notesPopup.dismiss(notify: false)
            popup.toggle(
                id: "status.\(kind)", anchor: anchor, side: side, visibleFrame: visibleFrame,
                size: kind.popupSize, content: AnyView(StatusPopupView(kind: kind, service: service))
            )
        case let .widget(tile):
            notesPopup.dismiss(notify: false)
            switch tile {
            case .weather:
                popup.dismiss()
                WidgetPanelController.weather.toggle()
            case .bluetooth:
                popup.toggle(id: "widget.bluetooth", anchor: anchor, side: side, visibleFrame: visibleFrame,
                             size: BluetoothFlyoutView.size, content: AnyView(BluetoothFlyoutView()))
            case .nowPlaying:
                popup.toggle(id: "widget.nowPlaying", anchor: anchor, side: side, visibleFrame: visibleFrame,
                             size: CGSize(width: 300, height: 120),
                             content: AnyView(NowPlayingFlyoutView(service: nowPlayingProvider())))
            }
        }
    }
}
