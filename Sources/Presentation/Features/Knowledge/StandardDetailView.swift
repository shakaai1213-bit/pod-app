import SwiftUI

// MARK: - Standard Detail View

struct StandardDetailView: View {

    let standard: Standard
    @Bindable var viewModel: KnowledgeViewModel

    @State private var currentStandard: Standard
    @State private var isFavorite: Bool
    @State private var showingAskAgent = false
    @State private var askAgentPrompt = ""
    @Environment(\.dismiss) private var dismiss

    init(standard: Standard, viewModel: KnowledgeViewModel) {
        self.standard = standard
        self.viewModel = viewModel
        self._currentStandard = State(initialValue: standard)
        self._isFavorite = State(initialValue: standard.isFavorite)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    headerSection
                    tagsSection
                    contentSection

                    if !viewModel.relatedStandards(for: currentStandard).isEmpty {
                        relatedSection
                    }

                    if !currentStandard.versions.isEmpty {
                        versionHistorySection
                    }

                    bottomSpacer
                }
                .padding(.horizontal, Theme.md)
                .padding(.top, Theme.sm)
            }
            .background(AppColors.backgroundPrimary)
            .refreshable {
                if let updated = await viewModel.loadStandard(id: currentStandard.id) {
                    currentStandard = updated
                }
            }

            stickyBottomBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: Theme.sm) {
                    Button {
                        Task {
                            await viewModel.toggleFavorite(id: currentStandard.id)
                            isFavorite.toggle()
                        }
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isFavorite ? AppColors.accentWarning : AppColors.textSecondary)
                    }

                    ShareLink(
                        item: "[\(currentStandard.title)]",
                        subject: Text(currentStandard.title),
                        message: Text(currentStandard.content)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        // Edit
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button {
                        Task {
                            _ = await viewModel.deleteStandard(id: currentStandard.id)
                            dismiss()
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(AppColors.accentDanger)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showingAskAgent) {
            AskAgentSheet(
                standard: currentStandard,
                prompt: $askAgentPrompt
            )
        }
        .task {
            if let updated = await viewModel.loadStandard(id: currentStandard.id) {
                currentStandard = updated
                isFavorite = updated.isFavorite
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(currentStandard.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(AppColors.textPrimary)

            HStack(spacing: Theme.sm) {
                CategoryBadge(category: currentStandard.category)

                Text("•")
                    .foregroundColor(AppColors.textTertiary)

                Text(currentStandard.authorName)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)

                Text("•")
                    .foregroundColor(AppColors.textTertiary)

                Text(currentStandard.updatedAt.shortDateString)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)

                Text("• v\(currentStandard.version)")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        Group {
            if !currentStandard.tags.isEmpty {
                FlowLayout(spacing: Theme.xs) {
                    ForEach(currentStandard.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
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
            }
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Content")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            MarkdownRenderer(content: currentStandard.content)
        }
    }

    // MARK: - Related Standards

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Related Standards")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            let related = viewModel.relatedStandards(for: currentStandard)
            LazyVStack(spacing: Theme.xs) {
                ForEach(related) { relatedStandard in
                    RelatedStandardCard(standard: relatedStandard)
                }
            }
        }
    }

    // MARK: - Version History

    private var versionHistorySection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Version History")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            VStack(spacing: 0) {
                ForEach(currentStandard.versions.sorted { $0.version > $1.version }) { version in
                    VersionRow(version: version)

                    if version.id != currentStandard.versions.last?.id {
                        Divider()
                            .background(AppColors.border)
                    }
                }
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Bottom

    private var bottomSpacer: some View {
        Color.clear.frame(height: 100)
    }

    // MARK: - Sticky Bottom Bar

    private var stickyBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppColors.border)

            HStack(spacing: Theme.sm) {
                Button {
                    showingAskAgent = true
                } label: {
                    HStack(spacing: Theme.xs) {
                        Image(systemName: "brain")
                            .font(.system(size: 14, weight: .semibold))

                        Text("Ask an Agent")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.sm)
                    .background(AppColors.accentAgent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
            }
            .padding(.horizontal, Theme.md)
            .padding(.vertical, Theme.sm)
            .background(AppColors.backgroundSecondary)
        }
    }
}

// MARK: - Markdown Renderer

struct MarkdownRenderer: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            ForEach(Array(parseMarkdown(content).enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block.type {
        case .heading1:
            Text(block.text)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(AppColors.textPrimary)

        case .heading2:
            Text(block.text)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary)

        case .heading3:
            Text(block.text)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary)

        case .codeBlock:
            codeBlockContent(block.text)

        case .listItem:
            HStack(alignment: .top, spacing: Theme.xs) {
                Text("•")
                    .font(.subheadline)
                    .foregroundColor(AppColors.accentElectric)
                    .frame(width: 16, alignment: .leading)

                Text(attributedText(block.text, isCode: false))
                    .font(.subheadline)
                    .foregroundColor(AppColors.textPrimary)
            }

        case .paragraph:
            Text(attributedText(block.text, isCode: false))
                .font(.subheadline)
                .foregroundColor(AppColors.textPrimary)
        }
    }

    private func codeBlockContent(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(AppColors.accentSuccess)
                .padding(Theme.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func attributedText(_ text: String, isCode: Bool) -> AttributedString {
        var result = AttributedString(text)

        // Inline code: `code`
        let codePattern = "`([^`]+)`"
        if let regex = try? NSRegularExpression(pattern: codePattern) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: nsRange).reversed()

            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let codeStr = String(text[range])
                    let startIndex = text.index(text.startIndex, offsetBy: match.range(at: 0).location)
                    let endIndex = text.index(text.startIndex, offsetBy: match.range(at: 0).location + match.range(at: 0).length)

                    if let attrStart = AttributedString.Index(startIndex, within: result),
                       let attrEnd = AttributedString.Index(endIndex, within: result) {
                        var code = AttributedString(codeStr)
                        code.foregroundColor = AppColors.accentSuccess
                        code.font = .system(.footnote, design: .monospaced)
                        result.replaceSubrange(attrStart..<attrEnd, with: code)
                    }
                }
            }
        }

        // Bold: **text**
        let boldPattern = "\\*\\*([^*]+)\\*\\*"
        if let regex = try? NSRegularExpression(pattern: boldPattern) {
            let nsRange = NSRange(result.characters.startIndex..., in: String(result.characters))
            let matches = regex.matches(in: String(result.characters), range: nsRange).reversed()

            for match in matches {
                if let range = Range(match.range(at: 1), in: String(result.characters)) {
                    let boldText = String(String(result.characters)[range])
                    if let attrStart = AttributedString.Index(range.lowerBound, within: result),
                       let attrEnd = AttributedString.Index(range.upperBound, within: result) {
                        var bold = AttributedString(boldText)
                        bold.foregroundColor = AppColors.textPrimary
                        bold.font = .subheadline.weight(.bold)
                        result.replaceSubrange(attrStart..<attrEnd, with: bold)
                    }
                }
            }
        }

        // Italic: *text*
        let italicPattern = "(?<!\\*)\\*([^*]+)\\*(?!\\*)"
        if let regex = try? NSRegularExpression(pattern: italicPattern) {
            let nsRange = NSRange(result.characters.startIndex..., in: String(result.characters))
            let matches = regex.matches(in: String(result.characters), range: nsRange).reversed()

            for match in matches {
                if let range = Range(match.range(at: 1), in: String(result.characters)) {
                    let italicText = String(String(result.characters)[range])
                    if let attrStart = AttributedString.Index(range.lowerBound, within: result),
                       let attrEnd = AttributedString.Index(range.upperBound, within: result) {
                        var italic = AttributedString(italicText)
                        italic.foregroundColor = AppColors.textSecondary
                        italic.font = .subheadline.italic()
                        result.replaceSubrange(attrStart..<attrEnd, with: italic)
                    }
                }
            }
        }

        // Links: [text](url)
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            let nsRange = NSRange(String(result.characters).startIndex..., in: String(result.characters))
            let matches = regex.matches(in: String(result.characters), range: nsRange).reversed()

            for match in matches {
                if let textRange = Range(match.range(at: 1), in: String(result.characters)),
                   let urlRange = Range(match.range(at: 2), in: String(result.characters)) {
                    let linkText = String(String(result.characters)[textRange])
                    let urlString = String(String(result.characters)[urlRange])
                    if let attrStart = AttributedString.Index(textRange.lowerBound, within: result),
                       let attrEnd = AttributedString.Index(textRange.upperBound, within: result) {
                        var link = AttributedString(linkText)
                        link.foregroundColor = AppColors.accentElectric
                        link.link = URL(string: urlString)
                        result.replaceSubrange(attrStart..<attrEnd, with: link)
                    }
                }
            }
        }

        return result
    }
}

