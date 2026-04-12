import SwiftUI

// MARK: - Trading View

struct TradingView: View {

    @State private var viewModel = TradingViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    pnlSection
                    researchSection
                    oracleSection
                    earningsSection
                    macroSection
                }
                .padding(.horizontal, Theme.md)
                .padding(.bottom, Theme.xxl)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Trading")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(AppColors.accentElectric)
                    } else {
                        refreshedBadge
                    }
                }
            }
            .refreshable {
                await viewModel.loadData()
            }
            .task {
                await viewModel.loadData()
            }
        }
    }

    // MARK: - Refreshed Badge

    private var refreshedBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(AppColors.accentSuccess)
                .frame(width: 7, height: 7)
            Text("LIVE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColors.accentSuccess)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppColors.accentSuccess.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Section 1: P&L Overview

    private var pnlSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            tradingSectionHeader("P&L Overview", icon: "chart.bar.fill", color: AppColors.accentElectric)

            if let note = viewModel.errorMessage {
                offlineBanner(note)
            }

            VStack(spacing: Theme.sm) {
                ForEach(viewModel.dashboard.bots) { bot in
                    BotCard(bot: bot)
                }
            }
        }
        .padding(.top, Theme.md)
    }

    // MARK: - Section 2: Research

    private var researchSection: some View {
        let r = viewModel.dashboard.research
        return VStack(alignment: .leading, spacing: Theme.sm) {
            tradingSectionHeader("Squid & Octopus Research", icon: "flask.fill", color: AppColors.accentAgent)

            VStack(spacing: 0) {
                // Top stats row
                HStack(spacing: 0) {
                    researchStat(label: "Active Arms", value: "\(r.activeArms)", color: AppColors.accentAgent)
                    statDivider
                    researchStat(label: "Experiments Today", value: r.experimentsToday >= 1000
                        ? "\(r.experimentsToday / 1000).\((r.experimentsToday % 1000) / 100)k+"
                        : "\(r.experimentsToday)",
                        color: AppColors.accentElectric
                    )
                    statDivider
                    researchStat(label: "Best Score", value: String(format: "%.2f", r.bestScore), color: AppColors.accentSuccess)
                }
                .padding(.vertical, Theme.md)

                Divider().background(AppColors.border)

                // Best experiment callout
                HStack {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.accentWarning)
                    Text("Best: Exp \(r.bestExperiment) · Score \(String(format: "%.2f", r.bestScore))")
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, Theme.md)
                .padding(.vertical, Theme.sm)

                Divider().background(AppColors.border)

                // Top arms
                VStack(spacing: 0) {
                    ForEach(r.arms) { arm in
                        ArmRow(arm: arm)
                        if arm.id != r.arms.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }

                Divider().background(AppColors.border)

                // Queue note
                HStack {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(r.queueNote)
                        .podTextStyle(.caption, color: AppColors.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, Theme.md)
                .padding(.vertical, Theme.sm)
            }
            .podCard(padding: 0)
        }
    }

    // MARK: - Section 3: Oracle

    private var oracleSection: some View {
        let oracle = viewModel.dashboard.oracle
        return VStack(alignment: .leading, spacing: Theme.sm) {
            tradingSectionHeader("Oracle", icon: "eye.fill", color: AppColors.accentWarning)

            VStack(spacing: 0) {
                // Conviction gauge
                VStack(spacing: Theme.sm) {
                    OracleGauge(score: oracle.score)

                    HStack {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textTertiary)
                        Text(oracle.statusNote)
                            .podTextStyle(.caption, color: AppColors.textSecondary)
                        Spacer()
                        Text("Model \(oracle.modelVersion)")
                            .podTextStyle(.label, color: AppColors.textTertiary)
                    }
                }
                .padding(Theme.md)

                Divider().background(AppColors.border)

                // Predictions
                VStack(spacing: 0) {
                    ForEach(oracle.predictions) { prediction in
                        OraclePredictionRow(prediction: prediction)
                        if prediction.id != oracle.predictions.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
            .podCard(padding: 0)
        }
    }

    // MARK: - Section 4: Earnings

    private var earningsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            tradingSectionHeader("Earnings Predictions", icon: "calendar.badge.clock", color: AppColors.accentCaptain)

            VStack(spacing: 0) {
                ForEach(viewModel.dashboard.earnings) { event in
                    EarningsRow(event: event)
                    if event.id != viewModel.dashboard.earnings.last?.id {
                        Divider().background(AppColors.border)
                    }
                }
            }
            .podCard(padding: 0)
        }
    }

    // MARK: - Section 5: Macro

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            tradingSectionHeader("QQQ & SPY Predictions", icon: "chart.line.uptrend.xyaxis", color: AppColors.accentElectric)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Theme.sm
            ) {
                ForEach(viewModel.dashboard.macro) { pred in
                    MacroCard(prediction: pred)
                }
            }
        }
    }

    // MARK: - Helpers

    private func tradingSectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)

            Text(title.uppercased())
                .podTextStyle(.label, color: AppColors.textTertiary)
        }
    }

    private func researchStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .podTextStyle(.caption, color: AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Divider()
            .frame(height: 36)
            .background(AppColors.border)
    }

    private func offlineBanner(_ message: String) -> some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.accentWarning)
            Text(message)
                .podTextStyle(.caption, color: AppColors.accentWarning)
            Spacer()
        }
        .padding(.horizontal, Theme.sm)
        .padding(.vertical, Theme.xs)
        .background(AppColors.accentWarning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(AppColors.accentWarning.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Bot Card

private struct BotCard: View {
    let bot: TradingBot

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: Theme.xs) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)

                Text(bot.name + (bot.version.isEmpty ? "" : " \(bot.version)"))
                    .podTextStyle(.headline, color: AppColors.textPrimary)

                Spacer()

                if let regime = bot.regime {
                    RegimeBadge(regime: regime)
                }

                Text(bot.status.rawValue.uppercased())
                    .podTextStyle(.label, color: statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Theme.md)
            .padding(.top, Theme.md)
            .padding(.bottom, Theme.sm)

            Divider().background(AppColors.border)

            // Metrics row
            HStack(spacing: 0) {
                botMetric(label: "Balance", value: formatCurrency(bot.balance), color: AppColors.textPrimary)
                metricDivider
                botMetric(label: "P&L", value: formatPnl(bot.pnl), color: bot.pnl >= 0 ? AppColors.accentSuccess : AppColors.accentDanger)
                metricDivider
                botMetric(label: "Open Pos.", value: "\(bot.openPositions)", color: AppColors.textPrimary)
                if bot.winRate > 0 {
                    metricDivider
                    botMetric(label: "Win Rate", value: formatPct(bot.winRate), color: AppColors.textSecondary)
                }
            }
            .padding(.vertical, Theme.sm)

            if let total = bot.tradesTotal {
                Divider().background(AppColors.border)
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("\(total.formatted()) total trades")
                        .podTextStyle(.caption, color: AppColors.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, Theme.md)
                .padding(.vertical, Theme.xs)
            }
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch bot.status {
        case .running: return AppColors.accentSuccess
        case .paused:  return AppColors.accentWarning
        case .stopped: return AppColors.textTertiary
        case .error:   return AppColors.accentDanger
        }
    }

    private func botMetric(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .podTextStyle(.caption, color: AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 30)
            .background(AppColors.border)
    }

    private func formatCurrency(_ value: Double) -> String {
        if value >= 1_000 {
            return "$\(String(format: "%.1f", value / 1_000))k"
        }
        return "$\(String(format: "%.2f", value))"
    }

    private func formatPnl(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        if abs(value) >= 1_000 {
            return "\(sign)$\(String(format: "%.1f", value / 1_000))k"
        }
        return "\(sign)$\(String(format: "%.2f", value))"
    }

    private func formatPct(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}

