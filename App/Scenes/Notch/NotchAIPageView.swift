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
                    Text(verbatim: snapshot.activeTurn?.isActive == true ? (snapshot.activeTurn?.model ?? String(localized: "Active")) : String(localized: "Idle"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    if let active = snapshot.activeTurn, active.isActive {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text(verbatim: "ACTIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                }

                // Token velocity readout — measured rows only; no rows means no number, not a zero.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: snapshot.providerToday.isEmpty ? "—" : snapshot.formattedTodayTokens)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(snapshot.providerToday.isEmpty ? Color.white.opacity(0.3) : .white)
                        Text("Tokens today").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
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

            }
            .padding(NotchDesignSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .notchCard()

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
                    Text("AI spend today")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer(minLength: 4)
                    // NP-3: three pills (Loadout / cap / Receipt) plus a savings badge asked for ~266 pt
                    // in a 279 pt card and truncated to "Loado…", "Cap:…", "Re…". One menu holds all
                    // three; the savings moved under the cost, where it belongs.
                    Menu {
                        Button { showingLoadout.toggle() } label: {
                            Text(verbatim: showingLoadout ? "Show spend" : "Show loadout")
                        }
                        Button { budgetPresetRaw = budgetPreset.next.rawValue } label: {
                            Text(verbatim: "Daily cap: \(budgetPreset.badgeTitle)")
                        }
                        Button { showingReceipt.toggle() } label: {
                            Text(verbatim: "Usage receipt")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .popover(isPresented: $showingReceipt) {
                        let receipt = AIStatsReceiptCalculator.calculate(
                            tokens: snapshot.todayTokens,
                            costUSD: snapshot.todayCost,
                            activeDuration: snapshot.activeDuration,
                            linesAdded: snapshot.linesAdded,
                            linesDeleted: snapshot.linesDeleted,
                            streakDays: snapshot.streakDays
                        )
                        AIReceiptPopoverView(receipt: receipt)
                    }
                }

                if showingLoadout {
                    loadoutDrawer
                } else {
                // Cost readout — the store's own number where the tool keeps one, priced here otherwise.
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: snapshot.providerToday.isEmpty ? "—" : snapshot.formattedTodayCost)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(snapshot.providerToday.isEmpty ? Color.white.opacity(0.3) : .white)
                    // NP-3: no `Sources:` fallback here — Card A already names the stores once, and two
                    // identical footers on one page read as a bug.
                    if !snapshot.costBasisLine.isEmpty {
                        Text(verbatim: snapshot.costBasisLine)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    if snapshot.todaySavings > 0 {
                        Text(verbatim: String(format: "$%.2f saved today", snapshot.todaySavings))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green.opacity(0.9))
                    }
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
            .notchCard()
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
