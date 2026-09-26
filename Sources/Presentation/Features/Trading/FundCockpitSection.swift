import SwiftUI

struct FundCockpitSection: View {
    let viewModel: FundCockpitViewModel

    private var payload: FundCockpitPayloadDTO? {
        guard viewModel.feed?.isAvailable == true,
              viewModel.feed?.data?.schemaVersion == "fund_routes_cockpit/v0",
              viewModel.feed?.data?.route == "fund.cockpit" else { return nil }
        return viewModel.feed?.data?.payload
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            HStack(spacing: Theme.xs) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(AppColors.accentElectric)
                Text("Fund cockpit")
                    .podTextStyle(.headline, color: AppColors.textPrimary)
                Spacer(minLength: 0)
                if viewModel.isLoading && viewModel.feed == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Text(feedLabel)
                        .podTextStyle(.label, color: feedLabel == "CURRENT"
                            ? AppColors.accentSuccess : AppColors.accentWarning)
                }
            }

            if let payload {
                HStack(spacing: Theme.md) {
                    metric("Engines", value: "\(payload.engines.rows.count)")
                    metric("ORCA sync", value: payload.orcaSync.map { "\($0.inSync)/\($0.total)" } ?? "-")
                    metric("Shadows", value: count(payload.shadows?.candidates.count))
                    metric("Alerts", value: "\(payload.alerts.count)")
                }

                HStack(spacing: Theme.md) {
                    metric("Predictors", value: count(payload.predictors?.predictors.count))
                    metric("Research queue", value: payload.chieffish?.pendingBefore.map(String.init) ?? "-")
                    metric("Runs captured", value: count(payload.runCapture?.symbols.values.filter { $0.runDetected == true }.count))
                }

                if let problems = payload.orcaSync?.problems, !problems.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        Text("ORCA SYNC NEEDS ATTENTION")
                            .podTextStyle(.label, color: AppColors.accentWarning)
                        ForEach(Array(problems.prefix(4).enumerated()), id: \.offset) { _, problem in
                            HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
                                Text(problem.surface ?? "Unknown route")
                                    .podTextStyle(.caption, color: AppColors.textSecondary)
                                    .lineLimit(1)
                                Spacer(minLength: Theme.xs)
                                Text(problem.verdict ?? "check")
                                    .podTextStyle(.label, color: AppColors.accentWarning)
                                    .lineLimit(1)
                            }
                        }
                        if problems.count > 4 {
                            Text("\(problems.count - 4) more feed checks need attention")
                                .podTextStyle(.caption, color: AppColors.textTertiary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("ENGINE HEALTH")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                    ForEach(Array(payload.engines.rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
                            Text(row.engine)
                                .podTextStyle(.body, color: AppColors.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: Theme.xs)
                            Text(row.verdict)
                                .podTextStyle(.label, color: AppColors.textSecondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                        Divider().background(AppColors.border)
                    }
                }

                if let predictors = payload.predictors?.predictors, !predictors.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        Text("PREDICTORS")
                            .podTextStyle(.label, color: AppColors.textTertiary)
                        ForEach(predictors.keys.sorted(), id: \.self) { key in
                            if let predictor = predictors[key] {
                                HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
                                    Text(predictor.label ?? key)
                                        .podTextStyle(.caption, color: AppColors.textSecondary)
                                        .lineLimit(1)
                                    Spacer(minLength: Theme.xs)
                                    Text(predictorRead(predictor))
                                        .podTextStyle(.label, color: AppColors.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                if !payload.execution.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        Text("EXECUTION SERVICES")
                            .podTextStyle(.label, color: AppColors.textTertiary)
                        ForEach(Array(payload.execution.enumerated()), id: \.offset) { _, service in
                            HStack(spacing: Theme.sm) {
                                Circle()
                                    .fill(service.alive ? AppColors.accentSuccess : AppColors.accentDanger)
                                    .frame(width: 7, height: 7)
                                Text(service.label)
                                    .podTextStyle(.caption, color: AppColors.textSecondary)
                                Spacer(minLength: 0)
                                Text(service.alive ? "running" : "offline")
                                    .podTextStyle(.label, color: service.alive
                                        ? AppColors.accentSuccess : AppColors.accentDanger)
                            }
                        }
                    }
                }

                if !payload.alerts.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        Text("ALERTS")
                            .podTextStyle(.label, color: AppColors.textTertiary)
                        ForEach(Array(payload.alerts.enumerated()), id: \.offset) { _, alert in
                            HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
                                Text(alert.name)
                                    .podTextStyle(.caption, color: AppColors.textSecondary)
                                Spacer(minLength: Theme.xs)
                                Text(alert.severity.uppercased())
                                    .podTextStyle(.label, color: AppColors.accentWarning)
                            }
                        }
                    }
                }

                Text("ORCA - \(FundTradesFormat.relativeTime(viewModel.feed?.displayAsOf))")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            } else {
                Text(viewModel.errorMessage ?? "Waiting for the protected ORCA cockpit feed.")
                    .podTextStyle(.caption, color: AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Theme.md)
        .accessibilityIdentifier("fund-cockpit-section")
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .podTextStyle(.label, color: AppColors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feedLabel: String {
        guard viewModel.feed?.isAvailable == true else { return "CHECK FEED" }
        return payload?.orcaSync?.problems.isEmpty == false ? "PARTIAL" : "CURRENT"
    }

    private func count(_ value: Int?) -> String {
        value.map(String.init) ?? "-"
    }

    private func predictorRead(_ predictor: FundCockpitPredictorDTO) -> String {
        let skill = predictor.skill?.replacingOccurrences(of: "_", with: " ").uppercased()
            ?? predictor.verdict
            ?? "pending"
        guard predictor.baselineKind == "random",
              let accuracy = predictor.accuracy,
              let baseline = predictor.randomBaseline else {
            return skill
        }
        return "\(skill) - \(Int((accuracy * 100).rounded()))% vs \(Int((baseline * 100).rounded()))% random"
    }
}