// MARK: - Regime Badge

private struct RegimeBadge: View {
    let regime: MarketRegime

    var body: some View {
        Text(regime.rawValue)
            .podTextStyle(.label, color: color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch regime {
        case .bull:    return AppColors.accentSuccess
        case .caution: return AppColors.accentWarning
        case .bear:    return AppColors.accentDanger
        }
    }
}

// MARK: - Arm Row

private struct ArmRow: View {
    let arm: ResearchArm

    var body: some View {
        HStack(spacing: Theme.sm) {
            // Symbol badge
            Text(arm.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.accentElectric)
                .frame(width: 38)

            // TP / SL
            HStack(spacing: Theme.xs) {
                labelValue("TP", String(format: "%.1f%%", arm.takeProfit), AppColors.accentSuccess)
                labelValue("SL", String(format: "%.1f%%", arm.stopLoss), AppColors.accentDanger)
            }

            Spacer()

            // P&L bar
            HStack(spacing: Theme.xs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.backgroundTertiary)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(pnlColor)
                            .frame(width: geo.size.width * min(CGFloat(arm.pnlPercent) / 100.0, 1.0))
                    }
                }
                .frame(width: 60, height: 6)

                Text(String(format: "+%.1f%%", arm.pnlPercent))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(pnlColor)
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.sm)
    }

    private var pnlColor: Color {
        arm.pnlPercent >= 0 ? AppColors.accentSuccess : AppColors.accentDanger
    }

    private func labelValue(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .podTextStyle(.label, color: AppColors.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Oracle Gauge

struct OracleGauge: View {
    let score: Double   // -1.0 to +1.0

    var body: some View {
        VStack(spacing: Theme.xs) {
            // Gauge bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    LinearGradient(
                        colors: [AppColors.accentDanger, AppColors.accentWarning, AppColors.accentSuccess],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(Capsule())

                    // Needle
                    let normalized = (score + 1.0) / 2.0
                    let xPos = geo.size.width * CGFloat(normalized)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.textPrimary)
                        .frame(width: 3, height: geo.size.height + 8)
                        .offset(x: xPos - 1.5, y: -4)
                }
            }
            .frame(height: 16)

            // Labels
            HStack {
                Text("-1.0")
                    .podTextStyle(.label, color: AppColors.accentDanger)
                Spacer()
                VStack(spacing: 1) {
                    Text(String(format: "%.4f", score))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(gaugeColor)
                    Text("Conviction Score")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                }
                Spacer()
                Text("+1.0")
                    .podTextStyle(.label, color: AppColors.accentSuccess)
            }
        }
        .padding(.vertical, Theme.xs)
    }

    private var gaugeColor: Color {
        if score > 0.3 { return AppColors.accentSuccess }
        if score < -0.3 { return AppColors.accentDanger }
        return AppColors.accentWarning
    }
}

