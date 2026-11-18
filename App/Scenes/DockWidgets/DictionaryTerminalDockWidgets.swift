import SwiftUI

/// Dictionary / Terminal as dock widgets: a compact glyph tile (no size presets). A click opens the panel.
private struct ToolDockChip: View {
    let symbol: String
    let label: LocalizedStringKey
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .opacity(DockWidgetStyle.secondaryOpacity)
        }
        .frame(maxHeight: .infinity)
        .dockWidgetChip()
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.isButton)
    }
}

struct DictionaryDockChip: View {
    let onOpen: () -> Void
    var body: some View { ToolDockChip(symbol: "character.book.closed", label: "Define…", onOpen: onOpen) }
}

struct TerminalDockChip: View {
    let onOpen: () -> Void
    var body: some View { ToolDockChip(symbol: "terminal", label: "Terminal", onOpen: onOpen) }
}

struct RailDictionaryTile: View {
    var body: some View {
        Image(systemName: "character.book.closed")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .dockWidgetRailTile()
            .accessibilityLabel(Text("Dictionary"))
    }
}

struct RailTerminalTile: View {
    var body: some View {
        Image(systemName: "terminal")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .dockWidgetRailTile()
            .accessibilityLabel(Text("Terminal"))
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
