import SwiftUI

struct SystemView: View {
    @State private var viewModel = SystemViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.md) {
                        if let errorMessage = viewModel.errorMessage {
                            errorBanner(errorMessage)
                        }

                        digestSection
                        runtimeSection
                        boardsSection
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.top, Theme.lg)
                    .padding(.bottom, Theme.xxl * 2)
                }
                .refreshable {
                    await viewModel.refresh()
                }

                if viewModel.isLoading && viewModel.digest == nil && viewModel.runtimeRegistry == nil && viewModel.boards.isEmpty {
                    ProgressView()
                        .tint(AppColors.accentElectric)
                        .scaleEffect(1.2)
                }
            }
            .navigationTitle("System")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(AppColors.accentElectric)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                if viewModel.digest == nil && viewModel.runtimeRegistry == nil && viewModel.boards.isEmpty {
                    await viewModel.load()
                }
            }
        }
    }

    private var digestSection: some View {
        section(title: "Control Room", systemImage: "waveform.path.ecg") {
            if let digest = viewModel.digest {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack(spacing: Theme.sm) {
                        statusPill(digest.status)
                        metric(label: "Signals", value: "\(digest.signalCount)")
                        Spacer(minLength: Theme.xs)
                    }

                    if let generatedAt = digest.generatedAt {
                        Text("Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    ForEach(digest.sections.prefix(5)) { section in
                        VStack(alignment: .leading, spacing: Theme.xxs) {
                            HStack(spacing: Theme.xs) {
                                Text(section.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                if let status = section.status {
                                    Text(status.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(statusColor(status))
                                }
                            }
                            if let summary = section.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .lineLimit(3)
                            }
                            ForEach(section.items.prefix(3), id: \.self) { item in
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.top, Theme.xxs)
                    }
                }
            } else {
                emptyState("Digest unavailable.")
            }
        }
    }

    private var runtimeSection: some View {
        section(title: "Runtime Registry", systemImage: "server.rack") {
            if let registry = viewModel.runtimeRegistry {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack(spacing: Theme.sm) {
                        metric(label: "Components", value: "\(registry.summary.total)")
                        ForEach(registry.summary.byStatus.sorted(by: { $0.key < $1.key }).prefix(3), id: \.key) { status, count in
                            metric(label: status.displayLabel, value: "\(count)")
                        }
                        Spacer(minLength: Theme.xs)
                    }

                    ForEach(registry.items.prefix(20)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
                            VStack(alignment: .leading, spacing: Theme.xxs) {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                Text([item.kind, item.owner].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: Theme.xs)
                            statusPill(item.status)
                        }
                        .padding(.vertical, Theme.xxs)
                    }
                }
            } else {
                emptyState("Runtime registry unavailable.")
            }
        }
    }

    private var boardsSection: some View {
        section(title: "Boards", systemImage: "rectangle.3.group") {
            if !viewModel.boards.isEmpty {
                VStack(spacing: Theme.xs) {
                    ForEach(viewModel.boards) { board in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
                            Text(board.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: Theme.xs)
                            metric(label: "Agents", value: "\(board.agentCount)")
                            metric(label: "Projects", value: "\(board.activeProjectCount)")
                            metric(label: "Tickets", value: "\(board.ticketCount)")
                        }
                        .padding(.vertical, Theme.xxs)
                    }
                }
            } else {
                emptyState("Boards unavailable.")
            }
        }
    }

    private func section<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(spacing: Theme.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentElectric)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
            }
            content()
        }
        .podCard(padding: Theme.md)
    }

    private func statusPill(_ status: String) -> some View {
        Text(status.displayLabel.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, Theme.xs)
            .padding(.vertical, Theme.xxs)
            .background(statusColor(status).opacity(0.14))
            .clipShape(Capsule())
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppColors.textPrimary)
            Text(label.displayLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .fixedSize()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.accentWarning)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: Theme.xs)
        }
        .padding(Theme.sm)
        .background(AppColors.accentWarning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.sm)
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "ok", "ready", "running", "active", "loaded", "healthy", "green":
            return AppColors.accentSuccess
        case "warning", "warn", "degraded", "stale", "yellow":
            return AppColors.accentWarning
        case "error", "failed", "down", "critical", "red":
            return AppColors.accentDanger
        default:
            return AppColors.textSecondary
        }
    }
}

private extension String {
    var displayLabel: String {
        replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