// MARK: - Oracle Prediction Row

private struct OraclePredictionRow: View {
    let prediction: OraclePrediction

    var body: some View {
        HStack(spacing: Theme.sm) {
            // Direction pill
            Text(prediction.direction)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(prediction.direction == "YES" ? AppColors.accentSuccess : AppColors.accentDanger)
                .frame(width: 32)
                .padding(.vertical, 3)
                .background((prediction.direction == "YES" ? AppColors.accentSuccess : AppColors.accentDanger).opacity(0.12))
                .clipShape(Capsule())

            // Question
            Text(prediction.question)
                .podTextStyle(.body, color: AppColors.textPrimary)
                .lineLimit(2)

            Spacer()

            // Confidence
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f%%", prediction.confidence * 100))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("conf.")
                    .podTextStyle(.label, color: AppColors.textTertiary)
            }
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.sm)
    }
}

// MARK: - Earnings Row

private struct EarningsRow: View {
    let event: EarningsEvent

    var body: some View {
        HStack(spacing: Theme.sm) {
            // Ticker
            Text(event.ticker)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 44, alignment: .leading)

            // Direction arrow
            directionView

            // Date
            Text(formattedDate)
                .podTextStyle(.caption, color: AppColors.textSecondary)

            Spacer()

            // Confidence bar + label
            HStack(spacing: Theme.xs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColors.backgroundTertiary)
                        Capsule()
                            .fill(directionColor)
                            .frame(width: geo.size.width * CGFloat(event.confidence))
                    }
                }
                .frame(width: 48, height: 6)

                Text(String(format: "%.0f%%", event.confidence * 100))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(directionColor)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.sm)
    }

    private var directionView: some View {
        HStack(spacing: 4) {
            Image(systemName: directionIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(directionColor)
            Text(event.direction.rawValue)
                .podTextStyle(.caption, color: directionColor)
        }
        .frame(width: 68, alignment: .leading)
    }

    private var directionIcon: String {
        switch event.direction {
        case .long:    return "arrow.up.right"
        case .short:   return "arrow.down.right"
        case .neutral: return "arrow.right"
        }
    }

    private var directionColor: Color {
        switch event.direction {
        case .long:    return AppColors.accentSuccess
        case .short:   return AppColors.accentDanger
        case .neutral: return AppColors.accentWarning
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: event.date)
    }
}

// MARK: - Macro Card

private struct MacroCard: View {
    let prediction: MacroPrediction

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            HStack {
                Text(prediction.instrument)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(prediction.timeframe)
                    .podTextStyle(.label, color: AppColors.textTertiary)
            }

            RegimeBadge(regime: prediction.regime)

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColors.backgroundTertiary)
                        Capsule()
                            .fill(regimeColor)
                            .frame(width: geo.size.width * CGFloat(prediction.conviction))
                    }
                }
                .frame(height: 6)

                Text(String(format: "%.0f%% conviction", prediction.conviction * 100))
                    .podTextStyle(.caption, color: AppColors.textSecondary)
            }
        }
        .padding(Theme.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(regimeColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var regimeColor: Color {
        switch prediction.regime {
        case .bull:    return AppColors.accentSuccess
        case .caution: return AppColors.accentWarning
        case .bear:    return AppColors.accentDanger
        }
    }
}

// MARK: - Preview

#Preview {
    TradingView()
}
