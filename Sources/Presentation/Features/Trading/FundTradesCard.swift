import SwiftUI

struct FundTradesCard: View {
    @State private var viewModel: FundTradesViewModel
    @State private var showingDetail = false

    @MainActor
    init() {
        _viewModel = State(initialValue: FundTradesViewModel())
    }

    @MainActor
    init(viewModel: FundTradesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fund-trades-card")
        .sheet(isPresented: $showingDetail) {
            FundTradesDetailSheet(
                feed: viewModel.feed,
                isLoading: viewModel.isLoading,
                errorMessage: viewModel.errorMessage,
                onRefresh: {
                    await viewModel.load()
                }
            )
            .presentationDetents([.medium, .large])
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var cardBody: some View {
        let feed = viewModel.feed
        let payload = feed?.data?.payload

        return VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .center, spacing: Theme.xs) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.accentElectric)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Fund Trades")
                        .podTextStyle(.headline, color: AppColors.textPrimary)
                    Text("Read-only route breakdown")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                }

                Spacer(minLength: 0)

                if viewModel.isLoading && feed == nil {
                    ProgressView()
                        .scaleEffect(0.72)
                } else {
                    FundTradesStageChip(stage: feed?.stage ?? .paper)
                }
            }

            if let feed, feed.hasPayloadData, let payload {
                VStack(spacing: Theme.xs) {
                    HStack(spacing: 0) {
                        compactMetric("Stitch", value: "\(payload.openCount(for: "stitch"))")
                        metricDivider
                        compactMetric("Lilo", value: "\(payload.openCount(for: "lilo"))")
                        metricDivider
                        compactMetric("Open", value: "\(payload.totalOpenCount)")
                        metricDivider
                        compactMetric("Closed", value: "\(payload.closedRecent.count)")
                    }

                    HStack(spacing: Theme.xs) {
                        if feed.isStale && feed.normalizedQuality != "stale" {
                            statusPill("STALE", icon: "clock.badge.exclamationmark", color: AppColors.accentWarning)
                        }
                        statusPill(feed.normalizedQuality.uppercased(), icon: "checkmark.seal", color: qualityColor(feed.normalizedQuality))
                        Spacer(minLength: 0)
                        Text(FundTradesFormat.relativeTime(feed.displayAsOf))
                            .podTextStyle(.caption, color: AppColors.textTertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                awaitingFeedPanel(feed: feed)
            }

            HStack(spacing: Theme.xs) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.accentWarning)
                Text("Protected lane visible; no order, position, wallet, or broker actions.")
                    .podTextStyle(.caption, color: AppColors.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(Theme.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(borderColor(feed).opacity(0.32), lineWidth: 1)
        )
    }

    private func awaitingFeedPanel(feed: FundRouteFeedDTO?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.xs) {
                Text("awaiting feed")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.accentWarning)
                Spacer(minLength: 0)
                statusPill((feed?.normalizedQuality ?? "unavailable").uppercased(), icon: "wifi.exclamationmark", color: AppColors.accentWarning)
            }

            Text(feed?.userFacingDegradedReason ?? viewModel.errorMessage ?? "ORCA trade breakdown route has not returned payload data yet.")
                .podTextStyle(.caption, color: AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.xs) {
                Text(feed?.displayStaleness ?? "staleness pending")
                    .podTextStyle(.label, color: AppColors.textTertiary)
                Text("as of \(FundTradesFormat.relativeTime(feed?.displayAsOf))")
                    .podTextStyle(.label, color: AppColors.textTertiary)
            }
        }
        .padding(Theme.sm)
        .background(AppColors.accentWarning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func compactMetric(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .podTextStyle(.label, color: AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 32)
            .background(AppColors.border)
    }

    private func statusPill(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .podTextStyle(.label, color: color)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.11))
        .clipShape(Capsule())
    }

    private func qualityColor(_ quality: String) -> Color {
        switch quality.lowercased() {
        case "available": return AppColors.accentSuccess
        case "stale", "degraded": return AppColors.accentWarning
        case "malformed", "unavailable": return AppColors.accentDanger
        default: return AppColors.textTertiary
        }
    }

    private func borderColor(_ feed: FundRouteFeedDTO?) -> Color {
        guard let feed else { return AppColors.border }
        if feed.hasPayloadData && !feed.isStale { return AppColors.accentSuccess }
        if feed.hasPayloadData { return AppColors.accentWarning }
        return AppColors.accentWarning
    }
}

