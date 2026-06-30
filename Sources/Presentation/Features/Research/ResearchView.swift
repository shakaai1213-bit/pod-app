import SwiftUI

struct ResearchView: View {
    @State private var viewModel = ResearchViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Topic filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.topics, id: \.self) { topic in
                        Button {
                            viewModel.selectedTopic = (viewModel.selectedTopic == topic) ? nil : topic
                            Task { await viewModel.loadFindings() }
                        } label: {
                            Text(topic)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.selectedTopic == topic ? Color.purple.opacity(0.3) : Color.gray.opacity(0.2))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(AppColors.backgroundPrimary)
            
            Divider()

            if !viewModel.findings.isEmpty {
                freshnessHeader
            }
            
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                Text("Error: \(error)").foregroundColor(.red)
                Spacer()
            } else if viewModel.findings.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                List(viewModel.findings) { finding in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(finding.topic)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                            Spacer()
                            Text(finding.confidence)
                                .font(.caption2)
                                .foregroundColor(AppColors.textTertiary)
                        }
                        Text(finding.content)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textPrimary)
                        if let source = finding.sourceTitle {
                            Text("Source: \(source)")
                                .font(.caption2)
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Research")
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .refreshable {
            await viewModel.loadFindings(showLoading: false)
        }
    }

    private var freshnessHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundColor(AppColors.textTertiary)
            Text(freshnessText)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.backgroundPrimary)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(AppColors.textTertiary)
            Text(emptyStateTitle)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            if let detail = emptyStateDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }

    private var freshnessText: String {
        var parts: [String] = []
        if let latestFindingAt = viewModel.latestFindingAt {
            parts.append("Latest finding \(latestFindingAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if let lastRefreshedAt = viewModel.lastRefreshedAt {
            parts.append("refreshed \(lastRefreshedAt.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " | ")
    }

    private var emptyStateTitle: String {
        if let selectedTopic = viewModel.selectedTopic {
            return "No research findings for \(selectedTopic)"
        }
        return "Research flywheel metadata unavailable"
    }

    private var emptyStateDetail: String? {
        if viewModel.selectedTopic != nil {
            return "Try another topic or pull to refresh."
        }
        if let lastRefreshedAt = viewModel.lastRefreshedAt {
            return "Last checked \(lastRefreshedAt.formatted(date: .abbreviated, time: .shortened))."
        }
        return "No Workbench research-flywheel rows were returned by ORCA."
    }
}
