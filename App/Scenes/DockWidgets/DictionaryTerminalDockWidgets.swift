import SwiftUI

/// Modern macOS Sequoia-style squircle utility badge shared across Mid-Dock Utilities tiles.
/// Sized at `36.5pt` inside the `40pt` Dock slot so Drawer, Screenshots, Clipboard, Dictionary,
/// and Terminal match the height and tight ~2.5pt visual gap of Downloads and Trash.
struct ModernUtilitySquircleIcon: View {
    let symbol: String?
    var monogram: String? = nil
    let gradient: [Color]
    let tint: Color
    var badgeCount: Int = 0
    var size: CGFloat = 36.5
    var dockScale: CGFloat = 1
    var isRail: Bool = false
    var label: LocalizedStringKey
    let onTap: () -> Void

    @State private var isHovered = false

    private var renderedArtSize: CGFloat { (isRail ? 28 : size) * dockScale }
    private var slotSize: CGSize {
        if isRail {
            let side = ChipPillMetrics.cardWidth * dockScale
            return CGSize(width: side, height: side)
        }
        return CGSize(
            width: ChipPillMetrics.cardWidth * dockScale,
            height: ChipPillMetrics.cardFrameHeight(dockScale, onRail: false)
        )
    }

    var body: some View {
        let art = renderedArtSize
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: art * 0.22, style: .continuous)
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: art * 0.22, style: .continuous)
                            .strokeBorder(Color.white.opacity(isHovered ? 0.34 : 0.18), lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)

                if let monogram {
                    Text(verbatim: monogram)
                        .font(.system(size: art * 0.43, weight: .bold, design: .serif))
                        .foregroundStyle(tint)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: art * 0.45, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: art, height: art)

            if badgeCount > 0 {
                Text(verbatim: "\(min(badgeCount, 99))")
                    .font(.system(size: max(8, 8.5 * dockScale), weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4 * dockScale).padding(.vertical, 1 * dockScale)
                    .background(Capsule().fill(Color.accentColor))
                    .offset(x: 2 * dockScale, y: -2 * dockScale)
            }
        }
        .frame(width: slotSize.width, height: slotSize.height)
        .scaleEffect(isHovered ? 1.06 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.isButton)
    }
}

struct DictionaryDockChip: View {
    var dockScale: CGFloat = 1
    let onOpen: () -> Void
    var body: some View {
        ModernUtilitySquircleIcon(
            symbol: nil,
            monogram: "Aa",
            gradient: [Color(red: 0.34, green: 0.36, blue: 0.92), Color(red: 0.19, green: 0.21, blue: 0.64)],
            tint: .white,
            dockScale: dockScale,
            label: "Define…",
            onTap: onOpen
        )
    }
}

struct TerminalDockChip: View {
    var dockScale: CGFloat = 1
    let onOpen: () -> Void
    var body: some View {
        ModernUtilitySquircleIcon(
            symbol: nil,
            monogram: ">_",
            gradient: [Color(red: 0.13, green: 0.16, blue: 0.19), Color(red: 0.06, green: 0.08, blue: 0.10)],
            tint: Color(red: 0.28, green: 0.92, blue: 0.58),
            dockScale: dockScale,
            label: "Terminal",
            onTap: onOpen
        )
    }
}

struct ScreenshotsDockChip: View {
    var count: Int = 0
    var dockScale: CGFloat = 1
    var isRail: Bool = false
    let onTap: () -> Void
    var body: some View {
        ModernUtilitySquircleIcon(
            symbol: "camera.viewfinder",
            gradient: [Color(red: 0.16, green: 0.52, blue: 0.88), Color(red: 0.10, green: 0.28, blue: 0.62)],
            tint: .white,
            badgeCount: count,
            dockScale: dockScale,
            isRail: isRail,
            label: "Screenshots",
            onTap: onTap
        )
    }
}

struct ClipboardUtilityDockChip: View {
    var count: Int = 0
    var dockScale: CGFloat = 1
    var isRail: Bool = false
    let onTap: () -> Void
    var body: some View {
        ModernUtilitySquircleIcon(
            symbol: "doc.on.clipboard.fill",
            gradient: [Color(red: 0.24, green: 0.26, blue: 0.32), Color(red: 0.13, green: 0.14, blue: 0.18)],
            tint: Color(red: 0.45, green: 0.78, blue: 1.0),
            badgeCount: count,
            dockScale: dockScale,
            isRail: isRail,
            label: "Clipboard",
            onTap: onTap
        )
    }
}

struct RailDictionaryTile: View {
    var dockScale: CGFloat = 1
    var onOpen: () -> Void = {}
    var body: some View {
        ModernUtilitySquircleIcon(
            symbol: nil,
            monogram: "Aa",
            gradient: [Color(red: 0.34, green: 0.36, blue: 0.92), Color(red: 0.19, green: 0.21, blue: 0.64)],
            tint: .white,
            dockScale: dockScale,
            isRail: true,
            label: "Dictionary",
            onTap: onOpen
        )
    }
}

