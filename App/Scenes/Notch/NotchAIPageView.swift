import SwiftUI

// Phase 33e — Page 1: AI Mission Control (Bento Card A: Active Model & Tokens, Card B: Spend & Limits)

struct NotchAIPageView: View {
    @ObservedObject private var agentService = AgentUsageService.shared
    @AppStorage(AgentBudgetPreset.key) private var budgetPresetRaw = AgentBudgetPreset.off.rawValue
    @State private var showingReceipt = false
    @State private var showingLoadout = false

    private var budgetPreset: AgentBudgetPreset {
        AgentBudgetPreset(rawValue: budgetPresetRaw) ?? .off
    }

    var body: some View {
        let snapshot = agentService.snapshot
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            // Card A: Active Turn & Token Velocity
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.purple, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 22)
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(verbatim: snapshot.activeTurn?.model ?? snapshot.lastMeasuredModel ?? "No AI activity today")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    if let active = snapshot.activeTurn, active.isActive {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text(verbatim: "ACTIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                    } else {
                        Text(verbatim: "IDLE").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                }

                // Token velocity readout — measured rows only; no rows means no number, not a zero.
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: snapshot.providerToday.isEmpty ? "—" : snapshot.formattedTodayTokens)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(verbatim: sourceCaption(snapshot))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 0)

                // Token distribution pills — only when something was measured.
                if !snapshot.providerToday.isEmpty {
                    HStack(spacing: 6) {
                        tokenBadge(label: "In", value: snapshot.todayTokens.input, color: .blue)
                        tokenBadge(label: "Out", value: snapshot.todayTokens.output, color: .purple)
                        tokenBadge(label: "Hit", value: Int(snapshot.todayTokens.cacheHitRate * 100), suffix: "%", color: .cyan)
                    }
                }

                BreatherRingsMiniView()
                    .padding(.top, 2)
            }
            .padding(NotchDesignSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                    )
            )

            // Card B: Spend & 5h Reset Arc
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.green, Color.mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 22)
                        Image(systemName: "dollarsign")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(verbatim: "AI Spend")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { showingLoadout.toggle() } label: {
                        Text(verbatim: showingLoadout ? "Spend" : "Loadout")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.cyan.opacity(showingLoadout ? 0.35 : 0.16)))
                    }
                    .buttonStyle(.plain)
                    Button {
                        budgetPresetRaw = budgetPreset.next.rawValue
                    } label: {
                        Text(verbatim: budgetPreset.badgeTitle)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    Button { showingReceipt.toggle() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text.fill").font(.system(size: 8))
                            Text(verbatim: "Receipt").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.purple.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingReceipt) {
                        let receipt = AIStatsReceiptCalculator.calculate(
                            tokens: snapshot.todayTokens,
                            costUSD: snapshot.todayCost,
                            activeDuration: 3600,
                            linesAdded: 120,
                            linesDeleted: 24,
                            streakDays: 3
                        )
                        AIReceiptPopoverView(receipt: receipt)
                    }
                    if snapshot.todaySavings > 0 {
                        Text(verbatim: String(format: "-$%.2f saved", snapshot.todaySavings))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    }
                }

                if showingLoadout {
                    loadoutDrawer
                } else {
                // Cost readout — the store's own number where the tool keeps one, priced here otherwise.
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: snapshot.providerToday.isEmpty ? "—" : snapshot.formattedTodayCost)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(verbatim: snapshot.costBasisLine.isEmpty ? sourceCaption(snapshot) : snapshot.costBasisLine)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 0)

                // Multi-provider session / daily quota bar
                if let (_, limits) = snapshot.limits.sorted(by: { $0.key.rawValue < $1.key.rawValue }).first,
                   let session = limits.windows.first(where: { $0.kind == .session }) ?? limits.windows.first {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: "\(limits.provider.displayName) Session")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text(verbatim: String(format: "%.0f%%", session.usedPercent))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(session.usedPercent > 80 ? .orange : .white.opacity(0.8))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(LinearGradient(colors: [Color.cyan, Color.purple], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, geo.size.width * CGFloat(session.usedFraction)), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                } else if let fraction = budgetPreset.usedFraction(todayCost: snapshot.todayCost),
                          let cap = budgetPreset.dailyCapUSD {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: String(format: "Daily Budget ($%.0f)", cap))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text(verbatim: String(format: "%.0f%%", fraction * 100))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(fraction > 0.8 ? .orange : .white.opacity(0.8))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(LinearGradient(colors: [Color.green, Color.cyan], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, geo.size.width * CGFloat(fraction)), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.cyan)
                        Text(verbatim: "Local Logs Connected")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                }
            }
            .padding(NotchDesignSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                    )
            )
        }
    }

    private var loadoutDrawer: some View {
        let overhead = LoadoutConfigCodec.contextOverhead(items: agentService.loadoutItems)
        let currentIdx = LoadoutProfile.allCases.firstIndex(of: agentService.activeProfile) ?? 0
        let nextIdx = (currentIdx + 1) % LoadoutProfile.allCases.count
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(verbatim: String(format: "~%.1fk ctx (%.1f%%)", Double(overhead.totalTokens) / 1000.0, overhead.percent))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(overhead.isBloated ? .orange : .cyan)
                Spacer()
                Button { agentService.applyLoadoutProfile(LoadoutProfile.allCases[nextIdx]) } label: {
                    Text(verbatim: agentService.activeProfile.title)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            if agentService.loadoutItems.isEmpty {
                Text(verbatim: "No MCP servers or skills discovered")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(agentService.loadoutItems) { item in
                            Button { agentService.toggleLoadoutItem(item) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: item.provider.symbol).font(.system(size: 9)).foregroundStyle(.cyan)
                                    Text(verbatim: item.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    Text(verbatim: "~\(item.estimatedTokens)t").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                                    Circle().fill(item.isEnabled ? Color.green : Color.white.opacity(0.2)).frame(width: 7, height: 7)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Names exactly the stores actually read; nothing measured and nothing read means no claim at all.
    private func sourceCaption(_ snapshot: AgentUsageSnapshot) -> String {
        snapshot.sourceNames.isEmpty ? "No usage recorded today" : "Sources: \(snapshot.sourceNames)"
    }

    private func tokenBadge(label: String, value: Int, suffix: String = "", color: Color) -> some View {
        let displayVal: String
        if suffix == "%" {
            displayVal = "\(value)%"
        } else if value >= 1_000 {
            displayVal = String(format: "%.0fk", Double(value) / 1000.0)
        } else {
            displayVal = "\(value)"
        }
        return HStack(spacing: 3) {
            Text(verbatim: label).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            Text(verbatim: displayVal).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

// MARK: - AI Stats Receipt & Breather Rings (Slice 2.6)

struct AIReceiptPopoverView: View {
    let receipt: AIStatsReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "AI Usage Receipt")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text(verbatim: receipt.formattedCost)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.green)
            }
            Divider()
            ForEach(receipt.items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: item.title)
                            .font(.system(size: 10, weight: .medium))
                        if let sub = item.subtitle {
                            Text(verbatim: sub)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(verbatim: item.value)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .padding(.vertical, 1)
            }
        }
        .padding(10)
        .frame(width: 220)
    }
}

/// PHN-2 — the rings were constructed per render before this, so they always read 0/12, 0/6, 0/8.
/// They now observe the shared controller: a done pause fills Eyes or Stretch, a logged glass fills Hydrate.
struct BreatherRingsMiniView: View {
    @ObservedObject private var hydro = HydrationController.shared

    private var rings: BreatherRings { hydro.breather.rings }

    var body: some View {
        HStack(spacing: 8) {
            ringPill("Eyes", progress: rings.eyes.progress, color: .cyan)
            ringPill("Stretch", progress: rings.stretch.progress, color: .mint)
            ringPill("Hydrate", progress: rings.hydrate.progress, color: .blue)
        }
    }

    private func ringPill(_ label: String, progress: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .trim(from: 0, to: CGFloat(max(0.1, progress)))
                .stroke(color, lineWidth: 2)
                .frame(width: 8, height: 8)
                .rotationEffect(.degrees(-90))
            Text(verbatim: label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}
