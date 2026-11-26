import AppKit
import Foundation

struct CursorPopoverInsets: Equatable, Sendable {
    var top: CGFloat
    var bottom: CGFloat
    var left: CGFloat
    var right: CGFloat
    init(top: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0) {
        self.top = max(0, top); self.bottom = max(0, bottom)
        self.left = max(0, left); self.right = max(0, right)
    }
}

enum CursorPopoverGeometry {
    static let cursorGap: CGFloat = 12

    /// MD-3: the display a cursor-anchored popover belongs on — the one under the pointer, else the
    /// main display, else the first. A popover must not open on a screen the user is not looking at
    /// just because that screen owns the menu bar.
    @MainActor
    static func screen(for cursor: CGPoint = NSEvent.mouseLocation,
                       screens: [NSScreen] = NSScreen.screens,
                       main: NSScreen? = NSScreen.main) -> NSScreen? {
        screens.first { $0.frame.contains(cursor) } ?? main ?? screens.first
    }
    static func frame(cursor: CGPoint, size requestedSize: CGSize, visibleFrame: CGRect,
                      insets: CursorPopoverInsets = CursorPopoverInsets()) -> CGRect {
        let insetFrame = CGRect(
            x: visibleFrame.minX + insets.left,
            y: visibleFrame.minY + insets.bottom,
            width: max(0, visibleFrame.width - insets.left - insets.right),
            height: max(0, visibleFrame.height - insets.top - insets.bottom)
        )
        guard insetFrame.width > 0, insetFrame.height > 0 else { return .zero }
        let width = min(max(1, requestedSize.width), insetFrame.width)
        let height = min(max(1, requestedSize.height), insetFrame.height)
        var x = cursor.x + cursorGap
        if x + width > insetFrame.maxX { x = cursor.x - cursorGap - width }
        var y = cursor.y - cursorGap - height
        if y < insetFrame.minY { y = cursor.y + cursorGap }
        x = min(max(x, insetFrame.minX), insetFrame.maxX - width)
        y = min(max(y, insetFrame.minY), insetFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

import CoreGraphics

/// Taskbar height as the user dragged it: whole points, clamped to `minimum...maximum`.
///
/// Every scaled size multiplies `scale`, which is normalised to `native` (the real Dock's
/// bar height) so that a bar at 54pt renders byte-for-byte the signed-off native pixels.
/// Heights are rounded to whole points before anything derives from them; a fractional
/// height would put corner radius, icons and the hairline divider on half pixels.
struct DockPanelHeight: Equatable {
    /// 32…90 (owner 2026-10-13: was 120, the Dock's own Size reach). Above ~90 the islands, widget
    /// pills and the apps row stop fitting a laptop screen, so the cap is a comfort band. Both ends are reached only through the
    /// status-menu slider or the grip; nothing seeds them. Below ~38pt the unscaled 9pt ▲▼ grip
    /// glyph reaches past the chip *frame* by under 1pt but stays short of the icon artwork
    /// (`ChipPillMetrics.bareIconVisibleSlot` keeps 3.75pt × scale of transparent margin).
    static let minimum: CGFloat = 32
    static let maximum: CGFloat = 90

    /// 54 = the native macOS Dock bar height (@2x screenshot: 108px). Icons (40pt,
    /// `ChipHoverVisual.bareIconSize`) and `ChipPillMetrics.chipHeight` are tuned to it;
    /// changing one without the others breaks the 0.741 icon/bar ratio.
    static let native = DockPanelHeight(validated: 54)
    static let `default` = native

    let points: CGFloat

    /// Non-finite → default; otherwise rounded to whole points and clamped.
    init(clamping raw: CGFloat) {
        guard raw.isFinite else {
            self = .default
            return
        }
        self.init(validated: min(max(raw.rounded(), Self.minimum), Self.maximum))
    }

    private init(validated points: CGFloat) {
        self.points = points
    }

    /// Multiplier for every tier-scaled size. Exactly `1.0` at `native`.
    var scale: CGFloat { points / Self.native.points }

    /// Legacy four-tier raw values (`com.katikati.dockSize`), read once for migration.
    static func migratingLegacyTier(rawValue: String) -> DockPanelHeight? {
        switch rawValue {
        case "small": return DockPanelHeight(clamping: 46)
        case "medium": return DockPanelHeight(clamping: 54)
        case "large": return DockPanelHeight(clamping: 62)
        case "extraLarge": return DockPanelHeight(clamping: 70)
        default: return nil
        }
    }

    /// The single source of panel geometry: AppKit (`PanelCoordinator`) and SwiftUI both
    /// read it, never their own copy. Uses the floating bottom gap; live callers go through
    /// `AppSettingsStore.layoutMetrics`, which threads the user's `bottomGap`.
    var metrics: PanelLayoutMetrics { metrics(bottomGap: PanelLayoutMetrics.floatingBottomGap) }

    /// Phase 6 hug toggle: `bottomGap` is the only input not derived from the height.
    func metrics(bottomGap: CGFloat) -> PanelLayoutMetrics {
        PanelLayoutMetrics(
            panelHeight: points,
            // Shadow padding never scales: the shadow tokens are frozen.
            shadowPadding: PanelLayoutMetrics.shadowPadding,
            // Written as an expression, not a literal: the relation used to live only in a
            // comment and is exactly what a height change forgets.
            windowHeight: points + 2 * PanelLayoutMetrics.shadowPadding,
            bottomGap: bottomGap,
            outerMargin: 12,
            capsuleWidth: points,
            capsuleGap: 8,
            minimumDockWidth: 120 * scale,
            minimumDrawerExtent: 120
        )
    }
}

struct PanelLayoutMetrics: Equatable {
    var panelHeight: CGFloat
    var shadowPadding: CGFloat
    var windowHeight: CGFloat
    var bottomGap: CGFloat
    var outerMargin: CGFloat
    var capsuleWidth: CGFloat
    var capsuleGap: CGFloat
    var minimumDockWidth: CGFloat
    var minimumDrawerExtent: CGFloat

    /// Fixed; never scales with the bar height (see `DockPanelHeight.metrics`).
    static let shadowPadding: CGFloat = 20

    /// Gap between the bar and the screen's bottom edge. Floating (8) is the tungsten
    /// original; Hugging (2) is the opt-in preset (`com.katikati.layout.bottomGap`).
    static let floatingBottomGap: CGFloat = 8
    static let huggingBottomGap: CGFloat = 2
    static let bottomGapRange: ClosedRange<CGFloat> = 0...12

    /// Native-height baseline for default parameters and tests; real values come from
    /// `DockPanelHeight.metrics`.
    static let tungstenEdge = DockPanelHeight.native.metrics
}

/// The drawer capsule's preview (2 × 2): three directly clickable apps plus a bottom-trailing
/// "expand" cell that shows the next four as a mini grid. Values are at the native height and
/// scale with the bar: `columns × icon + spacing + 2 × padding` must fit `capsuleWidth` at every
/// height (`PanelGeometryTests.testCapsuleGridContentFitsEveryHeight`).
enum DrawerCapsulePreviewMetrics {
    static let columns = 2
    /// Every cell but the bottom-trailing one launches an app.
    static let appSlots = columns * columns - 1
    static let miniColumns = 2
    static let miniLimit = miniColumns * miniColumns
    static let limit = appSlots + miniLimit
    // Proportions follow the system's app-library tile, on the visible artwork: a gap of about a
    // fifth of an icon, mini icons 0.4 of an icon. App icon assets carry ~9% transparent margin
    // per side, which already is that gap, so the frames touch. The 42pt the two columns span
    // keeps the icons clear of the capsule rim; growing it puts their corners against it.
    static let iconSize: CGFloat = 21
    static let gridSpacing: CGFloat = 0
    static let gridPadding: CGFloat = 4
    static let miniIconSize: CGFloat = 8.5
    static let miniSpacing: CGFloat = 0
    static let hoverScale: CGFloat = 1.1
    static let bounceHeight: CGFloat = 3

    /// The mini grid sits centred in one app cell and must not outgrow it.
    static var miniGridWidth: CGFloat {
        CGFloat(miniColumns) * miniIconSize + CGFloat(miniColumns - 1) * miniSpacing
    }

    static var contentWidth: CGFloat {
        CGFloat(columns) * iconSize + CGFloat(columns - 1) * gridSpacing + 2 * gridPadding
    }
}

/// Paging of the capsule preview: a page is three apps plus a mini grid of the next four.
/// `page` is where the capsule rests; `drag` is the live trackpad travel in pages.
enum DrawerCapsulePaging {
    /// Travel past which a released trackpad gesture turns the page instead of springing back.
    static let turnThreshold: CGFloat = 0.15
    /// How much of the overscroll past the first / last page is shown.
    static let rubberBand: CGFloat = 0.15
    /// Where one app's icon is drawn: its centre relative to the capsule's centre and its side
    /// length, both at the native height.
    struct IconPose: Equatable {
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
    }

    /// The pose of the icon resting in `slot`, counted from the first app of the shown page:
    /// 0...2 are the three app cells, 3...6 the mini grid. The page before (-3...-1) has shrunk
    /// to nothing in its app cell; the three after the mini grid (7...9) wait at zero size on the
    /// mini spots they are about to take. Everything further away is at zero size.
    static func restPose(slot: Int) -> IconPose {
        typealias M = DrawerCapsulePreviewMetrics
        let pitch = M.iconSize + M.gridSpacing
        func cell(_ index: Int) -> (x: CGFloat, y: CGFloat) {
            let wrapped = ((index % M.appSlots) + M.appSlots) % M.appSlots
            return (x: (CGFloat(wrapped % M.columns) - 0.5) * pitch, y: (CGFloat(wrapped / M.columns) - 0.5) * pitch)
        }
        func mini(_ index: Int) -> (x: CGFloat, y: CGFloat) {
            let miniPitch = M.miniIconSize + M.miniSpacing
            return (x: pitch / 2 + (CGFloat(index % M.miniColumns) - 0.5) * miniPitch,
                    y: pitch / 2 + (CGFloat(index / M.miniColumns) - 0.5) * miniPitch)
        }
        switch slot {
        case 0..<M.appSlots:
            let c = cell(slot)
            return IconPose(x: c.x, y: c.y, size: M.iconSize)
        case M.appSlots..<M.limit:
            let c = mini(slot - M.appSlots)
            return IconPose(x: c.x, y: c.y, size: M.miniIconSize)
        case M.limit..<(M.limit + M.appSlots):
            let c = mini(slot - 2 * M.appSlots)
            return IconPose(x: c.x, y: c.y, size: 0)
        default:
            let c = cell(slot)
            return IconPose(x: c.x, y: c.y, size: 0)
        }
    }

    /// Share of a turn during which a replaced app keeps its full size before it starts to shrink,
    /// so mid-turn the cell still holds two near-even icons instead of two small ones.
    static let leaveHold: CGFloat = 0.2
    /// Share of a turn before a new mini icon starts to grow: its spot is still held by the icon
    /// leaving it. The last spot waits longer — the fourth mini icon crosses the grid to vacate it.
    static let fillDelay: CGFloat = 0.3
    static let lastFillDelay: CGFloat = 0.45

    /// The pose of app `index` while the capsule is at `position` pages: a path between its
    /// resting poses on the two neighbouring pages (bowed slightly for two of the app cells, see
    /// `cellBend`). Turning forward, the first three mini icons grow and travel onto the three app
    /// cells while the apps there shrink away beneath.
    static func pose(index: Int, position: CGFloat) -> IconPose {
        let lower = position.rounded(.down)
        let t = position - lower
        let slot = index - Int(lower) * DrawerCapsulePreviewMetrics.appSlots
        let from = restPose(slot: slot)
        guard t > 0 else { return from }
        let to = restPose(slot: slot - DrawerCapsulePreviewMetrics.appSlots)
        let grown = sizeProgress(slot: slot, t: t)
        let bend = travelBend(slot: slot)
        let arc = 4 * t * (1 - t)
        return IconPose(x: from.x + (to.x - from.x) * t + arc * bend.x,
                        y: from.y + (to.y - from.y) * t + arc * bend.y,
                        size: from.size + (to.size - from.size) * grown)
    }

    /// Mid-turn offset from a straight path for the icon travelling onto each app cell
    /// (top-leading, top-trailing, bottom-leading). The two side paths bow a point and a half
    /// towards the capsule's inside, which also keeps the growing icons within the resting icons'
    /// outer edge; the diagonal stays straight. No rotation and no overshoot: in a cell this
    /// small either competes with the icons themselves.
    static let cellBend: [(x: CGFloat, y: CGFloat)] = [(0, 0), (-1.5, 0), (0, -1.5)]

    private static func travelBend(slot: Int) -> (x: CGFloat, y: CGFloat) {
        let appSlots = DrawerCapsulePreviewMetrics.appSlots
        guard (appSlots..<(2 * appSlots)).contains(slot) else { return (0, 0) }
        return cellBend[slot - appSlots]
    }

    /// How far the size has moved towards the next page's, for the icon resting in `slot` on the
    /// lower page. Only a function of the position, so a turn played backwards retraces it.
    private static func sizeProgress(slot: Int, t: CGFloat) -> CGFloat {
        let appSlots = DrawerCapsulePreviewMetrics.appSlots
        switch slot {
        case 0..<appSlots:
            // A replaced app holds, then shrinks; it reaches zero (and is hidden) only at the end.
            return smoothstep((t - leaveHold) / (1 - leaveHold))
        case appSlots..<(2 * appSlots):
            // A mini icon growing onto an app cell settles into its full size.
            return smoothstep(t)
        case DrawerCapsulePreviewMetrics.limit..<(DrawerCapsulePreviewMetrics.limit + appSlots):
            // A new mini icon grows only once its spot has emptied, so it never crowds the leaver.
            let isLastSpot = slot == DrawerCapsulePreviewMetrics.limit + appSlots - 1
            let delay = isLastSpot ? lastFillDelay : fillDelay
            return smoothstep((t - delay) / (1 - delay))
        default:
            return t
        }
    }

    /// Share of a turn over which the hover lift folds away after leaving a page, and comes back
    /// before reaching the next one.
    static let hoverSettle: CGFloat = 0.08

    /// How much of the hover lift may show at `position`: all of it at rest, none mid-turn. A
    /// function of the position, not of time, so hover never resizes an icon while it travels.
    static func hoverCalm(position: CGFloat) -> CGFloat {
        let t = position - position.rounded(.down)
        return 1 - smoothstep(min(t, 1 - t) / hoverSettle)
    }

    /// Whether app `index` answers to `hoveredCell`, judged on the page nearest to what is on
    /// screen at `position` (not the resting page, which jumps ahead when a wheel turn starts). An
    /// app cell lights its own app; the expand cell — or a cell with no app — lights the mini grid.
    static func isHovered(index: Int, position: CGFloat, hoveredCell: Int?, memberCount: Int) -> Bool {
        guard let hoveredCell else { return false }
        typealias M = DrawerCapsulePreviewMetrics
        let page = clampedPage(Int(position.rounded()), pageCount: pageCount(memberCount: memberCount))
        let slot = index - page * M.appSlots
        let appsOnPage = min(M.appSlots, max(0, memberCount - page * M.appSlots))
        if (0..<M.appSlots).contains(slot) { return hoveredCell == slot }
        return (M.appSlots..<M.limit).contains(slot) && hoveredCell >= appsOnPage
    }

    private static func smoothstep(_ x: CGFloat) -> CGFloat {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    static func pageCount(memberCount: Int) -> Int {
        let slots = DrawerCapsulePreviewMetrics.appSlots
        return max(1, (memberCount + slots - 1) / slots)
    }

    static func apps(page: Int, members: [String]) -> [String] {
        let start = page * DrawerCapsulePreviewMetrics.appSlots
        guard page >= 0, start < members.count else { return [] }
        return Array(members[start...].prefix(DrawerCapsulePreviewMetrics.appSlots))
    }

    static func more(page: Int, members: [String]) -> [String] {
        let start = (page + 1) * DrawerCapsulePreviewMetrics.appSlots
        guard page >= 0, start < members.count else { return [] }
        return Array(members[start...].prefix(DrawerCapsulePreviewMetrics.miniLimit))
    }

    static func clampedPage(_ page: Int, pageCount: Int) -> Int {
        min(max(0, page), max(0, pageCount - 1))
    }

    /// One gesture turns at most one page. The resting page is clamped first: the member list
    /// may have shrunk under it, and the turn starts from the page actually shown.
    static func settledPage(page: Int, drag: CGFloat, pageCount: Int) -> Int {
        let shown = clampedPage(page, pageCount: pageCount)
        guard abs(drag) > turnThreshold else { return shown }
        return clampedPage(shown + (drag > 0 ? 1 : -1), pageCount: pageCount)
    }

    /// The page a click lands on: the one nearest to what is on screen. While a trackpad gesture
    /// holds the capsule on the next page, that page — not the resting one — takes the click.
    static func hitPage(page: Int, drag: CGFloat, pageCount: Int) -> Int {
        let shown = clampedPage(page, pageCount: pageCount)
        return clampedPage(shown + Int(drag.rounded()), pageCount: pageCount)
    }

    /// Position in pages, with the travel beyond either end damped.
    static func displayedPosition(page: Int, drag: CGFloat, pageCount: Int) -> CGFloat {
        let last = CGFloat(max(0, pageCount - 1))
        let raw = CGFloat(page) + drag
        if raw < 0 { return raw * rubberBand }
        if raw > last { return last + (raw - last) * rubberBand }
        return raw
    }

    /// The pose of app `index` while the capsule is pulled past its last page, nil otherwise.
    /// Nothing arrives there and the apps hold their size for `leaveHold`, longer than the rubber
    /// band reaches, so the plain pose would not move at all. Instead each of the last page's apps
    /// takes exactly the pose the same cell shows when pulled as far before the first page: at
    /// both ends the apps gather together towards the mini grid. Not a mirror — mirrored, the apps
    /// spread apart towards the rim, which reads as a different gesture.
    static func endPullPose(index: Int, position: CGFloat, memberCount: Int) -> IconPose? {
        let last = pageCount(memberCount: memberCount) - 1
        let over = position - CGFloat(last)
        let slot = index - last * DrawerCapsulePreviewMetrics.appSlots
        guard over > 0, (0..<DrawerCapsulePreviewMetrics.appSlots).contains(slot) else { return nil }
        return pose(index: slot, position: -over)
    }
}

struct PanelScreenGeometry: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
    var safeAreaTop: CGFloat = 0

    /// The drawer's top cap still follows top system UI. On displays without a notch,
    /// this usually tracks visibleFrame.maxY and may change when the menu bar auto-hides.
    /// On notched displays, the safe-area cap can take over once the menu bar is hidden,
    /// so the same known edge can be smaller there than on external displays.
    var topUsableY: CGFloat {
        min(visibleFrame.maxY, frame.maxY - safeAreaTop)
    }
}

enum PanelGeometry {
    static let windowTitleTooltipScreenMargin: CGFloat = 8
    /// 阴影留白**不随档位缩放**：气泡的阴影 token 本身是固定的，跟着缩会动到定稿的观感。
    /// 视图侧和这里必须用同一个值（视图 `.padding(它)`，这里再减回去）。
    static let windowTitleTooltipShadowPadding: CGFloat = 8

    /// The bar and the drawer capsule to its right are centered as one group, the way the native
    /// Dock centers its whole row. Centering the bar alone leaves the set (gap + capsule) / 2 right
    /// of center; at the width cap the group keeps `outerMargin` on both sides.
    static func dockTargetFrame(
        contentWidth: CGFloat,
        on screen: PanelScreenGeometry,
        placement: DrawerPlacement = .right,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let capsuleSpace = metrics.capsuleGap + metrics.capsuleWidth
        let maxWidth = screen.frame.width - 2 * metrics.outerMargin - capsuleSpace
        let panelWidth = max(min(contentWidth, maxWidth), metrics.minimumDockWidth)
        
        let totalWidth = panelWidth + capsuleSpace
        let x = screen.frame.minX + (screen.frame.width - totalWidth) / 2
        
        let panelX = placement == .left ? x + capsuleSpace : x
        return CGRect(
            x: panelX - metrics.shadowPadding,
            y: screen.frame.minY + metrics.bottomGap - metrics.shadowPadding,
            width: panelWidth + metrics.shadowPadding * 2,
            height: metrics.windowHeight
        )
    }

    /// Plate width of the Full Width bar: the screen minus both side margins and the capsule slot.
    /// `DockStripView` stretches its content to it (flexible gaps around the apps zone).
    static func fullWidthPlateWidth(screenWidth: CGFloat, margin: CGFloat, metrics: PanelLayoutMetrics) -> CGFloat {
        max(0, screenWidth - 2 * max(0, margin) - (metrics.capsuleGap + metrics.capsuleWidth))
    }

    /// Computes target window frame for a specific island slot and layout mode.
    /// In `.windows` mode, a full-width plate inside the margins (Phase 11b).
    /// In `.centered` and split modes, computes per-island geometry via `IslandLayoutSolver`.
    static func islandTargetFrame(
        slot: Int,
        contentWidth: CGFloat,
        mode: BarLayoutMode,
        on screen: PanelScreenGeometry,
        placement: DrawerPlacement = .right,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        centeredWidth: CGFloat = 720,
        gap: CGFloat = 8,
        margin: CGFloat = 12,
        widgetLayout: WidgetLayout? = nil,
        tileStride: CGFloat? = nil,
        contentInset: CGFloat = IslandChrome.contentInset,
        controlCentreTrailing: Bool = false,
        enforceMinimumWidgetWidths: Bool = true,
        capsuleOwnerSlot: Int? = nil,
        wingConfig: DockWingsConfiguration = .default
    ) -> CGRect {
        switch mode {
        case .windows:
            // Owner 2026-11-25: no dead space in the bar at any item count. Full Width hugs its
            // content like every other mode — the plate is the content plus the chrome, centred in
            // the space the wings leave — instead of running edge to edge with the spare width
            // poured into section boundaries.
            let capsuleSpace = controlCentreTrailing ? 0 : metrics.capsuleGap + metrics.capsuleWidth
            var wingSpace = dockWingReserve(config: wingConfig, metrics: metrics)
            if capsuleSpace > 0, wingConfig.hasAnyActiveWing {
                if placement == .left { wingSpace.left += 2 * metrics.shadowPadding }
                else { wingSpace.right += 2 * metrics.shadowPadding }
            }
            let maxWidth = screen.frame.width - 2 * max(0, margin) - capsuleSpace
                - wingSpace.left - wingSpace.right
            let targetWidth = min(maxWidth, max(contentWidth, metrics.minimumDockWidth))
            let panelWidth = max(targetWidth, metrics.minimumDockWidth)
            let slack = max(0, screen.frame.width - 2 * max(0, margin) - capsuleSpace
                - wingSpace.left - wingSpace.right - panelWidth)
            let x = screen.frame.minX + max(0, margin) + wingSpace.left + slack / 2
            let panelX = placement == .left ? x + capsuleSpace : x
            return CGRect(
                x: panelX - metrics.shadowPadding,
                y: screen.frame.minY + metrics.bottomGap - metrics.shadowPadding,
                width: panelWidth + metrics.shadowPadding * 2,
                height: metrics.windowHeight
            )

        case .centered:
            let capsuleSpace = controlCentreTrailing ? 0 : metrics.capsuleGap + metrics.capsuleWidth
            // Dock II wings are separate panels parked *outside* the plate, so the plate has to hand
            // their width back before it is clamped to the screen. Without this a busy dock grows the
            // plate to the whole usable width, `wingPanelFrames` sees zero room on both sides and
            // `DockWingLadder` resolves both wings to `.hidden` — the feature disappears exactly when
            // the dock is full. The strip's own horizontal `ScrollView` absorbs the lost width.
            var wingSpace = dockWingReserve(config: wingConfig, metrics: metrics)
            // The capsule rides beside the plate and is drawn with the bar's shadow padding, so its
            // side needs that much more room back: measured on a real bar, a trailing wing lost one
            // ladder step to the capsule's unpadded edge.
            if capsuleSpace > 0, wingConfig.hasAnyActiveWing {
                if placement == .left {
                    wingSpace.left += 2 * metrics.shadowPadding
                } else {
                    wingSpace.right += 2 * metrics.shadowPadding
                }
            }
            let maxWidth = screen.frame.width - 2 * max(0, margin) - capsuleSpace
                - wingSpace.left - wingSpace.right
            let targetWidth = min(maxWidth, max(min(centeredWidth, maxWidth), contentWidth))
            let panelWidth = max(targetWidth, metrics.minimumDockWidth)
            let totalWidth = panelWidth + capsuleSpace
            // Centre the plate in what is left *after* each wing's park, so a side never has to
            // degrade just because the other wing is wider.
            let slack = max(0, screen.frame.width - 2 * max(0, margin) - capsuleSpace
                - wingSpace.left - wingSpace.right - panelWidth)
            let x = screen.frame.minX + max(0, margin) + wingSpace.left + slack / 2
            let panelX = placement == .left ? x + capsuleSpace : x
            return CGRect(
                x: panelX - metrics.shadowPadding,
                y: screen.frame.minY + metrics.bottomGap - metrics.shadowPadding,
                width: panelWidth + metrics.shadowPadding * 2,
                height: metrics.windowHeight
            )

        case .split3, .split4, .split5:
            // `tileStride` override = a rail's own pitch (`IslandChrome.railChipStride`): the bottom
            // bar's 54 pt stride would drop a chip the rail has room for (Phase 41b).
            let stride = tileStride ?? IslandLayoutSolver.tileStride(barHeight: metrics.panelHeight)
            let appCount = max(1, Int((contentWidth / stride).rounded()))
            let capsuleSpace = controlCentreTrailing ? 0 : metrics.capsuleGap + metrics.capsuleWidth
            
            // IslandLayoutSolver adds 24 to clusterWidth. 
            // We want appsWidth to be exactly (contentWidth + capsuleSpace).
            let exactClusterWidth = contentWidth + capsuleSpace - (CGFloat(appCount) * stride) - 24
            
            // The live caller passes the store's layout (Phase 11a, B9); the defaults read is the
            // fallback for callers without a store.
            let storedLayout = widgetLayout ?? Self.storedWidgetLayout()
            let fittedLayout = storedLayout.fitted(toBudget: WidgetLayout.widgetBudget(
                screenWidth: screen.frame.width, margin: margin, gap: gap, tileStride: stride,
                mode: mode, order: storedLayout.visibleOrder, barHeight: metrics.panelHeight))
            let widgetWidths = fittedLayout.solverWidths()
            
            let layout = IslandLayoutSolver.layout(
                screenWidth: screen.frame.width,
                mode: mode,
                widgetOrder: storedLayout.visibleOrder,
                widgetWidths: widgetWidths,
                tileStride: stride,
                appCount: appCount,
                weatherWidth: BarSection.weather.defaultWidgetWidth,
                clockWidth: BarSection.clock.defaultWidgetWidth, // Fixed default width for truncation
                clusterWidth: exactClusterWidth,
                gap: gap,
                margin: margin,
                barHeight: metrics.panelHeight,
                bottomMargin: metrics.bottomGap,
                centeredWidth: centeredWidth,
                screenOriginX: screen.frame.minX,
                screenMinY: screen.frame.minY,
                appsTrailingClearance: capsuleSpace,
                contentInset: contentInset,
                enforceMinimumWidgetWidths: enforceMinimumWidgetWidths
            )
            guard slot < layout.islands.count else {
                return dockTargetFrame(contentWidth: contentWidth, on: screen, placement: placement, metrics: metrics)
            }
            let island = layout.islands[slot]
            let isApps = island.sections.contains(.apps)
            // DP-4: the capsule rides with the Background Apps host island (the trailing one in a
            // split), so the island that gives up the room is that host, not the apps island.
            let ownerSlot = capsuleOwnerSlot
                ?? layout.islands.firstIndex { $0.sections.contains(.apps) }
            let ownsCapsule = slot == ownerSlot
            let currentCapsuleSpace = ownsCapsule ? capsuleSpace : 0
            
            #if DEBUG
            if !IslandLayoutSolver.validate(layout: layout, screenWidth: screen.frame.width,
                                            screenOriginX: screen.frame.minX, expectedBarHeight: metrics.panelHeight) {
                NSLog("KatiKati: island layout failed validation for %@", "\(mode)")
            }
            #endif
            // Only the apps island takes the dock minimum: a fixed island is exactly its solver
            // frame, or a narrow trailing island grows past the screen edge (Phase 11a, B3).
            // The capsule is its own panel in split modes, so every apps island hands its slot back:
            // subtracting it only on the owner island left the others with a capsule-sized dead
            // stretch at their trailing end (measured 95 pt on split3, 49 pt on split4).
            let reservedCapsuleSpace = isApps ? capsuleSpace : currentCapsuleSpace
            let panelWidth = isApps
                ? max(island.frame.width - reservedCapsuleSpace, metrics.minimumDockWidth)
                : max(island.frame.width - currentCapsuleSpace, 0)
            let panelX = (ownsCapsule && placement == .left) ? island.frame.minX + currentCapsuleSpace : island.frame.minX
            
            return CGRect(
                x: panelX - metrics.shadowPadding,
                y: island.frame.minY - metrics.shadowPadding,
                width: panelWidth + metrics.shadowPadding * 2,
                height: metrics.windowHeight
            )
        }
    }

    // MARK: Side rails (Phase 18b)

    /// Distance from the screen's top edge to the first usable point (menu bar / notch).
    static func railTopInset(on screen: PanelScreenGeometry) -> CGFloat {
        max(0, screen.frame.maxY - screen.topUsableY)
    }

    /// Horizontal room the Dock II wings need outside the plate, per side: the requested wing width
    /// at the bar's scale plus the gap to the plate. Pure, so the reserve can be tested without
    /// asking AppKit for a screen.
    struct WingReserve: Equatable {
        var left: CGFloat = 0
        var right: CGFloat = 0
    }

    static func dockWingReserve(
        config: DockWingsConfiguration,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> WingReserve {
        guard config.hasAnyActiveWing else { return WingReserve() }
        let scale = max(0.5, metrics.panelHeight / IslandChrome.nativeBarHeight)
        let gap = DockWingsConfiguration.clampedGap(config.gap) * scale
        var reserve = WingReserve()
        if config.left.preset.isAssigned {
            reserve.left = DockWingDimensions.scaledWidth(for: config.left.preset, size: config.left.size, scale: scale) + gap
        }
        if config.right.preset.isAssigned {
            reserve.right = DockWingDimensions.scaledWidth(for: config.right.preset, size: config.right.size, scale: scale) + gap
        }
        return reserve
    }

    static func railWingPlan(
        config: DockWingsConfiguration,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics,
        margin: CGFloat
    ) -> DockWingLayoutPlanner.VerticalWingPlan {
        let scale = max(0.5, metrics.panelHeight / IslandChrome.nativeBarHeight)
        let gap = DockWingsConfiguration.clampedGap(config.gap) * scale
        let baseLength = StripAxis.mainLength(placement: .left, screen: screen.frame, topInset: railTopInset(on: screen))
        let usableSpan = max(0, baseLength - 2 * max(0, margin))
        return DockWingLayoutPlanner.verticalReservations(
            config: config,
            availableSpan: usableSpan,
            gap: gap,
            scale: scale
        )
    }

    /// A rail solves as a bottom strip on a virtual screen as wide as the rail is long.
    static func railVirtualScreen(
        on screen: PanelScreenGeometry,
        placement: StripPlacement,
        topReserve: CGFloat = 0,
        bottomReserve: CGFloat = 0
    ) -> PanelScreenGeometry {
        let length = max(0, StripAxis.mainLength(placement: placement, screen: screen.frame, topInset: railTopInset(on: screen) + topReserve) - bottomReserve)
        let frame = CGRect(x: 0, y: 0, width: length, height: screen.frame.width)
        return PanelScreenGeometry(frame: frame, visibleFrame: frame, safeAreaTop: 0)
    }

    /// Maps a window frame solved on `railVirtualScreen` onto the rail's edge. The shadow padding is
    /// symmetric, so the plate is mapped and the padding re-applied around it.
    static func railWindowFrame(_ virtualWindow: CGRect, on screen: PanelScreenGeometry,
                                placement: StripPlacement, metrics: PanelLayoutMetrics,
                                topReserve: CGFloat = 0) -> CGRect {
        let plate = virtualWindow.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
        let mapped = StripAxis.map(plate, placement: placement, screen: screen.frame, topInset: railTopInset(on: screen) + topReserve)
        return mapped.insetBy(dx: -metrics.shadowPadding, dy: -metrics.shadowPadding)
    }

    /// Widgets as compact rail tiles (decision 1); the apps zone keeps its own measured length.
    /// - Parameter tileLength: DP-5 — the pitch-derived tile length (native scale) for a widget
    ///   section. Omitted, a rail keeps the fixed 40 pt tile; the utilities cluster keeps its own
    ///   slot count either way.
    static func railWidgetLayout(
        _ layout: WidgetLayout,
        visibleUtilityCount: Int = storedUtilitiesConfig().visibleUtilities.count,
        tileLength: CGFloat? = nil
    ) -> WidgetLayout {
        WidgetLayout(instances: layout.instances.map { inst in
            var copy = inst
            if inst.section != .apps {
                copy.exactWidth = inst.section.railTileLength(
                    barHeight: IslandChrome.nativeBarHeight,
                    visibleUtilityCount: visibleUtilityCount
                )
                if let tileLength, inst.section != .utilities {
                    copy.exactWidth = tileLength
                }
            }
            return copy
        })
    }

    /// Island window frame for any placement. `.bottom` is exactly `islandTargetFrame`; a rail solves
    /// the mode as itself (Phase 41a) on the virtual screen with rail tiles, and maps the result.
    /// `contentLength` is the measured main-axis length of this island's content.
    static func stripTargetFrame(
        slot: Int,
        contentLength: CGFloat,
        mode: BarLayoutMode,
        stripPlacement: StripPlacement,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        centeredWidth: CGFloat = 720,
        gap: CGFloat = 8,
        margin: CGFloat = 12,
        widgetLayout: WidgetLayout? = nil,
        controlCentreTrailing: Bool = false,
        wingConfig: DockWingsConfiguration = .default,
        visibleUtilityCount: Int? = nil
    ) -> CGRect {
        guard stripPlacement.isVertical else {
            return islandTargetFrame(slot: slot, contentWidth: contentLength, mode: mode, on: screen,
                                     placement: .right, metrics: metrics, centeredWidth: centeredWidth,
                                     gap: gap, margin: margin, widgetLayout: widgetLayout,
                                     controlCentreTrailing: controlCentreTrailing)
        }
        let wingPlan = railWingPlan(config: wingConfig, on: screen, metrics: metrics, margin: margin)
        let virtual = railVirtualScreen(on: screen, placement: stripPlacement,
                                        topReserve: wingPlan.topReserve, bottomReserve: wingPlan.bottomReserve)
        // DP-5: the rail's pitch is adaptive. `contentLength` is the measured chip run, so dividing
        // it by the natural stride gives the chip count the rail is trying to place; the plan then
        // shares the rail's usable length across that count, floors at the legibility minimum and
        // reports overflow rather than letting the last tile be cut.
        let naturalPitch = IslandChrome.railChipStride(barHeight: metrics.panelHeight)
        let chipCount = max(1, Int((contentLength / max(naturalPitch, 1)).rounded()))
        let railPlan = RailPitchPlan.resolve(usable: virtual.frame.width, count: chipCount,
                                             barHeight: metrics.panelHeight)
        let layout = railWidgetLayout(
            widgetLayout ?? storedWidgetLayout(),
            visibleUtilityCount: visibleUtilityCount ?? storedUtilitiesConfig().visibleUtilities.count,
            tileLength: RailPitchPlan.widgetTile(pitch: railPlan.pitch, barHeight: metrics.panelHeight)
        )
        let solved = islandTargetFrame(slot: slot, contentWidth: contentLength,
                                       mode: mode, on: virtual,
                                       placement: .right, metrics: metrics,
                                       centeredWidth: centeredWidth,
                                       gap: gap, margin: margin, widgetLayout: layout,
                                       tileStride: railPlan.pitch,
                                       contentInset: IslandChrome.railContentInset,
                                       enforceMinimumWidgetWidths: false)
        let mapped = railWindowFrame(solved, on: screen, placement: stripPlacement, metrics: metrics, topReserve: wingPlan.topReserve)
        // DP-5: the rail's plate is `tile + 2·inset`, not the bar's height. The virtual solve runs on
        // the bar's metrics (they carry the chip scale), so only the cross-axis size is rewritten here,
        // anchored to the screen edge the rail hugs.
        return railThicknessFrame(mapped,
                                  thickness: RailPitchPlan.thickness(barHeight: metrics.panelHeight),
                                  placement: stripPlacement,
                                  metrics: metrics)
    }

    /// Resizes a mapped rail window to the rail's own thickness on the cross axis, keeping the plate
    /// flush with the screen edge it hugs.
    static func railThicknessFrame(_ window: CGRect, thickness: CGFloat,
                                   placement: StripPlacement, metrics: PanelLayoutMetrics) -> CGRect {
        guard placement.isVertical else { return window }
        let plate = window.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
        guard abs(plate.width - thickness) > 0.001 else { return window }
        var resized = plate
        resized.size.width = thickness
        if placement == .right { resized.origin.x = plate.maxX - thickness }
        return resized.insetBy(dx: -metrics.shadowPadding, dy: -metrics.shadowPadding)
    }

    /// Length a rail's **apps** island fills: `0` (Phase 49, owner: "Hug content with balanced insets").
    /// Previously Phase 41b stretched the apps island across the full span between the fixed end islands,
    /// leaving a tall empty void below the last icon when apps didn't fill the screen height. Like the
    /// horizontal bar, the rail's apps island now hugs its measured content.
    static func railAppsFillLength(
        mode: BarLayoutMode,
        stripPlacement: StripPlacement,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        centeredWidth: CGFloat = 720,
        gap: CGFloat = 8,
        margin: CGFloat = 12,
        widgetLayout: WidgetLayout? = nil
    ) -> CGFloat {
        0
    }

    /// Capsule window for any placement: right of the bar on the bottom (honouring `drawerPlacement`),
    /// at the rail's lower end on a side.
    static func stripCapsuleTargetFrame(
        forDock dockFrame: CGRect,
        stripPlacement: StripPlacement,
        on screen: PanelScreenGeometry,
        drawerPlacement: DrawerPlacement,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        controlCentreTrailing: Bool = false
    ) -> CGRect {
        guard stripPlacement.isVertical else {
            return capsuleTargetFrame(forDock: dockFrame, on: screen, placement: drawerPlacement,
                                      metrics: metrics, controlCentreTrailing: controlCentreTrailing)
        }
        let plate = dockFrame.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
        let side = metrics.capsuleWidth
        let x = plate.midX - side / 2
        let rawY = plate.minY - metrics.capsuleGap - side
        let y = max(rawY, screen.frame.minY)
        return CGRect(x: x - metrics.shadowPadding, y: y - metrics.shadowPadding,
                      width: side + metrics.shadowPadding * 2, height: side + metrics.shadowPadding * 2)
    }

    static func storedWidgetLayout(_ defaults: UserDefaults = .standard) -> WidgetLayout {
        WidgetLayout.decode(defaults.data(forKey: WidgetLayout.defaultsKey))
            ?? WidgetLayout.migrating(legacyWidths: defaults.dictionary(forKey: "widgetWidths") as? [String: CGFloat] ?? [:])
    }

    static func storedUtilitiesConfig(_ defaults: UserDefaults = .standard) -> DockUtilitiesConfig {
        DockUtilitiesConfig.decode(defaults.data(forKey: DockUtilitiesConfig.defaultsKey)) ?? .default
    }

    /// Width the strip leaves empty for the capsule when the Control Centre disc takes the trailing
    /// end: the capsule's own side plus the gap on each side, so the two tiles read as neighbours.
    static func controlCentreHole(metrics: PanelLayoutMetrics) -> CGFloat {
        metrics.capsuleWidth + 2 * metrics.capsuleGap
    }

    static func capsuleTargetFrame(
        forDock dockFrame: CGRect,
        on screen: PanelScreenGeometry,
        placement: DrawerPlacement,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        controlCentreTrailing: Bool = false
    ) -> CGRect {
        let rawX: CGFloat
        if controlCentreTrailing {
            // One slot in from the plate's trailing end, centred in the hole the strip reserves
            // there: `inset + disc + gap + capsule`, measured from the plate's trailing edge.
            let scale = metrics.panelHeight / IslandChrome.nativeBarHeight
            let plate = dockFrame.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
            rawX = plate.maxX - IslandChrome.contentInset * scale
                - BarSection.widgets.defaultWidgetWidth * scale
                - metrics.capsuleGap - metrics.capsuleWidth
        } else {
            rawX = placement == .left
                ? dockFrame.minX + metrics.shadowPadding - metrics.capsuleGap - metrics.capsuleWidth
                : dockFrame.maxX - metrics.shadowPadding + metrics.capsuleGap
        }
        let rawY = dockFrame.minY + metrics.shadowPadding + (metrics.panelHeight - metrics.capsuleWidth) / 2
        let clampedX = min(max(rawX, screen.frame.minX), screen.frame.maxX - metrics.capsuleWidth)
        let clampedY = min(max(rawY, screen.frame.minY), screen.frame.maxY - metrics.capsuleWidth)
        return CGRect(
            x: clampedX - metrics.shadowPadding,
            y: clampedY - metrics.shadowPadding,
            width: metrics.capsuleWidth + metrics.shadowPadding * 2,
            height: metrics.capsuleWidth + metrics.shadowPadding * 2
        )
    }

    /// Frame of a floating widget-tile stack (Phase 5e/5g): anchored to the top-right (calendar) or top-left
    /// (weather) of the usable area,
    /// `outerMargin` in from the edge and below the menu bar, and **content-sized** — `contentHeight`
    /// is what the tiles measure, clamped so the window never runs under the taskbar. Pure.
    static func widgetPanelFrame(
        on screen: PanelScreenGeometry,
        layout: CalendarPanelLayout,
        side: WidgetPanelSide = .right,
        contentHeight: CGFloat,
        sideInset: CGFloat = 0,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let margin = metrics.outerMargin
        let visible = screen.visibleFrame
        // `sideInset` keeps the stack clear of an edge bar hugging the same side (7A-8).
        let inset = max(0, sideInset)
        let width = min(layout.width(forScreenWidth: screen.frame.width), max(0, visible.width - 2 * margin - inset))
        let top = screen.topUsableY - margin
        let bottom = max(screen.frame.minY, visible.minY) + metrics.bottomGap + metrics.panelHeight + margin
        let available = max(0, top - bottom)
        let height = min(max(0, contentHeight), available)
        let x = side == .right ? visible.maxX - margin - inset - width : visible.minX + margin + inset
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    /// Phase 56 W11: the full-screen Glance page — the whole usable area (below the menu bar/notch, above
    /// nothing else), so the bar and rail stay reachable only through Esc/close. Pure.
    static func fullScreenFrame(on screen: PanelScreenGeometry) -> CGRect {
        let v = screen.visibleFrame
        return CGRect(x: v.minX, y: v.minY, width: v.width, height: max(0, min(v.maxY, screen.topUsableY) - v.minY))
    }

    /// Height available to the tiles on this screen (same bounds as `widgetPanelFrame`).
    static func widgetPanelMaxHeight(on screen: PanelScreenGeometry, metrics: PanelLayoutMetrics = .tungstenEdge) -> CGFloat {
        widgetPanelFrame(on: screen, layout: .mac, contentHeight: .greatestFiniteMagnitude, metrics: metrics).height
    }

    // MARK: Edge bars (Phase 7A)

    /// Minimum gap/margin for edge bars (Appendix C).
    static let edgeBarMinimumSpacing: CGFloat = 0.5
    /// Edge bars default to hugging the bottom bar (Appendix C), unlike floating islands.
    static let edgeBarDefaultBottomGap: CGFloat = 2

    /// Popup (status popover etc.) for an edge-bar tile: opens **inward** (left of a right bar, right of a
    /// left bar), `gap` off the bar, vertically centered on `anchor`, clamped inside `visibleFrame`. Pure.
    static func edgeBarPopupFrame(
        side: EdgeSide,
        anchor: CGRect,
        size: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 8
    ) -> CGRect {
        let w = min(max(0, size.width), visibleFrame.width)
        let h = min(max(0, size.height), visibleFrame.height)
        let rawX = side == .right ? anchor.minX - gap - w : anchor.maxX + gap
        let x = min(max(rawX, visibleFrame.minX), visibleFrame.maxX - w)
        let rawY = anchor.midY - h / 2
        let y = min(max(rawY, visibleFrame.minY), visibleFrame.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Phase 16g: the Control Center side panel — flush to the dock's side, top-aligned under the menu
    /// bar, `margin` from the screen edges, stepped inward past a rail (`railInset`) on the same edge.
    /// Phase 16v: `anchor` picks the vertical placement (top = pre-anchor behavior); `bottomReserve`
    /// is the dock clearance the bottom anchor sits above. Both default to the old behavior.
    static func controlCenterFrame(side: EdgeSide, visibleFrame: CGRect, size: CGSize, railInset: CGFloat, margin: CGFloat = 12, bottomReserve: CGFloat = 0, anchor: ControlCenterAnchor = .top) -> CGRect {
        let x = side == .right ? visibleFrame.maxX - size.width - margin - railInset
                              : visibleFrame.minX + margin + railInset
        let y: CGFloat
        switch anchor {
        case .top:
            y = visibleFrame.maxY - size.height - margin
        case .center:
            y = visibleFrame.midY - size.height / 2
        case .bottom:
            y = visibleFrame.minY + margin + bottomReserve
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: Folder / shelf / Trash popup
    //
    // The popup window is the plate plus a transparent `StackPopupMetrics.panelMargin` border on
    // every side (the glass's own shadow lives there) and the arrow strip under the plate. These
    // functions speak in window frames; `folderPopupPlateFrame` converts back to what is visible.

    /// Bottom edge of the popup window for an anchor: the arrow's tip floats `tipGap` above the
    /// chip, the transparent border hangs below the tip.
    static func folderPopupDesiredBottomY(anchorVisibleRect: CGRect) -> CGFloat {
        anchorVisibleRect.maxY + StackPopupMetrics.tipGap - StackPopupMetrics.panelMargin
    }

    /// How close the popup's **plate** may come to the screen's left and right edges.
    struct StackPopupScreenMargins: Equatable {
        var left: CGFloat
        var right: CGFloat

        func interpolated(to other: StackPopupScreenMargins, progress: CGFloat) -> StackPopupScreenMargins {
            .init(left: left + (other.left - left) * progress, right: right + (other.right - right) * progress)
        }
    }

    /// Margins for an anchor: `screenMargin` (native), giving way down to `minimumScreenMargin`
    /// on the side the anchor hugs, so the arrow — never closer than `arrowInset` to the plate's
    /// side — still lands on that chip. They belong to the **anchor**, never to an interpolated
    /// centre: the switch tween interpolates them (`folderPopupScreenMargins(holding:)` → these).
    static func folderPopupScreenMargins(anchorCenterX: CGFloat, on screen: PanelScreenGeometry) -> StackPopupScreenMargins {
        let m = StackPopupMetrics.self
        func margin(_ distanceToEdge: CGFloat) -> CGFloat {
            min(m.screenMargin, max(m.minimumScreenMargin, distanceToEdge - m.arrowInset))
        }
        return .init(left: margin(anchorCenterX - screen.frame.minX), right: margin(screen.frame.maxX - anchorCenterX))
    }

    /// The margins a popup window already on screen satisfies — a tween's starting point, so its
    /// first tick reproduces the current frame instead of re-clamping it.
    static func folderPopupScreenMargins(holding panelFrame: CGRect, on screen: PanelScreenGeometry) -> StackPopupScreenMargins {
        let m = StackPopupMetrics.self
        let plate = folderPopupPlateFrame(panelFrame: panelFrame)
        func margin(_ distanceToEdge: CGFloat) -> CGFloat { min(m.screenMargin, max(0, distanceToEdge)) }
        return .init(left: margin(plate.minX - screen.frame.minX), right: margin(screen.frame.maxX - plate.maxX))
    }

    /// The single truth for anchoring and clamping: first frame, re-anchoring and every tick of
    /// the switch tween go through it. The plate stays `margins` inside the screen; the window
    /// itself may overhang the screen by its transparent border.
    static func folderPopupClampedOrigin(
        desiredCenterX: CGFloat,
        desiredBottomY: CGFloat,
        size: CGSize,
        margins: StackPopupScreenMargins,
        on screen: PanelScreenGeometry
    ) -> CGPoint {
        let m = StackPopupMetrics.self
        let minX = screen.frame.minX + margins.left - m.panelMargin
        let maxX = screen.frame.maxX - margins.right + m.panelMargin - size.width
        // Wider than the screen allows: centre it rather than favour one edge.
        let x = maxX >= minX ? min(max(desiredCenterX - size.width / 2, minX), maxX) : screen.frame.midX - size.width / 2
        return CGPoint(x: x, y: desiredBottomY)
    }

    /// Phase 18d: a popup beside a side rail opens **inward** (right of a left rail, left of a right
    /// rail) `tipGap` off the anchor, vertically centred on it and clamped between the screen bottom
    /// and `topUsableY`. `size` and the result are window frames; `border` is the transparent margin
    /// around the visible plate (the gap is measured plate to anchor).
    static func railPopupFrame(
        anchorVisibleRect anchor: CGRect,
        size: CGSize,
        stripPlacement: StripPlacement,
        on screen: PanelScreenGeometry,
        border: CGFloat,
        gap: CGFloat = StackPopupMetrics.tipGap
    ) -> CGRect {
        let floor = screen.frame.minY - border
        let ceiling = screen.topUsableY + border
        let height = min(size.height, max(0, ceiling - floor))
        let x = stripPlacement == .right
            ? anchor.minX - gap + border - size.width
            : anchor.maxX + gap - border
        let rawY = anchor.midY - height / 2
        let y = min(max(rawY, floor), ceiling - height)
        return CGRect(x: x, y: y, width: size.width, height: height)
    }

    /// The popup window's frame: centred on the anchor chip, clamped into the screen, growing
    /// upward only and capped where the plate would cross `topUsableY`. `size` is the whole window.
    /// On a side rail it opens beside the rail instead (`railPopupFrame`).
    static func folderPopupTargetFrame(
        anchorVisibleRect: CGRect,
        size: CGSize,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        stripPlacement: StripPlacement = .bottom
    ) -> CGRect {
        if stripPlacement.isVertical {
            return railPopupFrame(anchorVisibleRect: anchorVisibleRect, size: size, stripPlacement: stripPlacement,
                                  on: screen, border: StackPopupMetrics.panelMargin)
        }
        let origin = folderPopupClampedOrigin(
            desiredCenterX: anchorVisibleRect.midX,
            desiredBottomY: folderPopupDesiredBottomY(anchorVisibleRect: anchorVisibleRect),
            size: size,
            margins: folderPopupScreenMargins(anchorCenterX: anchorVisibleRect.midX, on: screen),
            on: screen)
        let top = screen.topUsableY + StackPopupMetrics.panelMargin
        let height = min(size.height, max(metrics.minimumDrawerExtent, top - origin.y))
        return CGRect(x: origin.x, y: origin.y, width: size.width, height: height)
    }

    /// Height the plate may take above the anchor, leaving `stackPopupTopGap` under the menu bar;
    /// feeds `StackGridLayout.limits`, which takes a status line's height off it when there is one.
    static func stackPopupAvailablePlateHeight(anchorVisibleRect: CGRect, on screen: PanelScreenGeometry,
                                               stripPlacement: StripPlacement = .bottom) -> CGFloat {
        // Beside a rail the plate may use the whole usable height (it centres on the anchor).
        if stripPlacement.isVertical {
            return screen.topUsableY - stackPopupTopGap - (screen.frame.minY + stackPopupTopGap)
        }
        let plateBottom = anchorVisibleRect.maxY + StackPopupMetrics.tipGap + StackPopupMetrics.arrowHeight
        return screen.topUsableY - stackPopupTopGap - plateBottom
    }

    static let stackPopupTopGap: CGFloat = 8

    /// Placement geometry for Mid-Dock Utilities (`Dictionary`, `Terminal`, `Screenshots`, `Clipboard`,
    /// `Downloads`, `Drawer`, `Trash`): supports icon-anchored (`v` arrow), centered bottom float, and screen center float.
    struct UtilityPanelLayout: Equatable {
        let frame: CGRect
        let arrowOffsetFromCenter: CGFloat
        let showsArrow: Bool
    }

    static func utilityPanelFrame(
        plateSize: CGSize,
        anchorVisibleRect: CGRect?,
        placement: UtilityPopoverPlacement,
        flyoutPreset: UtilityFlyoutPreset,
        stripPlacement: StripPlacement = .bottom,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> UtilityPanelLayout {
        let m = StackPopupMetrics.self
        let effectivePlacement = (flyoutPreset == .cleanFloat && placement == .anchored) ? .bottomFloat : placement
        let showsArrow = flyoutPreset.resolvesArrowVisible(for: effectivePlacement)
        let arrowW: CGFloat = (showsArrow && stripPlacement.isVertical) ? m.arrowHeight : 0
        let arrowH: CGFloat = (showsArrow && !stripPlacement.isVertical) ? m.arrowHeight : 0
        let totalSize = CGSize(
            width: plateSize.width + arrowW + m.panelMargin * 2,
            height: plateSize.height + arrowH + m.panelMargin * 2
        )

        if effectivePlacement == .anchored, let anchor = anchorVisibleRect, anchor != .zero {
            let target = folderPopupTargetFrame(
                anchorVisibleRect: anchor,
                size: totalSize,
                on: screen,
                metrics: metrics,
                stripPlacement: stripPlacement
            )
            let arrowOffset = showsArrow
                ? (stripPlacement.isVertical ? (target.midY - anchor.midY) : (anchor.midX - target.midX))
                : 0
            return UtilityPanelLayout(frame: target, arrowOffsetFromCenter: arrowOffset, showsArrow: showsArrow)
        }

        let vf = screen.visibleFrame
        let minPlateX = vf.minX + m.screenMargin
        let maxPlateX = max(minPlateX, vf.maxX - m.screenMargin - plateSize.width)
        let plateX = min(max(vf.midX - plateSize.width / 2, minPlateX), maxPlateX)
        let maxPlateY = max(vf.minY + m.screenMargin, vf.maxY - m.screenMargin - plateSize.height)
        let rawY: CGFloat = (effectivePlacement == .centerFloat)
            ? (vf.midY - plateSize.height / 2)
            : (vf.minY + 80)
        let plateY = min(max(rawY, vf.minY + m.screenMargin), maxPlateY)
        let windowFrame = CGRect(
            x: plateX - m.panelMargin,
            y: plateY - m.panelMargin,
            width: plateSize.width + m.panelMargin * 2,
            height: plateSize.height + m.panelMargin * 2
        )
        return UtilityPanelLayout(frame: windowFrame, arrowOffsetFromCenter: 0, showsArrow: false)
    }

    /// The visible part of the popup window — plate plus arrow strip. Hit tests use this, never
    /// the window frame: the border is 40pt of nothing.
    static func folderPopupPlateFrame(panelFrame: CGRect) -> CGRect {
        panelFrame.insetBy(dx: StackPopupMetrics.panelMargin, dy: StackPopupMetrics.panelMargin)
    }

    /// Window-title tooltip panel frame. The panel includes transparent padding for its SwiftUI
    /// shadow, while the visible bubble stays 8pt above the pill and 8pt inside the screen edges.
    /// `tipGap` = 气泡**尖端**到锚点顶边的距离，随档位缩放，由调用方从
    /// `WindowTitleTooltipStyle.tipGap` 传进来——系数只在样式那一处算，这里不再算第二遍。
    static func windowTitleTooltipTargetFrame(
        anchorVisibleRect: CGRect,
        size: CGSize,
        tipGap: CGFloat,
        on screen: PanelScreenGeometry,
        stripPlacement: StripPlacement = .bottom
    ) -> CGRect {
        if stripPlacement.isVertical {
            return railPopupFrame(anchorVisibleRect: anchorVisibleRect, size: size, stripPlacement: stripPlacement,
                                  on: screen, border: windowTitleTooltipShadowPadding, gap: tipGap)
        }
        let inset = windowTitleTooltipShadowPadding
        let visibleWidth = max(0, size.width - 2 * inset)
        let visibleHeight = max(0, size.height - 2 * inset)
        let minVisibleX = screen.frame.minX + windowTitleTooltipScreenMargin
        let maxVisibleX = screen.frame.maxX - windowTitleTooltipScreenMargin - visibleWidth
        let desiredVisibleX = anchorVisibleRect.midX - visibleWidth / 2
        let visibleX = min(max(desiredVisibleX, minVisibleX), maxVisibleX)
        let desiredVisibleY = anchorVisibleRect.maxY + tipGap
        let maxVisibleY = screen.topUsableY - visibleHeight
        let visibleY = min(desiredVisibleY, maxVisibleY)

        return CGRect(
            x: visibleX - inset,
            y: visibleY - inset,
            width: size.width,
            height: size.height
        )
    }

    /// The drawer is a stack popup anchored on its capsule: this is the capsule's visible rect,
    /// the anchor every `folderPopup…` function takes.
    static func drawerAnchorVisibleRect(
        forCapsule capsuleFrame: CGRect,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        capsuleFrame.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
    }

    static func drawerTargetFrame(
        forCapsule capsuleFrame: CGRect,
        size: CGSize,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        stripPlacement: StripPlacement = .bottom
    ) -> CGRect {
        folderPopupTargetFrame(
            anchorVisibleRect: drawerAnchorVisibleRect(forCapsule: capsuleFrame, metrics: metrics),
            size: size, on: screen, metrics: metrics, stripPlacement: stripPlacement)
    }

    /// Rows and columns the drawer's grid may take above its capsule on this screen.
    static func drawerGridLimits(
        forCapsule capsuleFrame: CGRect,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        stripPlacement: StripPlacement = .bottom
    ) -> StackGridLayout.Limits {
        StackGridLayout.drawerLimits(
            screenSize: screen.frame.size,
            availablePlateHeight: stackPopupAvailablePlateHeight(
                anchorVisibleRect: drawerAnchorVisibleRect(forCapsule: capsuleFrame, metrics: metrics), on: screen,
                stripPlacement: stripPlacement))
    }

    /// The pointer's lower bound for "inside the drawer body" while dragging a strip chip: the
    /// capsule's top, i.e. the bar's top edge. `plate` is `folderPopupPlateFrame` of the drawer.
    static func drawerBodyFloorY(plate: CGRect) -> CGFloat {
        plate.minY - StackPopupMetrics.tipGap
    }

    /// Pure frame solver for the Dock II left and right wing panels flanking `dockFrame` (and clearing
    /// `capsuleFrame` when present). All returned frames include `metrics.shadowPadding` on every edge.
    struct DockWingPanelLayout: Equatable, Sendable {
        var leftFrame: CGRect?
        var rightFrame: CGRect?
        var leftSize: WidgetSize
        var rightSize: WidgetSize
        /// Slice DP-6: the resolved rung per side. `.hidden` means the strip must not reserve room for it.
        var leftStep: DockWingLadder.Step = .hidden
        var rightStep: DockWingLadder.Step = .hidden
    }

    static func wingPanelFrames(
        dockFrame: CGRect,
        capsuleFrame: CGRect,
        config: DockWingsConfiguration,
        stripPlacement: StripPlacement,
        drawerPlacement: DrawerPlacement,
        controlCentreTrailing: Bool,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        margin: CGFloat = 12,
        isSplit: Bool = false
    ) -> DockWingPanelLayout {
        guard config.hasAnyActiveWing else {
            return DockWingPanelLayout(leftFrame: nil, rightFrame: nil,
                                       leftSize: config.left.size, rightSize: config.right.size)
        }

        let scale = max(0.5, metrics.panelHeight / IslandChrome.nativeBarHeight)
        let gap = DockWingsConfiguration.clampedGap(config.gap) * scale
        let pad = metrics.shadowPadding
        let dockPlate = dockFrame.insetBy(dx: pad, dy: pad)
        let capsulePlate = capsuleFrame != .zero ? capsuleFrame.insetBy(dx: pad, dy: pad) : .zero

        if stripPlacement.isVertical {
            let bottomAnchorY = (capsulePlate != .zero && capsulePlate.minY < dockPlate.minY)
                ? capsulePlate.minY : dockPlate.minY
            let plan = railWingPlan(config: config, on: screen, metrics: metrics, margin: margin)
            let maxAbove = isSplit
                ? max(0, plan.topReserve - gap)
                : max(0, screen.topUsableY - margin - (dockPlate.maxY + gap))
            let maxBelow = isSplit
                ? max(0, plan.bottomReserve - gap)
                : max(0, (bottomAnchorY - gap) - (screen.frame.minY + margin))
            let resolved = DockWingLayoutPlanner.resolveVerticalSizes(
                config: config,
                availableTop: maxAbove,
                availableBottom: maxBelow,
                scale: scale
            )
            // Keep vertical caps aligned flush to the rail's thickness and X position. The rail plate is
            // `RailPitchPlan.thickness` (48 at native), not `metrics.panelHeight`, so the caps must use the
            // same rule and hug the screen edge the rail hugs instead of its old raw inner edge.
            let plateWidth = RailPitchPlan.thickness(barHeight: metrics.panelHeight)
            let railX = stripPlacement == .left ? dockPlate.minX : dockPlate.maxX - plateWidth
            let minWingH = 36 * scale

            var leftFrame: CGRect?
            if config.left.preset.isAssigned, maxAbove >= minWingH {
                let desiredH = DockWingDimensions.scaledVerticalHeight(for: config.left.preset, size: resolved.left, scale: scale)
                let h = min(desiredH, maxAbove)
                let y = isSplit ? (screen.topUsableY - margin - h) : (dockPlate.maxY + gap)
                leftFrame = CGRect(x: railX - pad, y: y - pad,
                                   width: plateWidth + 2 * pad, height: h + 2 * pad)
            }

            var rightFrame: CGRect?
            if config.right.preset.isAssigned, maxBelow >= minWingH {
                let desiredH = DockWingDimensions.scaledVerticalHeight(for: config.right.preset, size: resolved.right, scale: scale)
                let h = min(desiredH, maxBelow)
                let y = isSplit ? (screen.frame.minY + margin) : (bottomAnchorY - gap - h)
                rightFrame = CGRect(x: railX - pad, y: y - pad,
                                    width: plateWidth + 2 * pad, height: h + 2 * pad)
            }

            return DockWingPanelLayout(leftFrame: leftFrame, rightFrame: rightFrame,
                                       leftSize: resolved.left, rightSize: resolved.right)
        }

        let leftAnchorMaxX = (capsulePlate != .zero && capsulePlate.minX < dockPlate.minX && !controlCentreTrailing)
            ? capsulePlate.minX : dockPlate.minX
        let rightAnchorMinX = (capsulePlate != .zero && capsulePlate.maxX > dockPlate.maxX)
            ? capsulePlate.maxX : dockPlate.maxX

        let leftAvailable = max(0, leftAnchorMaxX - (screen.frame.minX + margin) - gap)
        let rightAvailable = max(0, (screen.frame.maxX - margin) - (rightAnchorMinX + gap))
        // Slice DP-6: each side gets its own budget and walks the explicit L → M → S → icon pillar → hidden
        // ladder; the two sides never pool room, so one wing can no longer consume the other's span.
        let ladder = DockWingLadder.resolve(
            config: config,
            availableLeft: leftAvailable,
            availableRight: rightAvailable,
            scale: scale
        )
        let resolved = DockWingLayoutPlanner.ResolvedSizes(
            left: ladder.left.size ?? .small, right: ladder.right.size ?? .small)

        // No margin clamp is needed here: `DockWingLadder.step` only returns a visible rung whose width
        // fits that side's own measured span, and the span already stops `gap` short of the margin, so
        // the frame lands on or inside the margin by construction. Measured on the live full-width bar,
        // the offset that once looked like an over-reserve was the island margin itself.
        var leftFrame: CGRect?
        if config.left.preset.isAssigned, ladder.left.isVisible {
            let w = DockWingLadder.width(of: ladder.left, preset: config.left.preset, scale: scale)
            let x = leftAnchorMaxX - gap - w
            leftFrame = CGRect(x: x - pad, y: dockFrame.minY,
                               width: w + 2 * pad, height: metrics.windowHeight)
        }

        var rightFrame: CGRect?
        if config.right.preset.isAssigned, ladder.right.isVisible {
            let w = DockWingLadder.width(of: ladder.right, preset: config.right.preset, scale: scale)
            let x = rightAnchorMinX + gap
            rightFrame = CGRect(x: x - pad, y: dockFrame.minY,
                                width: w + 2 * pad, height: metrics.windowHeight)
        }

        return DockWingPanelLayout(leftFrame: leftFrame, rightFrame: rightFrame,
                                   leftSize: resolved.left, rightSize: resolved.right,
                                   leftStep: ladder.left, rightStep: ladder.right)
    }

    /// Pure target frame for the torn-off Floating Widget Stack panel (bottom-left screen coordinates,
    /// including `metrics.shadowPadding` on every edge). Uses `customOrigin` when user-dragged, or
    /// anchors to the right flank / right wing above the dock otherwise, automatically dodging any active
    /// `avoidRect` (such as an open Drawer or Shelf popup) and clamped within `screen.visibleFrame`.
    static func floatingWidgetStackFrame(
        size: CGSize,
        dockFrame: CGRect,
        customOrigin: CGPoint?,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        margin: CGFloat = 12,
        rightFlankFrame: CGRect? = nil,
        avoidRect: CGRect? = nil
    ) -> CGRect {
        let pad = metrics.shadowPadding
        let plateW = max(160, size.width)
        let plateH = max(60, size.height)
        let dockPlate = dockFrame.insetBy(dx: pad, dy: pad)
        let anchorPlate = rightFlankFrame.map { $0.insetBy(dx: pad, dy: pad) } ?? dockPlate

        let defaultX = anchorPlate.maxX - plateW
        var rawPlateX = customOrigin?.x ?? defaultX
        var rawPlateY = customOrigin?.y ?? (dockPlate.maxY + 14)

        let minX = screen.visibleFrame.minX + margin
        let maxX = max(minX, screen.visibleFrame.maxX - margin - plateW)
        let minY = screen.visibleFrame.minY + margin
        let maxY = max(minY, screen.topUsableY - margin - plateH)

        var clampedX = min(max(rawPlateX, minX), maxX)
        var clampedY = min(max(rawPlateY, minY), maxY)

        if let avoid = avoidRect {
            let avoidPlate = avoid.insetBy(dx: pad, dy: pad)
            let candidate = CGRect(x: clampedX, y: clampedY, width: plateW, height: plateH)
            if candidate.intersects(avoidPlate) {
                let rightSlideX = avoidPlate.maxX + 12
                let leftSlideX = avoidPlate.minX - 12 - plateW
                let upSlideY = avoidPlate.maxY + 12
                if rightSlideX <= maxX {
                    clampedX = rightSlideX
                } else if leftSlideX >= minX {
                    clampedX = leftSlideX
                } else if upSlideY <= maxY {
                    clampedY = upSlideY
                }
            }
        }

        return CGRect(
            x: clampedX - pad,
            y: clampedY - pad,
            width: plateW + 2 * pad,
            height: plateH + 2 * pad
        )
    }
}