struct RailTerminalTile: View {
    var dockScale: CGFloat = 1
    var onOpen: () -> Void = {}
    var body: some View {
        ModernUtilitySquircleIcon(
            symbol: nil,
            monogram: ">_",
            gradient: [Color(red: 0.13, green: 0.16, blue: 0.19), Color(red: 0.06, green: 0.08, blue: 0.10)],
            tint: Color(red: 0.28, green: 0.92, blue: 0.58),
            dockScale: dockScale,
            isRail: true,
            label: "Terminal",
            onTap: onOpen
        )
    }
}

/// Self-contained utility buttons with isolated flyout popovers for Screenshots & Clipboard.
struct DockScreenshotsUtilityButton: View {
    var dockScale: CGFloat = 1
    var isRail: Bool = false
    var onAnchoredTap: (() -> Void)? = nil
    @ObservedObject private var controller = TendederoClotheslineController.shared
    @Environment(\.dockPopoverEdge) private var popoverEdge
    @State private var showFlyout = false

    private var unreadCount: Int {
        controller.store.items.filter {
            if case .screenshot = $0.kind { return $0.isUnread }
            return false
        }.count
    }

    var body: some View {
        ScreenshotsDockChip(count: unreadCount, dockScale: dockScale, isRail: isRail) {
            if let onAnchoredTap {
                onAnchoredTap()
            } else {
                showFlyout.toggle()
            }
        }
        .popover(isPresented: $showFlyout, arrowEdge: popoverEdge) {
            DockScreenshotsFlyoutView()
        }
        .onAppear { controller.start() }
    }
}

struct DockClipboardUtilityButton: View {
    var dockScale: CGFloat = 1
    var isRail: Bool = false
    var onAnchoredTap: (() -> Void)? = nil
    @ObservedObject private var monitor = ProductivityServices.shared.clipboard
    @Environment(\.dockPopoverEdge) private var popoverEdge
    @State private var showFlyout = false

    var body: some View {
        ClipboardUtilityDockChip(count: min(monitor.history.entries.count, 99), dockScale: dockScale, isRail: isRail) {
            if let onAnchoredTap {
                onAnchoredTap()
            } else {
                showFlyout.toggle()
            }
        }
        .popover(isPresented: $showFlyout, arrowEdge: popoverEdge) {
            DockClipboardStackFlyoutView()
        }
    }
}

// MARK: - AI Dock Widget & Popover

enum AIDockPresentation {
    struct Summary {
        let icon: String
        let title: String
        let detail: String
        let tint: Color
        let isUrgent: Bool
        let isBloated: Bool
        let scrubLevel: Double?
        let pendingRequest: AgentApprovalRequest?
    }

    @MainActor
    static func resolve(usage: AgentUsageService, approvals: ClaudeApprovalService, timeTravel: SurfaceTimeTravelCoordinator) -> Summary {
        if let preview = timeTravel.activePreview {
            return Summary(icon: preview.entry.icon, title: "\(preview.entry.title) (\(preview.index)/\(preview.total))",
                           detail: preview.entry.subtitle ?? "Time Travel", tint: .cyan, isUrgent: false,
                           isBloated: false, scrubLevel: Double(preview.index) / Double(max(1, preview.total)), pendingRequest: nil)
        }
        if let req = approvals.requests.first {
            return Summary(icon: req.provider.symbol, title: req.toolName, detail: req.provider.displayName,
                           tint: .orange, isUrgent: true, isBloated: false, scrubLevel: nil, pendingRequest: req)
        }
        let overhead = LoadoutConfigCodec.contextOverhead(items: usage.loadoutItems)
        if let active = usage.snapshot.activeTurn, active.isActive {
            return Summary(icon: active.provider.symbol, title: active.activeTool?.summary ?? active.model,
                           detail: "\(active.provider.displayName) · \(usage.snapshot.formattedTodayCost)", tint: .green,
                           isUrgent: false, isBloated: overhead.isBloated, scrubLevel: nil, pendingRequest: nil)
        }
        let bloated = overhead.isBloated && timeTravel.suggestionBackoff.shouldSuggest(ruleKey: "sixthSense.mcpBloat")
        let tokLabel = overhead.totalTokens > 0 ? String(format: "~%.0fk", Double(overhead.totalTokens) / 1000.0) : usage.activeProfile.title
        return Summary(icon: bloated ? "exclamationmark.triangle.fill" : "sparkles", title: usage.snapshot.formattedTodayCost,
                       detail: bloated ? String(format: "Ctx %.0f%% · Lean?", overhead.percent) : tokLabel,
                       tint: bloated ? .orange : .cyan, isUrgent: bloated, isBloated: bloated, scrubLevel: nil, pendingRequest: nil)
    }
}