// MARK: - Markdown Block

struct MarkdownBlock {
    enum BlockType {
        case heading1, heading2, heading3, codeBlock, listItem, paragraph
    }

    let type: BlockType
    let text: String
}

func parseMarkdown(_ content: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = content.components(separatedBy: "\n")
    var inCodeBlock = false
    var codeBlockContent = ""
    var i = 0

    while i < lines.count {
        let line = lines[i]

        // Code block start/end
        if line.hasPrefix("```") {
            if inCodeBlock {
                blocks.append(MarkdownBlock(type: .codeBlock, text: codeBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)))
                codeBlockContent = ""
                inCodeBlock = false
            } else {
                inCodeBlock = true
            }
            i += 1
            continue
        }

        if inCodeBlock {
            codeBlockContent += line + "\n"
            i += 1
            continue
        }

        // Headings
        if line.hasPrefix("# ") {
            blocks.append(MarkdownBlock(type: .heading1, text: String(line.dropFirst(2))))
        } else if line.hasPrefix("## ") {
            blocks.append(MarkdownBlock(type: .heading2, text: String(line.dropFirst(3))))
        } else if line.hasPrefix("### ") {
            blocks.append(MarkdownBlock(type: .heading3, text: String(line.dropFirst(4))))
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            blocks.append(MarkdownBlock(type: .listItem, text: String(line.dropFirst(2))))
        } else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Skip empty lines
        } else {
            blocks.append(MarkdownBlock(type: .paragraph, text: line))
        }

        i += 1
    }

    return blocks
}

