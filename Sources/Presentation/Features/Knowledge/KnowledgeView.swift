import SwiftUI

// MARK: - Knowledge View

struct KnowledgeView: View {

    @State private var viewModel = KnowledgeViewModel()
    @State private var showingEditor = false
    @State private var editingStandard: Standard?
    @State private var selectedStandard: Standard?
    @State private var searchText = ""

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: Theme.lg) {
                        searchBar

                        categoryGrid

                        if !viewModel.recentStandards.isEmpty {
                            recentSection
                        }

                        if !viewModel.favoriteStandards.isEmpty {
                            favoritesSection
                        }

                        standardsList
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.bottom, 100)
                }
                .background(AppColors.backgroundPrimary)
                .refreshable {
                    await viewModel.loadStandards()
                }

                // FAB
                fabButton
            }
            .navigationTitle("Knowledge")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
            .navigationDestination(item: $selectedStandard) { standard in
                StandardDetailView(standard: standard, viewModel: viewModel)
            }
            .sheet(isPresented: $showingEditor) {
                StandardEditorView(
                    mode: .create,
                    viewModel: viewModel
                )
            }
            .sheet(item: $editingStandard) { standard in
                StandardEditorView(
                    mode: .edit(standard),
                    viewModel: viewModel
                )
            }
            .task {
                await viewModel.loadStandards()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.textTertiary)

            TextField("Search standards, tags, authors…", text: $searchText)
                .font(.subheadline)
                .foregroundColor(AppColors.textPrimary)
                .tint(AppColors.accentElectric)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, newValue in
                    viewModel.searchText = newValue
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, Theme.sm)
        .padding(.vertical, Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Theme.sm),
                GridItem(.flexible(), spacing: Theme.sm),
            ],
            spacing: Theme.sm
        ) {
            ForEach(StandardCategory.allCases, id: \.self) { category in
                CategoryCard(
                    category: category,
                    count: viewModel.categoryCounts[category] ?? 0,
                    isSelected: viewModel.selectedCategory == category
                ) {
                    withAnimation(Animation.easeInOut) {
                        if viewModel.selectedCategory == category {
                            viewModel.selectedCategory = nil
                        } else {
                            viewModel.selectedCategory = category
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent Section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Recent")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.sm) {
                    ForEach(viewModel.recentStandards) { standard in
                        RecentStandardCard(standard: standard) {
                            selectedStandard = standard
                        }
                    }
                }
            }
        }
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.accentWarning)

                Text("Favorites")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.sm) {
                    ForEach(viewModel.favoriteStandards) { standard in
                        FavoriteStandardCard(standard: standard) {
                            selectedStandard = standard
                        }
                    }
                }
            }
        }
    }

    // MARK: - Standards List

    private var standardsList: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Text(viewModel.selectedCategory?.displayName ?? "All Standards")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text("\(viewModel.filteredStandards.count)")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textTertiary)
            }

            if viewModel.isLoading && viewModel.standards.isEmpty {
                loadingView
            } else if viewModel.filteredStandards.isEmpty {
                emptyView
            } else {
                LazyVStack(spacing: Theme.xs) {
                    ForEach(viewModel.filteredStandards) { standard in
                        StandardRowView(standard: standard) {
                            selectedStandard = standard
                        } onFavorite: {
                            Task {
                                await viewModel.toggleFavorite(id: standard.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            showingEditor = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(AppColors.accentElectric)
                .clipShape(Circle())
                .podShadow(Theme.ShadowConfig.medium)
        }
        .padding(.trailing, Theme.md)
        .padding(.bottom, Theme.md)
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(AppColors.accentElectric)
            Spacer()
        }
        .frame(height: 200)
    }

    private var emptyView: some View {
        VStack(spacing: Theme.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textTertiary)

            Text("No standards found")
                .font(.headline)
                .foregroundColor(AppColors.textSecondary)

            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.xxl)
    }
}

// MARK: - Category Card

private struct CategoryCard: View {
    let category: StandardCategory
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.xs) {
                HStack {
                    Image(systemName: category.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? Color(hexString: category.color) : AppColors.textSecondary)

                    Spacer()

                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? Color(hexString: category.color) : AppColors.textTertiary)
                }

                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            }
            .padding(Theme.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(isSelected ? Color(hexString: category.color).opacity(0.15) : AppColors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(isSelected ? Color(hexString: category.color) : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Standard Card

private struct RecentStandardCard: View {
    let standard: Standard
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.xxs) {
                HStack(spacing: Theme.xxs) {
                    Image(systemName: standard.category.icon)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hexString: standard.category.color))

                    Text(standard.category.displayName)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                }

                Text(standard.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(Theme.sm)
            .frame(width: 140, alignment: .leading)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Favorite Standard Card

private struct FavoriteStandardCard: View {
    let standard: Standard
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.xxs) {
                HStack(spacing: Theme.xxs) {
                    Image(systemName: standard.category.icon)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hexString: standard.category.color))

                    Text(standard.category.displayName)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(AppColors.accentWarning)
                }

                Text(standard.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(Theme.sm)
            .frame(width: 140, alignment: .leading)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Standard Row View

struct StandardRowView: View {
    let standard: Standard
    let onTap: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.sm) {
                // Category indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hexString: standard.category.color))
                    .frame(width: 4, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(standard.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: Theme.xs) {
                        CategoryBadge(category: standard.category)

                        Text("•")
                            .foregroundColor(AppColors.textTertiary)
                            .font(.caption2)

                        Text(standard.authorName)
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)

                        Text("•")
                            .foregroundColor(AppColors.textTertiary)
                            .font(.caption2)

                        Text(standard.updatedAt.shortDateString)
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }

                    if !standard.tags.isEmpty {
                        HStack(spacing: Theme.xxs) {
                            ForEach(standard.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColors.backgroundTertiary)
                                    .clipShape(Capsule())
                            }
                            if standard.tags.count > 3 {
                                Text("+\(standard.tags.count - 3)")
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                    }
                }

                Spacer()

                Button(action: onFavorite) {
                    Image(systemName: standard.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(standard.isFavorite ? AppColors.accentWarning : AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Badge

struct CategoryBadge: View {
    let category: StandardCategory

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.icon)
                .font(.system(size: 8, weight: .semibold))

            Text(category.displayName)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(Color(hexString: category.color))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(hexString: category.color).opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Date Extensions

extension Date {
    var shortDateString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var versionDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - Preview

#Preview {
    KnowledgeView()
        .preferredColorScheme(.dark)
}
