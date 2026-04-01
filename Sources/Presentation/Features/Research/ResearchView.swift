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
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(AppColors.textTertiary)
                    Text("No research findings yet")
                        .foregroundColor(AppColors.textSecondary)
                    Text("Starfish is working on it...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
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
            Task { await viewModel.loadFindings() }
        }
        .refreshable {
            await viewModel.loadFindings()
        }
    }
}