struct FundTradesDetailSheet: View {
    let feed: FundRouteFeedDTO?
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        detailScroll
        #else
        NavigationStack {
            detailScroll
            .navigationTitle("Fund Trades")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    doneButton
                }
            }
        }
        #endif
    }

    private var doneButton: some View {
        Button("Done") {
            dismiss()
        }
    }

    private var detailScroll: some View {
        #if os(macOS)
        detailStack
            .background(AppColors.backgroundPrimary)
        #else
        ScrollView {
            detailStack
        }
        .background(AppColors.backgroundPrimary)
        .refreshable {
            await onRefresh()
        }
        #endif
    }

    private var detailStack: some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            if isLoading && feed == nil {
                loadingPanel
            } else if let feed, let payload = feed.data?.payload {
                summaryPanel(feed: feed, payload: payload)
                ForEach(payload.deskSections) { desk in
                    deskSection(desk, payload: payload)
                }
                closedWithoutDeskSection(payload)
                protectedControlsFootnote(feed.data?.blockedControls ?? [])
            } else {
                awaitingDetailPanel
                protectedControlsFootnote([])
            }
        }
        .padding(Theme.md)
        .padding(.bottom, Theme.xxl)
    }

    private var loadingPanel: some View {
        HStack(spacing: Theme.sm) {
            ProgressView()
                .tint(AppColors.accentElectric)
            Text("Loading ORCA trade breakdown route...")
                .podTextStyle(.caption, color: AppColors.textSecondary)
            Spacer(minLength: 0)
        }
        .podCard()
    }

    private var awaitingDetailPanel: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Label("awaiting feed", systemImage: "wifi.exclamationmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppColors.accentWarning)

            Text(feed?.userFacingDegradedReason ?? errorMessage ?? "ORCA trade breakdown route is degraded or unavailable.")
                .podTextStyle(.body, color: AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.xs) {
                detailChip(feed?.normalizedQuality.uppercased() ?? "UNAVAILABLE", color: AppColors.accentWarning)
                detailChip(feed?.displayStaleness ?? "STALENESS PENDING", color: AppColors.textTertiary)
            }

            Text("Pull to refresh re-queries the protected read route only.")
                .podTextStyle(.caption, color: AppColors.textTertiary)
        }
        .podCard()
    }

    private func summaryPanel(feed: FundRouteFeedDTO, payload: FundTradesPayloadDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .center, spacing: Theme.xs) {
                Label("Route summary", systemImage: "point.3.connected.trianglepath.dotted")
                    .podTextStyle(.headline, color: AppColors.textPrimary)
                Spacer(minLength: 0)
                FundTradesStageChip(stage: feed.stage)
            }

            HStack(spacing: 0) {
                summaryMetric("Stitch", "\(payload.openCount(for: "stitch"))")
                metricDivider
                summaryMetric("Lilo", "\(payload.openCount(for: "lilo"))")
                metricDivider
                summaryMetric("Open", "\(payload.totalOpenCount)")
                metricDivider
                summaryMetric("Closed", "\(payload.closedRecent.count)")
            }

            HStack(spacing: Theme.xs) {
                if feed.isStale && feed.normalizedQuality != "stale" {
                    detailChip("STALE", color: AppColors.accentWarning)
                }
                detailChip(feed.normalizedQuality.uppercased(), color: qualityColor(feed.normalizedQuality))
                Text(FundTradesFormat.relativeTime(feed.displayAsOf))
                    .podTextStyle(.caption, color: AppColors.textTertiary)
                Spacer(minLength: 0)
            }
        }
        .podCard()
    }

    private func deskSection(_ desk: FundTradesDeskDTO, payload: FundTradesPayloadDTO) -> some View {
        let openPositions = payload.openPositions.filter { $0.matchesDesk(desk.id) }
        let closedTrades = payload.closedRecent.filter { $0.matchesDesk(desk.id) }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.xs) {
                Text(desk.displayName)
                    .podTextStyle(.headline, color: AppColors.textPrimary)
                Spacer(minLength: 0)
                if let status = desk.status {
                    detailChip(status.uppercased(), color: deskStatusColor(status))
                }
            }
            .padding(Theme.md)

            Divider().background(AppColors.border)

            if !desk.strategyAggregates.isEmpty {
                detailSubheader("Strategy aggregates")
                ForEach(desk.strategyAggregates) { aggregate in
                    strategyAggregateRow(aggregate)
                    Divider().background(AppColors.border)
                }
            } else {
                deskAggregateFallback(desk)
                Divider().background(AppColors.border)
            }

            detailSubheader("Open positions")
            if openPositions.isEmpty {
                emptyDetail("No open positions reported for \(desk.displayName).")
            } else {
                ForEach(openPositions) { position in
                    positionRow(position)
                    if position.id != openPositions.last?.id {
                        Divider().background(AppColors.border)
                    }
                }
            }

            Divider().background(AppColors.border)
            detailSubheader("Closed tail")
            if closedTrades.isEmpty {
                emptyDetail("No recent closed trades reported for \(desk.displayName).")
            } else {
                ForEach(closedTrades) { trade in
                    closedTradeRow(trade)
                    if trade.id != closedTrades.last?.id {
                        Divider().background(AppColors.border)
                    }
                }
            }
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func closedWithoutDeskSection(_ payload: FundTradesPayloadDTO) -> some View {
        let assigned = Set(payload.deskSections.map { $0.id.lowercased() })
        let unassigned = payload.closedRecent.filter { trade in
            guard let desk = trade.desk?.lowercased(), !desk.isEmpty else { return true }
            return !assigned.contains(desk)
        }

        if !unassigned.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                detailSubheader("Other closed tail")
                ForEach(unassigned) { trade in
                    closedTradeRow(trade)
                    if trade.id != unassigned.last?.id {
                        Divider().background(AppColors.border)
                    }
                }
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
    }

    private func protectedControlsFootnote(_ controls: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Label("Protected controls", systemImage: "lock.shield.fill")
                .podTextStyle(.headline, color: AppColors.accentWarning)

            if controls.isEmpty {
                Text("No protected controls are exposed by this feed.")
                    .podTextStyle(.caption, color: AppColors.textSecondary)
            } else {
                ForEach(controls, id: \.self) { item in
                    HStack(alignment: .top, spacing: Theme.xs) {
                        Circle()
                            .fill(AppColors.accentWarning)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(item)
                            .podTextStyle(.caption, color: AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("Pod renders state only. Execution authority remains outside this surface.")
                .podTextStyle(.label, color: AppColors.textTertiary)
        }
        .podCard()
    }

    private func deskAggregateFallback(_ desk: FundTradesDeskDTO) -> some View {
        HStack(spacing: 0) {
            summaryMetric("Mode", desk.mode ?? "-")
            metricDivider
            summaryMetric("Open", desk.openPositionCount.map(String.init) ?? "-")
            metricDivider
            summaryMetric("Closed", desk.closedRecentCount.map(String.init) ?? "-")
            metricDivider
            summaryMetric("P&L", FundTradesFormat.money(desk.pnl))
        }
        .padding(.vertical, Theme.sm)
    }

    private func strategyAggregateRow(_ aggregate: FundTradesStrategyAggregateDTO) -> some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(aggregate.displayName)
                    .podTextStyle(.body, color: AppColors.textPrimary)
                    .lineLimit(1)
                if let status = aggregate.status {
                    Text(status.replacingOccurrences(of: "_", with: " "))
                        .podTextStyle(.caption, color: AppColors.textTertiary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text("open \(aggregate.openCount.map(String.init) ?? "-") / closed \(aggregate.closedCount.map(String.init) ?? "-")")
                    .podTextStyle(.caption, color: AppColors.textSecondary)
                    .lineLimit(1)
                Text("\(FundTradesFormat.money(aggregate.pnl)) / win \(FundTradesFormat.percent(aggregate.winRate))")
                    .podTextStyle(.label, color: AppColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.sm)
    }

    private func positionRow(_ position: FundTradePositionDTO) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: Theme.sm) {
                Text(position.symbol ?? "Position")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 94, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text([position.side, position.strategy].compactMap { $0 }.joined(separator: " / "))
                        .podTextStyle(.body, color: AppColors.textSecondary)
                        .lineLimit(1)
                    Text("opened \(FundTradesFormat.relativeTime(position.openedAt))")
                        .podTextStyle(.caption, color: AppColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(FundTradesFormat.money(position.pnl))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pnlColor(position.pnl))
            }

            HStack(spacing: Theme.xs) {
                if position.quantity != nil {
                    valuePill("Qty", FundTradesFormat.compactNumber(position.quantity), color: AppColors.textSecondary)
                }
                if position.sizeDollars != nil {
                    valuePill("Size", FundTradesFormat.money(position.sizeDollars), color: AppColors.textSecondary)
                }
                valuePill("Entry", price(position.entryPrice), color: AppColors.accentElectric)
                valuePill("Stop", price(position.stop), color: AppColors.accentWarning)
                valuePill("Target", price(position.target), color: AppColors.accentSuccess)
            }
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.sm)
    }

    private func closedTradeRow(_ trade: FundClosedTradeDTO) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: Theme.sm) {
                Text(trade.symbol ?? "Trade")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 94, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text([trade.side, trade.strategy].compactMap { $0 }.joined(separator: " / "))
                        .podTextStyle(.body, color: AppColors.textSecondary)
                        .lineLimit(1)
                    Text(closedTradeContext(trade))
                        .podTextStyle(.caption, color: AppColors.textTertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Text(FundTradesFormat.money(trade.pnl))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pnlColor(trade.pnl))
            }

            HStack(spacing: Theme.xs) {
                if trade.quantity != nil {
                    valuePill("Qty", FundTradesFormat.compactNumber(trade.quantity), color: AppColors.textSecondary)
                }
                if trade.entryPrice != nil {
                    valuePill("Entry", price(trade.entryPrice), color: AppColors.accentElectric)
                }
                if trade.exitPrice != nil {
                    valuePill("Exit", price(trade.exitPrice), color: AppColors.accentCaptain)
                }
                if trade.stop != nil {
                    valuePill("Stop", price(trade.stop), color: AppColors.accentWarning)
                }
                if trade.pnlPercent != nil {
                    valuePill("Return", FundTradesFormat.percent(trade.pnlPercent), color: pnlColor(trade.pnl))
                }
            }
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.sm)
    }

    private func closedTradeContext(_ trade: FundClosedTradeDTO) -> String {
        var parts: [String] = []
        if let reason = trade.reason, !reason.isEmpty {
            parts.append(reason)
        }
        if let closedAt = trade.closedAt {
            parts.append(FundTradesFormat.relativeTime(closedAt))
        }
        return parts.joined(separator: " / ")
    }

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(label)
                .podTextStyle(.label, color: AppColors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailSubheader(_ text: String) -> some View {
        Text(text.uppercased())
            .podTextStyle(.label, color: AppColors.textTertiary)
            .padding(.horizontal, Theme.md)
            .padding(.top, Theme.sm)
            .padding(.bottom, Theme.xs)
    }

    private func emptyDetail(_ text: String) -> some View {
        Text(text)
            .podTextStyle(.caption, color: AppColors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.md)
            .padding(.bottom, Theme.sm)
    }

    private func valuePill(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .podTextStyle(.label, color: AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 32)
            .background(AppColors.border)
    }

    private func detailChip(_ label: String, color: Color) -> some View {
        Text(label)
            .podTextStyle(.label, color: color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.11))
            .clipShape(Capsule())
    }

    private func price(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "$\(String(format: "%.2f", value))"
    }

    private func pnlColor(_ value: Double?) -> Color {
        guard let value else { return AppColors.textTertiary }
        return value >= 0 ? AppColors.accentSuccess : AppColors.accentDanger
    }

    private func deskStatusColor(_ status: String) -> Color {
        let normalized = status.lowercased()
        if normalized.contains("active") || normalized.contains("available") || normalized.contains("ok") {
            return AppColors.accentSuccess
        }
        if normalized.contains("block") || normalized.contains("error") || normalized.contains("fail") {
            return AppColors.accentDanger
        }
        return AppColors.accentWarning
    }

    private func qualityColor(_ quality: String) -> Color {
        switch quality.lowercased() {
        case "available": return AppColors.accentSuccess
        case "stale", "degraded": return AppColors.accentWarning
        case "malformed", "unavailable": return AppColors.accentDanger
        default: return AppColors.textTertiary
        }
    }
}

private struct FundTradesStageChip: View {
    let stage: FundTradesStage

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: stage.icon)
                .font(.system(size: 10, weight: .bold))
            Text(stage.label.uppercased())
                .podTextStyle(.label, color: color)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.45), lineWidth: 1)
        )
    }

    private var color: Color {
        switch stage {
        case .paper: return AppColors.textSecondary
        case .trialLive: return AppColors.accentWarning
        case .scaleLive: return AppColors.accentSuccess
        }
    }
}

#if DEBUG
#Preview("Fund Trades Card - Synthetic") {
    ScrollView {
        FundTradesCard(
            viewModel: FundTradesViewModel(initialFeed: .synthAvailablePreview)
        )
        .padding()
    }
    .background(AppColors.backgroundPrimary)
}

#Preview("Fund Trades Card - Malformed") {
    ScrollView {
        FundTradesCard(
            viewModel: FundTradesViewModel(initialFeed: .synthMalformedPreview)
        )
        .padding()
    }
    .background(AppColors.backgroundPrimary)
}

#Preview("Fund Trades Detail - Synthetic") {
    FundTradesDetailSheet(
        feed: .synthAvailablePreview,
        isLoading: false,
        errorMessage: nil,
        onRefresh: {}
    )
}
#endif
