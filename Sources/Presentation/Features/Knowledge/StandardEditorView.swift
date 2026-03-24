import SwiftUI

// MARK: - Standard Editor Mode

enum StandardEditorMode: Hashable {
    case create
    case edit(Standard)

    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }
}

// MARK: - Standard Editor View

struct StandardEditorView: View {

    let mode: StandardEditorMode
    @Bindable var viewModel: KnowledgeViewModel

    @Environment(\.dismiss) private var dismiss

    // State
    @State private var title: String = ""
    @State private var category: StandardCategory = .standards
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var content: String = ""
    @State private var showPreview: Bool = false
    @State private var relatedStandardIds: Set<UUID> = []
    @State private var relatedSearch: String = ""
    @State private var showRelatedPicker: Bool = false
    @State private var isSaving: Bool = false
    @State private var isPublishing: Bool = false
    @State private var errorMessage: String?

    // Init from edit mode
    private var existingStandard: Standard? {
        if case .edit(let s) = mode { return s }
        return nil
    }

    init(mode: StandardEditorMode, viewModel: KnowledgeViewModel) {
        self.mode = mode
        self.viewModel = viewModel
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    titleSection
                    categorySection
                    tagsSection
                    contentSection

                    relatedSection

                    errorSection
                }
                .padding(Theme.md)
                .padding(.bottom, 120)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle(mode.isEditing ? "Edit Standard" : "New Standard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.textSecondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Theme.sm) {
                        if !showPreview {
                            Button("Preview") {
                                withAnimation { showPreview = true }
                            }
                            .foregroundColor(AppColors.accentElectric)
                        } else {
                            Button("Edit") {
                                withAnimation { showPreview = false }
                            }
                            .foregroundColor(AppColors.accentElectric)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
            .sheet(isPresented: $showRelatedPicker) {
                RelatedStandardPickerView(
                    selectedIds: $relatedStandardIds,
                    allStandards: viewModel.standards,
                    currentStandardId: existingStandard?.id
                )
            }
            .onAppear {
                loadExisting()
            }
        }
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text("Title")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textSecondary)

