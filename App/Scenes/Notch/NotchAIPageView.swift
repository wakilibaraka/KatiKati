import SwiftUI

// Phase 33e — Page 1: AI Mission Control (Bento Card A: Active Model & Tokens, Card B: Spend & Limits)

struct NotchAIPageView: View {
    @ObservedObject private var agentService = AgentUsageService.shared

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
                    Text(verbatim: snapshot.activeTurn?.model ?? "Claude 3.7 Sonnet")
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

                // Token velocity readout
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: snapshot.formattedTodayTokens)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(verbatim: "tokens processed today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 0)

                // Token distribution pills
                HStack(spacing: 6) {
                    tokenBadge(label: "In", value: snapshot.todayTokens.input, color: .blue)
                    tokenBadge(label: "Out", value: snapshot.todayTokens.output, color: .purple)
                    tokenBadge(label: "Hit", value: Int(snapshot.todayTokens.cacheHitRate * 100), suffix: "%", color: .cyan)
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
                    Text(verbatim: "API List Spend")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    if snapshot.todaySavings > 0 {
                        Text(verbatim: String(format: "-$%.2f saved", snapshot.todaySavings))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    }
                }

                // Cost readout
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: snapshot.formattedTodayCost)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(verbatim: "estimated value consumed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 0)

                // 5-hour rolling session limit bar
                if let limits = snapshot.limits[.claude],
                   let session = limits.windows.first(where: { $0.kind == .session }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: "5h Session Window")
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
