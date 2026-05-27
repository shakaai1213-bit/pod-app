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
                    earningsQualitySection
                    predictionsSection
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
                .fill(viewModel.isSnapshot ? AppColors.accentWarning : AppColors.accentSuccess)
                .frame(width: 7, height: 7)
            Text(viewModel.isSnapshot ? "ORCA OFFLINE" : "ORCA FUND")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(viewModel.isSnapshot ? AppColors.accentWarning : AppColors.accentSuccess)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((viewModel.isSnapshot ? AppColors.accentWarning : AppColors.accentSuccess).opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Section 1: P&L Overview

    private var pnlSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            tradingSectionHeader("P&L Overview", icon: "chart.bar.fill", color: AppColors.accentElectric)

            if let note = viewModel.errorMessage {
                offlineBanner(note)
            } else {
                protectedBanner
            }

            VStack(spacing: Theme.sm) {
                if viewModel.dashboard.bots.isEmpty {
                    emptyState("No ORCA Fund landing metrics are available.")
                } else {
                    ForEach(viewModel.dashboard.bots) { bot in
                        BotCard(bot: bot)
                    }
                }
            }
        }
        .padding(.top, Theme.md)
    }

    private var protectedBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.accentWarning)
            Text("Chief/Fund surface is read-only in Pod. No orders, positions, or protected mutations are available here.")
                .podTextStyle(.caption, color: AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.accentWarning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    if r.arms.isEmpty {
                        emptyState("Research arm detail is not exposed through ORCA Fund landing yet.")
                    } else {
                        ForEach(r.arms) { arm in
                            ArmRow(arm: arm)
                            if arm.id != r.arms.last?.id {
                                Divider().background(AppColors.border)
                            }
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

    // MARK: - Section 3: Earnings Quality

    private var earningsQualitySection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            tradingSectionHeader("Earnings Quality", icon: "doc.text.magnifyingglass", color: AppColors.accentCaptain)
            researchOnlyBanner

            if let surface = viewModel.earningsQuality {
                VStack(spacing: Theme.sm) {
                    earningsQualityTopTenCard(surface.topTen)
                    chartSetupLevelsCard(surface.chartSetups)
                    sectorTrendTapeCard(surface.sectorTrends)
                    evidenceGatesCard(surface)
                }
            } else {
                emptyState(viewModel.earningsQualityError ?? "Waiting for ORCA earnings quality research route.")
            }
        }
    }

    private var researchOnlyBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.accentWarning)
            Text("Research only · not a trade signal. Pod shows ORCA research packets only; no orders, sizing, strategy promotion, live capital, or runtime controls.")
                .podTextStyle(.caption, color: AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.accentWarning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func earningsQualityTopTenCard(_ candidates: [EarningsQualityCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Earnings Quality Top 10", icon: "list.number")
            Divider().background(AppColors.border)
            if candidates.isEmpty {
                emptyState("Top 10 research candidates are not available from ORCA yet.")
            } else {
                ForEach(candidates) { candidate in
                    HStack(alignment: .top, spacing: Theme.sm) {
                        Text(candidate.ticker)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.headline ?? candidate.qualityNote ?? "Research candidate")
                                .podTextStyle(.body, color: AppColors.textPrimary)
                                .lineLimit(2)
                            if let note = candidate.qualityNote, note != candidate.headline {
                                Text(note)
                                    .podTextStyle(.caption, color: AppColors.textTertiary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        if let score = candidate.score {
                            Text(String(format: "%.2f", score))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppColors.accentSuccess)
                        }
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.sm)
                    if candidate.id != candidates.last?.id {
                        Divider().background(AppColors.border)
                    }
                }
            }
        }
        .podCard(padding: 0)
    }

    private func chartSetupLevelsCard(_ setups: [ChartSetupLevel]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Chart Setup Levels", icon: "chart.xyaxis.line")
            Divider().background(AppColors.border)
            if setups.isEmpty {
                emptyState("Chart setup levels are not available from ORCA yet.")
            } else {
                ForEach(setups) { setup in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(setup.ticker)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(setup.setup ?? "Setup")
                                .podTextStyle(.caption, color: AppColors.textSecondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        HStack(spacing: Theme.xs) {
                            levelPill("Support", setup.support, AppColors.accentSuccess)
                            levelPill("Resist", setup.resistance, AppColors.accentWarning)
                            levelPill("Stop", setup.stop, AppColors.accentDanger)
                            levelPill("Target", setup.target, AppColors.accentElectric)
                        }
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.sm)
                    if setup.id != setups.last?.id {
                        Divider().background(AppColors.border)
                    }
                }
            }
        }
        .podCard(padding: 0)
    }

    private func sectorTrendTapeCard(_ trends: [SectorETFTrend]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Sector ETF Trend Tape", icon: "waveform.path.ecg")
            Divider().background(AppColors.border)
            if trends.isEmpty {
                emptyState("Sector ETF trend tape is not available from ORCA yet.")
            } else {
                ForEach(trends) { trend in
                    HStack(spacing: Theme.sm) {
                        Text(trend.symbol)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 50, alignment: .leading)
                        Text(trend.trend.replacingOccurrences(of: "_", with: " ").capitalized)
                            .podTextStyle(.body, color: trendColor(trend.trend))
                            .lineLimit(1)
                        Spacer()
                        if let score = trend.score {
                            Text(String(format: "%.2f", score))
                                .podTextStyle(.caption, color: AppColors.textSecondary)
                        }
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.sm)
                    if trend.id != trends.last?.id {
                        Divider().background(AppColors.border)
                    }
                }
            }
        }
        .podCard(padding: 0)
    }

    private func evidenceGatesCard(_ surface: EarningsQualitySurface) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Evidence + Gates", icon: "checklist.checked")
            Divider().background(AppColors.border)

            if surface.gates.isEmpty && surface.evidenceRefs.isEmpty {
                emptyState("Evidence and gate records are not available from ORCA yet.")
            } else {
                ForEach(surface.gates) { gate in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(gate.name)
                                .podTextStyle(.body, color: AppColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(gate.status.replacingOccurrences(of: "_", with: " ").uppercased())
                                .podTextStyle(.label, color: gateColor(gate.status))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(gateColor(gate.status).opacity(0.12))
                                .clipShape(Capsule())
                        }
                        if let note = gate.note {
                            Text(note)
                                .podTextStyle(.caption, color: AppColors.textTertiary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.sm)
                    Divider().background(AppColors.border)
                }

                if !surface.evidenceRefs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Evidence")
                            .podTextStyle(.label, color: AppColors.textTertiary)
                        ForEach(surface.evidenceRefs.prefix(4), id: \.self) { ref in
                            Text(ref)
                                .podTextStyle(.caption, color: AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(Theme.md)
                }
            }

            Divider().background(AppColors.border)
            Text("\(surface.policy) · \(surface.generatedAt ?? "freshness pending")")
                .podTextStyle(.caption, color: AppColors.textTertiary)
                .padding(Theme.md)
        }
        .podCard(padding: 0)
    }

    // MARK: - Section 4: Predictions

    private var predictionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            tradingSectionHeader("Chief Predictions", icon: "chart.line.text.clipboard", color: AppColors.accentElectric)
            researchOnlyBanner

            if let brief = viewModel.marketPredictionBrief {
                VStack(spacing: Theme.sm) {
                    marketPredictionCard(brief)
                    weekAheadEarningsPredictionCard(brief.earningsRows)
                    predictionCalibrationCard(brief.calibration, generatedAt: brief.generatedAt, asOfDate: brief.asOfDate)
                }
            } else {
                emptyState(viewModel.marketPredictionError ?? "Waiting for ORCA market prediction brief route.")
            }
        }
    }

    private func marketPredictionCard(_ brief: MarketPredictionBrief) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Market 30/60/90", icon: "calendar")
            Divider().background(AppColors.border)

            if brief.marketRows.isEmpty {
                emptyState("30/60/90 market trend rows are not available from ORCA yet.")
            } else {
                ForEach(brief.marketRows) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: Theme.sm) {
                            Text(row.symbol)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(width: 46, alignment: .leading)
                            Text(row.name ?? row.assetClass ?? "Market")
                                .podTextStyle(.body, color: AppColors.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            if let lastPrice = row.lastPrice {
                                Text(formatPrice(lastPrice))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }

                        HStack(spacing: Theme.xs) {
                            horizonPill("30D", prediction: row.prediction30d, confidence: row.confidence30d, returnValue: row.return30d)
                            horizonPill("60D", prediction: row.prediction60d, confidence: row.confidence60d, returnValue: row.return60d)
                            horizonPill("90D", prediction: row.prediction90d, confidence: row.confidence90d, returnValue: row.return90d)
                        }
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.sm)
                    if row.id != brief.marketRows.last?.id {
                        Divider().background(AppColors.border)
                    }
                }
            }
        }
        .podCard(padding: 0)
    }

    private func weekAheadEarningsPredictionCard(_ rows: [WeekAheadEarningsPrediction]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Week-Ahead Earnings", icon: "calendar.badge.clock")
            Divider().background(AppColors.border)

            if rows.isEmpty {
                emptyState("Week-ahead earnings predictions are not available from ORCA yet.")
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: Theme.sm) {
                        Text(row.symbol)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 50, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(predictionLabel(row.prediction))
                                .podTextStyle(.body, color: predictionColor(row.prediction))
                                .lineLimit(1)
                            Text(earningsDetail(row))
                                .podTextStyle(.caption, color: AppColors.textTertiary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatConfidence(row.confidence))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(predictionColor(row.prediction))
                            Text(row.earningsDate ?? "date pending")
                                .podTextStyle(.label, color: AppColors.textTertiary)
                        }
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.sm)
                    if row.id != rows.last?.id {
                        Divider().background(AppColors.border)
                    }
                }
            }
        }
        .podCard(padding: 0)
    }

    private func predictionCalibrationCard(_ calibration: PredictionCalibrationSummary?, generatedAt: String?, asOfDate: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Prediction Calibration", icon: "target")
            Divider().background(AppColors.border)

            HStack(spacing: 0) {
                researchStat(label: "Total", value: "\(calibration?.totalPredictions ?? 0)", color: AppColors.accentElectric)
                statDivider
                researchStat(label: "Resolved", value: "\(calibration?.resolved ?? 0)", color: AppColors.accentSuccess)
                statDivider
                researchStat(label: "Unresolved", value: "\(calibration?.unresolved ?? 0)", color: AppColors.accentWarning)
            }
            .padding(.vertical, Theme.md)

            Divider().background(AppColors.border)

            Text(calibration?.read ?? "Calibration starts after predictions resolve against market outcomes.")
                .podTextStyle(.caption, color: AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.md)

            Divider().background(AppColors.border)

            Text("As of \(asOfDate ?? "pending") / generated \(generatedAt ?? "pending")")
                .podTextStyle(.caption, color: AppColors.textTertiary)
                .padding(Theme.md)
        }
        .podCard(padding: 0)
    }

    private func horizonPill(_ label: String, prediction: String?, confidence: Double?, returnValue: Double?) -> some View {
        let color = predictionColor(prediction)
        return VStack(spacing: 2) {
            Text(label)
                .podTextStyle(.label, color: AppColors.textTertiary)
            Text(predictionLabel(prediction))
                .podTextStyle(.label, color: color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(formatPercent(returnValue)) / \(formatConfidence(confidence))")
                .podTextStyle(.label, color: AppColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    // MARK: - Section 5: Oracle

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
                    if oracle.predictions.isEmpty {
                        emptyState("Oracle predictions are not exposed through ORCA Fund landing yet.")
                    } else {
                        ForEach(oracle.predictions) { prediction in
                            OraclePredictionRow(prediction: prediction)
                            if prediction.id != oracle.predictions.last?.id {
                                Divider().background(AppColors.border)
                            }
                        }
                    }
                }
            }
            .podCard(padding: 0)
        }
    }

    // MARK: - Section 6: Earnings

    private var earningsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            tradingSectionHeader("Earnings Predictions", icon: "calendar.badge.clock", color: AppColors.accentCaptain)

            VStack(spacing: 0) {
                if viewModel.dashboard.earnings.isEmpty {
                    emptyState("Earnings predictions are not exposed through ORCA Fund landing yet.")
                } else {
                    ForEach(viewModel.dashboard.earnings) { event in
                        EarningsRow(event: event)
                        if event.id != viewModel.dashboard.earnings.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
            .podCard(padding: 0)
        }
    }

    // MARK: - Section 7: Macro

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            tradingSectionHeader("QQQ & SPY Predictions", icon: "chart.line.uptrend.xyaxis", color: AppColors.accentElectric)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Theme.sm
            ) {
                if viewModel.dashboard.macro.isEmpty {
                    emptyState("Macro predictions are not exposed through ORCA Fund landing yet.")
                        .gridCellColumns(2)
                } else {
                    ForEach(viewModel.dashboard.macro) { pred in
                        MacroCard(prediction: pred)
                    }
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

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .podTextStyle(.caption, color: AppColors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.md)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cardTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.accentCaptain)
            Text(title)
                .podTextStyle(.headline, color: AppColors.textPrimary)
            Spacer()
        }
        .padding(Theme.md)
    }

    private func levelPill(_ label: String, _ value: Double?, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value.map { String(format: "%.2f", $0) } ?? "-")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .podTextStyle(.label, color: AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func trendColor(_ trend: String) -> Color {
        let normalized = trend.lowercased()
        if normalized.contains("up") || normalized.contains("bull") || normalized.contains("strong") {
            return AppColors.accentSuccess
        }
        if normalized.contains("down") || normalized.contains("bear") || normalized.contains("weak") {
            return AppColors.accentDanger
        }
        return AppColors.accentWarning
    }

    private func gateColor(_ status: String) -> Color {
        let normalized = status.lowercased()
        if normalized.contains("pass") || normalized.contains("ok") || normalized.contains("clear") {
            return AppColors.accentSuccess
        }
        if normalized.contains("fail") || normalized.contains("block") || normalized.contains("breach") {
            return AppColors.accentDanger
        }
        return AppColors.accentWarning
    }

    private func predictionColor(_ prediction: String?) -> Color {
        let normalized = (prediction ?? "").lowercased()
        if normalized.contains("up") || normalized.contains("positive") || normalized.contains("long") {
            return AppColors.accentSuccess
        }
        if normalized.contains("down") || normalized.contains("fade") || normalized.contains("short") {
            return AppColors.accentDanger
        }
        return AppColors.accentWarning
    }

    private func predictionLabel(_ prediction: String?) -> String {
        guard let prediction, !prediction.isEmpty else {
            return "Pending"
        }
        return prediction.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func earningsDetail(_ row: WeekAheadEarningsPrediction) -> String {
        var parts: [String] = []
        if let days = row.daysUntil {
            parts.append(days == 0 ? "today" : "\(days)d out")
        }
        if let qualityScore = row.qualityScore {
            parts.append("quality \(String(format: "%.2f", qualityScore))")
        }
        if let eps = row.epsEstimate {
            parts.append("EPS \(String(format: "%.2f", eps))")
        }
        if let setup = row.chartSetup {
            parts.append(setup.replacingOccurrences(of: "_", with: " "))
        }
        return parts.isEmpty ? (row.companyName ?? row.sector ?? "details pending") : parts.joined(separator: " / ")
    }

    private func formatConfidence(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return String(format: "%.0f%%", value * 100)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f%%", value * 100))"
    }

    private func formatPrice(_ value: Double) -> String {
        if value >= 1_000 {
            return "$\(String(format: "%.1fk", value / 1_000))"
        }
        return "$\(String(format: "%.2f", value))"
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