            TextField("Enter standard title…", text: $title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary)
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Category Section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text("Category")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: Theme.xs) {
                ForEach(StandardCategory.allCases, id: \.self) { cat in
                    Button {
                        withAnimation { category = cat }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 12, weight: .semibold))

                            Text(cat.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(category == cat ? Color(hexString: cat.color) : AppColors.textSecondary)
                        .padding(.horizontal, Theme.sm)
                        .padding(.vertical, Theme.xs)
                        .background(
                            category == cat
                                ? Color(hexString: cat.color).opacity(0.15)
                                : AppColors.backgroundTertiary
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    category == cat ? Color(hexString: cat.color) : AppColors.border,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text("Tags")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textSecondary)

            VStack(alignment: .leading, spacing: Theme.xs) {
                // Existing tags
                if !tags.isEmpty {
                    FlowLayout(horizontalSpacing: Theme.xs, verticalSpacing: Theme.xs) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(tag: tag) {
                                withAnimation { tags.removeAll { $0 == tag } }
                            }
                        }
                    }
                }

                // Input
                HStack(spacing: Theme.xs) {
                    TextField("Add tag…", text: $tagInput)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.horizontal, Theme.sm)
                        .padding(.vertical, Theme.xs)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                        .onSubmit {
                            addTag()
                        }

                    if !tagInput.isEmpty {
                        Button {
                            addTag()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AppColors.accentElectric)
                        }
                    }
                }
            }
        }
    }

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        withAnimation { tags.append(trimmed) }
        tagInput = ""
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text("Content")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textSecondary)

            if showPreview {
                // Preview mode
                ScrollView {
                    MarkdownRenderer(content: content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.sm)
                }
                .frame(minHeight: 300)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            } else {
                // Edit mode
                VStack(spacing: 0) {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(AppColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(Theme.sm)
                        .frame(minHeight: 300)
                        .background(AppColors.backgroundSecondary)

                    MarkdownToolbar(content: $content)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Related Section

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            HStack {
                Text("Related Standards")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                Button {
                    showRelatedPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))

                        Text("Add")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(AppColors.accentElectric)
                }
            }

            if relatedStandardIds.isEmpty {
                Text("No related standards selected")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.xs)
            } else {
                let related = viewModel.standards.filter { relatedStandardIds.contains($0.id) }
                LazyVStack(spacing: Theme.xxs) {
                    ForEach(related) { standard in
                        RelatedEditorRow(standard: standard) {
                            relatedStandardIds.remove(standard.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Error Section

    private var errorSection: some View {
        Group {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.accentDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppColors.border)

            HStack(spacing: Theme.sm) {
                if mode.isEditing {
                    Button {
                        Task { await deleteStandard() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppColors.accentDanger)
                            .frame(width: 44, height: 44)
                            .background(AppColors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    }
                }

                Button {
                    Task { await saveDraft() }
                } label: {
                    Text(mode.isEditing ? "Save Draft" : "Save Draft")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.sm)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                }
                .disabled(title.isEmpty || isSaving || isPublishing)

                Button {
                    Task { await publish() }
                } label: {
                    HStack(spacing: 4) {
                        if isPublishing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12))

                            Text("Publish")
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.sm)
                    .background(title.isEmpty ? AppColors.textTertiary : AppColors.accentElectric)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .disabled(title.isEmpty || isPublishing || isSaving)
            }
            .padding(.horizontal, Theme.md)
            .padding(.vertical, Theme.sm)
            .background(AppColors.backgroundSecondary)
        }
    }

    // MARK: - Helpers

    private func loadExisting() {
        if let standard = existingStandard {
            title = standard.title
            category = standard.category
            tags = standard.tags
            content = standard.content
            relatedStandardIds = Set(standard.relatedStandardIds)
        }
    }

    private func buildStandard() -> Standard {
        let now = Date()
        return Standard(
            id: existingStandard?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            content: content,
            authorId: existingStandard?.authorId ?? UUID(),
            authorName: existingStandard?.authorName ?? "You",
            tags: tags,
            version: existingStandard.map { $0.version } ?? 1,
            createdAt: existingStandard?.createdAt ?? now,
            updatedAt: now,
            isFavorite: existingStandard?.isFavorite ?? false,
            relatedStandardIds: Array(relatedStandardIds),
            versions: existingStandard?.versions ?? []
        )
    }

    private func saveDraft() async {
        guard !title.isEmpty else { return }
        isSaving = true
        errorMessage = nil

        let standard = buildStandard()
        let success: Bool

        if mode.isEditing {
            success = await viewModel.updateStandard(standard)
        } else {
            success = await viewModel.createStandard(standard)
        }

        await MainActor.run {
            isSaving = false
            if success {
                dismiss()
            } else {
                errorMessage = viewModel.errorMessage ?? "Failed to save"
            }
        }
    }

    private func publish() async {
        guard !title.isEmpty else { return }
        isPublishing = true
        errorMessage = nil

        let standard = buildStandard()
        if mode.isEditing {
            let updated = await viewModel.updateStandard(standard)
            await MainActor.run {
                isPublishing = false
                if updated { dismiss() }
                else { errorMessage = viewModel.errorMessage ?? "Failed to publish" }
            }
        } else {
            let created = await viewModel.createStandard(standard)
            await MainActor.run {
                isPublishing = false
                if created { dismiss() }
                else { errorMessage = viewModel.errorMessage ?? "Failed to publish" }
            }
        }
    }

    private func deleteStandard() async {
        guard let id = existingStandard?.id else { return }
        let deleted = await viewModel.deleteStandard(id: id)
        if deleted {
            await MainActor.run { dismiss() }
        }
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, Theme.xs)
        .padding(.vertical, 4)
        .background(AppColors.backgroundTertiary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

// MARK: - Markdown Toolbar

struct MarkdownToolbar: View {
    @Binding var content: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.xs) {
                ToolbarButton(icon: "bold", label: "B") {
                    wrapSelection(prefix: "**", suffix: "**")
                }

                ToolbarButton(icon: "italic", label: "I") {
                    wrapSelection(prefix: "*", suffix: "*")
                }

                ToolbarButton(icon: "chevron.left.forwardslash.chevron.right", label: nil) {
                    wrapSelection(prefix: "`", suffix: "`")
                }

                ToolbarButton(icon: "link", label: nil) {
                    insertLink()
                }

                ToolbarButton(icon: "number", label: nil) {
                    insertHeader()
                }

                ToolbarButton(icon: "list.bullet", label: nil) {
                    insertList()
                }

                ToolbarButton(icon: "text.quote", label: nil) {
                    insertCodeBlock()
                }
            }
            .padding(.horizontal, Theme.sm)
            .padding(.vertical, Theme.xs)
        }
        .background(AppColors.backgroundTertiary)
    }

    private func wrapSelection(prefix: String, suffix: String) {
        content += "\(prefix)text\(suffix)"
    }

    private func insertLink() {
        content += "[link text](url)"
    }

    private func insertHeader() {
        content += "\n## Heading\n"
    }

    private func insertList() {
        content += "\n- item\n"
    }

    private func insertCodeBlock() {
        content += "\n```\ncode\n```\n"
    }
}

// MARK: - Toolbar Button

struct ToolbarButton: View {
    let icon: String
    let label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let label = label {
                    Text(label)
                        .font(.system(size: 14, weight: .bold, design: .default))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundColor(AppColors.textSecondary)
            .frame(width: 36, height: 32)
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

// MARK: - Related Editor Row

struct RelatedEditorRow: View {
    let standard: Standard
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Theme.sm) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hexString: standard.category.color))
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(standard.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                Text(standard.category.displayName)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, Theme.xs)
        .padding(.vertical, Theme.xxs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

// MARK: - Related Standard Picker

struct RelatedStandardPickerView: View {
    @Binding var selectedIds: Set<UUID>
    let allStandards: [Standard]
    let currentStandardId: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredStandards: [Standard] {
        let candidates = allStandards.filter { $0.id != currentStandardId }
        if searchText.isEmpty {
            return candidates
        }
        let query = searchText.lowercased()
        return candidates.filter {
            $0.title.lowercased().contains(query) ||
            $0.category.displayName.lowercased().contains(query) ||
            $0.tags.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack(spacing: Theme.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textTertiary)

                    TextField("Search standards…", text: $searchText)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textPrimary)
                        .tint(AppColors.accentElectric)
                }
                .padding(.horizontal, Theme.sm)
                .padding(.vertical, Theme.xs)
                .background(AppColors.backgroundTertiary)

                // List
                ScrollView {
                    LazyVStack(spacing: Theme.xxs) {
                        ForEach(filteredStandards) { standard in
                            RelatedPickerRow(
                                standard: standard,
                                isSelected: selectedIds.contains(standard.id)
                            ) {
                                if selectedIds.contains(standard.id) {
                                    selectedIds.remove(standard.id)
                                } else {
                                    selectedIds.insert(standard.id)
                                }
                            }
                        }
                    }
                    .padding(Theme.sm)
                }
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Related Standards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppColors.accentElectric)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Related Picker Row

struct RelatedPickerRow: View {
    let standard: Standard
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Theme.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? AppColors.accentElectric : AppColors.textTertiary)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hexString: standard.category.color))
                    .frame(width: 3, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(standard.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: standard.category.icon)
                            .font(.system(size: 9))
                            .foregroundColor(Color(hexString: standard.category.color))

                        Text(standard.category.displayName)
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                Spacer()
            }
            .padding(Theme.sm)
            .background(isSelected ? AppColors.accentElectric.opacity(0.08) : AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .stroke(isSelected ? AppColors.accentElectric : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    StandardEditorView(
        mode: .create,
        viewModel: KnowledgeViewModel()
    )
    .preferredColorScheme(.dark)
}
