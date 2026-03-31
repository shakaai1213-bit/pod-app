import SwiftUI

// MARK: - Search Sheet

struct SearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var recentSearches: [String] = [
        "authentication flow",
        "backend API",
        "agent status",
    ]

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    recentSection
                } else if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else {
                    resultsSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search agents, tasks, messages...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var recentSection: some View {
        Section("Recent Searches") {
            ForEach(recentSearches, id: \.self) { query in
                Button {
                    searchText = query
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(AppColors.textTertiary)
                        Text(query)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var resultsSection: some View {
        Section("Results") {
            Text("Search results for \"\(searchText)\"")
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Theme.lg)
        }
    }
}

#Preview {
    SearchSheet()
        .preferredColorScheme(.dark)
}