/// Dock strip chip for AI: morphs across Time Travel scrub, approvals, active agent heartbeat, bloat warnings, and Spend/Loadout.
struct AIDockChip: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockPopoverEdge) private var edge
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var approvals = ClaudeApprovalService.shared
    @ObservedObject private var timeTravel = SurfaceTimeTravelCoordinator.shared
    @State private var showPopover = false

    var body: some View {
        let state = AIDockPresentation.resolve(usage: usage, approvals: approvals, timeTravel: timeTravel)
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: state.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(state.tint)
                if state.isUrgent || state.tint == .green {
                    Circle().fill(state.tint).frame(width: 5, height: 5).offset(x: 2, y: -2)
                }
            }.frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: state.title).font(.system(size: 11.5, weight: .semibold, design: .rounded)).lineLimit(1)
                if size != .small { Text(verbatim: state.detail).dockCaption().lineLimit(1) }
            }.layoutPriority(1)

            if size == .large, let req = state.pendingRequest {
                HStack(spacing: 3) {
                    Button { approvals.decide(req, .allow) } label: {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white).padding(4).background(Circle().fill(Color.green))
                    }.buttonStyle(.plain)
                    Button { approvals.decide(req, .deny) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white).padding(4).background(Circle().fill(Color.red.opacity(0.85)))
                    }.buttonStyle(.plain)
                }
            } else if size == .large, state.isBloated {
                Button {
                    usage.applyLoadoutProfile(.leanCoding); timeTravel.acceptSuggestion(ruleKey: "sixthSense.mcpBloat")
                } label: {
                    Text(verbatim: "Lean").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.orange.opacity(0.18)))
                }.buttonStyle(.plain)
            }
        }
        .frame(maxHeight: .infinity)
        .dockWidgetChip()
        .dockHoverPreview { AIDockPopoverView() }
        .onTapGesture { showPopover.toggle() }
        .popover(isPresented: $showPopover, arrowEdge: edge) { AIDockPopoverView() }
        .onAppear { usage.startMonitoring() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("AI"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Vertical rail tile for AI usage, heartbeat, and approvals.
struct RailAITile: View {
    @Environment(\.dockPopoverEdge) private var edge
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var approvals = ClaudeApprovalService.shared
    @ObservedObject private var timeTravel = SurfaceTimeTravelCoordinator.shared
    @State private var showPopover = false

    var body: some View {
        let state = AIDockPresentation.resolve(usage: usage, approvals: approvals, timeTravel: timeTravel)
        ZStack(alignment: .topTrailing) {
            Image(systemName: state.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(state.tint)
            if state.isUrgent || state.tint == .green { Circle().fill(state.tint).frame(width: 6, height: 6).offset(x: 3, y: -3) }
        }
        .frame(width: 28, height: 28).dockWidgetRailTile()
        .dockHoverPreview { AIDockPopoverView() }
        .onTapGesture { showPopover.toggle() }
        .popover(isPresented: $showPopover, arrowEdge: edge) { AIDockPopoverView() }
        .onAppear { usage.startMonitoring() }
        .accessibilityLabel(Text("AI"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Interactive Dock AI popover: inline approval card, dismissible Sixth-Sense suggestion, and Spend + Loadout hub.
struct AIDockPopoverView: View {
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var approvals = ClaudeApprovalService.shared
    @ObservedObject private var timeTravel = SurfaceTimeTravelCoordinator.shared

    var body: some View {
        let overhead = LoadoutConfigCodec.contextOverhead(items: usage.loadoutItems)
        let showBloat = overhead.isBloated && timeTravel.suggestionBackoff.shouldSuggest(ruleKey: "sixthSense.mcpBloat")

        VStack(alignment: .leading, spacing: 8) {
            if !approvals.requests.isEmpty { ClaudeApprovalCardView(service: approvals) }
            if showBloat {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(verbatim: String(format: "MCP %.0f%% (%dk tok) — Lean?", overhead.percent, overhead.totalTokens / 1000))
                        .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Spacer()
                    Button { usage.applyLoadoutProfile(.leanCoding); timeTravel.acceptSuggestion(ruleKey: "sixthSense.mcpBloat") } label: {
                        Text(verbatim: "Lean").font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.orange.opacity(0.22)))
                    }.buttonStyle(.plain)
                    Button { timeTravel.dismissSuggestion(ruleKey: "sixthSense.mcpBloat") } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 10).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }
            NotchAIPageView().frame(width: 600, height: 215).padding(8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.9)))
        }.padding(10).frame(width: 636)
    }
}