// MARK: - Related Standard Card

struct RelatedStandardCard: View {
    let standard: Standard

    var body: some View {
        NavigationLink(value: standard) {
            HStack(spacing: Theme.sm) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: standard.category.color))
                    .frame(width: 3, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(standard.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: Theme.xxs) {
                        Image(systemName: standard.category.icon)
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: standard.category.color))

                        Text(standard.category.displayName)
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(Theme.sm)
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

// MARK: - Version Row

struct VersionRow: View {
    let version: StandardVersion

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("v\(version.version)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)

                Text(version.authorName)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Text(version.updatedAt.versionDateString)
                .font(.caption)
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal, Theme.sm)
        .padding(.vertical, Theme.xs)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - Ask Agent Sheet

struct AskAgentSheet: View {
    let standard: Standard
    @Binding var prompt: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.md) {
                Text("Ask an Agent about **\(standard.title)**")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Text("Send this standard's content to an agent for clarification, examples, or deeper explanation.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)

                ScrollView {
                    Text(standard.content)
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                        .padding(Theme.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }
                .frame(maxHeight: 200)

                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("Your question")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)

                    TextField("What would you like clarified?", text: $prompt, axis: .vertical)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textPrimary)
                        .padding(Theme.sm)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .lineLimit(3...6)
                }

                Spacer()

                Button {
                    // TODO: Send to chief-desk channel
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Send to Agent")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.sm)
                    .background(AppColors.accentAgent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Theme.md)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Ask an Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.accentElectric)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview {
    let vm = KnowledgeViewModel()
    let sample = Standard(
        id: UUID(),
        title: "API Design Standards",
        category: .standards,
        content: """
        # API Design Standards

        ## Overview

        This document outlines the **API design standards** for all services.

        - Use REST for web APIs
        - Use gRPC for internal services

        ## Code Example

        ```swift
        struct APIResponse: Codable {
            let data: Data
            let status: Int
        }
        ```

        ## References

        See [REST guidelines](https://example.com) for more.
        """,
        authorId: UUID(),
        authorName: "Shaka",
        tags: ["api", "swift", "backend"],
        version: 3,
        createdAt: Date().addingTimeInterval(-86400 * 30),
        updatedAt: Date().addingTimeInterval(-86400),
        isFavorite: true,
        relatedStandardIds: [],
        versions: [
            StandardVersion(id: UUID(), version: 3, content: "", authorId: UUID(), authorName: "Shaka", updatedAt: Date().addingTimeInterval(-86400)),
            StandardVersion(id: UUID(), version: 2, content: "", authorId: UUID(), authorName: "Shaka", updatedAt: Date().addingTimeInterval(-86400 * 7)),
            StandardVersion(id: UUID(), version: 1, content: "", authorId: UUID(), authorName: "Shaka", updatedAt: Date().addingTimeInterval(-86400 * 30)),
        ]
    )

    return NavigationStack {
        StandardDetailView(standard: sample, viewModel: vm)
    }
    .preferredColorScheme(.dark)
}
