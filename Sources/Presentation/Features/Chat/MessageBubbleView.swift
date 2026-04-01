import SwiftUI
import SwiftData

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: Message
    let showAvatar: Bool
    let isCurrentUser: Bool
    let onAgentTapped: () -> Void
    let onAddReaction: (String) -> Void
    let onReply: (Message) -> Void

    @State private var showReactionPicker = false
    @State private var copiedCode = false

    private let avatarColors: [Color] = [
        AppColors.accentElectric,
        AppColors.accentAgent,
        AppColors.accentSuccess,
        AppColors.accentCaptain,
        Color(hexString: "06B6D4"),
        Color(hexString: "EC4899"),
    ]

    private var avatarColor: Color {
        let hash = message.authorId.hashValue
        let index = abs(hash) % avatarColors.count
        return avatarColors[index]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isCurrentUser {
                Spacer(minLength: 60)
            }

            if !isCurrentUser {
                // Avatar
                if showAvatar {
                    avatarView
                        .frame(width: 32)
                } else {
                    Color.clear
                        .frame(width: 32)
                }
            }

            // Message content
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                // Author name (only when avatar is shown)
                if showAvatar && !isCurrentUser {
                    authorNameView
                }

                // Reply indicator
                if let replyTo = message.replyTo {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 8))
                            .foregroundColor(AppColors.textTertiary)
                        Text("Replying to a message")
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding(.bottom, 2)
                }

                // Bubble
                bubbleView
                    .environment(\.openURL, OpenURLAction { url in
                        // Handle links in messages
                        return .systemAction
                    })

                // Reactions
                if !message.reactions.isEmpty {
                    reactionsRow
                }

                // Timestamp — relative for recent, absolute for older
                Text(message.timestamp.relativeTimeString)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.top, 2)
            }
            .frame(
                maxWidth: isCurrentUser ? 320 : nil,
                alignment: isCurrentUser ? .trailing : .leading
            )

            if !isCurrentUser {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            message.isHighlighted
                ? AppColors.accentAgent.opacity(0.08)
                : Color.clear
        )
        .animation(.easeInOut(duration: 0.2), value: message.isHighlighted)
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Author Name

    private var authorNameView: some View {
        Button(action: onAgentTapped) {
            HStack(spacing: 4) {
                Text(message.authorName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(nameColor)

                if message.authorRole == .agent {
                    Image(systemName: "cpu")
                        .font(.system(size: 8))
                        .foregroundColor(AppColors.accentAgent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var nameColor: Color {
        switch message.authorRole {
        case .human:  return AppColors.textSecondary
        case .agent:  return AppColors.accentAgent
        case .system: return AppColors.textTertiary
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        Group {
            if message.authorRole == .system {
                SystemAvatarView(systemImage: "gearshape.fill", size: .sm, color: AppColors.textTertiary)
            } else {
                AvatarView(name: message.authorName, size: .sm, useDiceBear: true)
            }
        }
        .frame(width: 32, height: 32)
    }

    // MARK: - Bubble

    private var bubbleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Left border for agent messages
            if message.authorRole == .agent && !isCurrentUser {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(AppColors.accentAgent)
                        .frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1))

                    messageContentView
                        .padding(.leading, 10)
                }
            } else {
                messageContentView
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.authorRole {
        case .system:
            AppColors.backgroundTertiary
        default:
            if isCurrentUser {
                AppColors.accentElectric.opacity(0.15)
            } else {
                AppColors.backgroundSecondary
            }
        }
    }

    @ViewBuilder
    private var messageContentView: some View {
        // System messages are plain
        if message.authorRole == .system {
            Text(message.content)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
        } else {
            MarkdownContentView(content: message.content)
                .environment(\.openURL, OpenURLAction { url in
                    return .systemAction
                })
        }
    }

    // MARK: - Reactions

    private var reactionsRow: some View {
        HStack(spacing: 4) {
            ForEach(message.reactions.filter { $0.count > 0 }) { reaction in
                Button {
                    onAddReaction(reaction.emoji)
                } label: {
                    HStack(spacing: 2) {
                        Text(reaction.emoji)
                            .font(.caption)
                        Text("\(reaction.count)")
                            .font(.caption2)
                            .foregroundColor(
                                reaction.isReactedByMe
                                    ? AppColors.accentElectric
                                    : AppColors.textSecondary
                            )
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        reaction.isReactedByMe
                            ? AppColors.accentElectric.opacity(0.15)
                            : AppColors.backgroundTertiary
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                reaction.isReactedByMe
                                    ? AppColors.accentElectric.opacity(0.4)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            // Add reaction button
            Button {
                showReactionPicker.toggle()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showReactionPicker) {
                ReactionPickerView { emoji in
                    onAddReaction(emoji)
                    showReactionPicker = false
                }
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            UIPasteboard.general.string = message.content
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
            onReply(message)
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }

        if message.authorRole == .agent {
            Button {
                onAgentTapped()
            } label: {
                Label("Highlight agent messages", systemImage: "highlighter")
            }
        }

        Button {
            onAddReaction("👍")
        } label: {
            Label("React", systemImage: "face.smiling")
        }
    }
}

// MARK: - Reaction Picker

struct ReactionPickerView: View {
    let onSelect: (String) -> Void

    private let quickEmojis = ["👍", "❤️", "😂", "🎉", "🤔", "👀", "🚀", "✅"]

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Reaction")
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
                .padding(.top, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(quickEmojis, id: \.self) { emoji in
                    Button {
                        onSelect(emoji)
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .padding(6)
                            .background(AppColors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 200)
        .background(AppColors.backgroundSecondary)
    }
}

// MARK: - Markdown Content View

struct MarkdownContentView: View {
    let content: String

    var body: some View {
        // Parse and render markdown content
        VStack(alignment: .leading, spacing: 4) {
            ForEach(parseMarkdown(content), id: \.id) { segment in
                switch segment.type {
                case .text:
                    Text(segment.content)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textPrimary)

                case .boldText:
                    Text(segment.content)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppColors.textPrimary)

                case .italicText:
                    Text(segment.content)
                        .font(.subheadline.italic())
                        .foregroundColor(AppColors.textPrimary)

                case .boldItalicText:
                    Text(segment.content)
                        .font(.subheadline.weight(.bold).italic())
                        .foregroundColor(AppColors.textPrimary)

                case .inlineCode:
                    Text(segment.content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(AppColors.accentElectric)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                case .codeBlock(let language):
                    CodeBlockView(code: segment.content, language: language)
                        .padding(.vertical, 4)

                case .newline:
                    Text("")

                case .mention(let name):
                    HStack(spacing: 2) {
                        Text("@")
                            .font(.subheadline)
                            .foregroundColor(AppColors.accentAgent)
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.accentAgent)
                    }
                }
            }
        }
    }

    // MARK: - Markdown Parser

    private struct MarkdownSegment: Identifiable {
        let id = UUID()
        let type: SegmentType
        let content: String

        enum SegmentType {
            case text
            case boldText
            case italicText
            case boldItalicText
            case inlineCode
            case codeBlock(language: String?)
            case newline
            case mention(name: String)
        }
    }

    private func parseMarkdown(_ text: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        var remaining = text

        while !remaining.isEmpty {
            // Check for code block
            if remaining.hasPrefix("```") {
                let endOfLine = remaining.index(remaining.startIndex, offsetBy: 3, limitedBy: remaining.endIndex) ?? remaining.endIndex
                let rest = remaining[endOfLine...]

                // Find closing ```
                if let closeRange = rest.range(of: "```") {
                    let codeContent = String(rest[..<closeRange.lowerBound])
                    let beforeNewline = remaining.index(endOfLine, offsetBy: -3, limitedBy: remaining.startIndex) ?? remaining.startIndex
                    let afterNewline = remaining.index(after: beforeNewline)
                    let line = String(remaining[afterNewline..<endOfLine]).trimmingCharacters(in: .whitespaces)
                    let language = line.isEmpty ? nil : line
                    segments.append(MarkdownSegment(type: .codeBlock(language: language), content: codeContent.trimmingCharacters(in: .newlines)))
                    remaining = String(rest[closeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    continue
                }
            }

            // Check for bold italic (***text***)
            if let match = remaining.range(of: #"\*\*\*(.+?)\*\*\*"#, options: .regularExpression) {
                let inner = String(remaining[match]).dropFirst(3).dropLast(3)
                segments.append(MarkdownSegment(type: .boldItalicText, content: String(inner)))
                remaining = String(remaining[match.upperBound...])
                continue
            }

            // Check for bold (**text**)
            if let match = remaining.range(of: #"\*\*(.+?)\*\*"#, options: .regularExpression) {
                let inner = String(remaining[match]).dropFirst(2).dropLast(2)
                segments.append(MarkdownSegment(type: .boldText, content: String(inner)))
                remaining = String(remaining[match.upperBound...])
                continue
            }

            // Check for italic (*text*)
            if let match = remaining.range(of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, options: .regularExpression) {
                let inner = String(remaining[match]).dropFirst(1).dropLast(1)
                segments.append(MarkdownSegment(type: .italicText, content: String(inner)))
                remaining = String(remaining[match.upperBound...])
                continue
            }

            // Check for inline code (`code`)
            if let match = remaining.range(of: #"`[^`]+`"#, options: .regularExpression) {
                let inner = String(remaining[match]).dropFirst(1).dropLast(1)
                segments.append(MarkdownSegment(type: .inlineCode, content: String(inner)))
                remaining = String(remaining[match.upperBound...])
                continue
            }

            // Check for mention (@name)
            if let match = remaining.range(of: #"@[a-zA-Z0-9_]+"#, options: .regularExpression) {
                let name = String(remaining[match]).dropFirst()
                segments.append(MarkdownSegment(type: .mention(name: String(name)), content: String(remaining[match])))
                remaining = String(remaining[match.upperBound...])
                continue
            }

            // Check for newline
            if remaining.hasPrefix("\n") {
                segments.append(MarkdownSegment(type: .newline, content: ""))
                remaining = String(remaining.dropFirst())
                continue
            }

            // Collect plain text until next special character
            let specialChars = CharacterSet(charactersIn: "`*\n@")
            if let nextSpecial = remaining.rangeOfCharacter(from: specialChars) {
                let plainText = String(remaining[..<nextSpecial.lowerBound])
                if !plainText.isEmpty {
                    segments.append(MarkdownSegment(type: .text, content: plainText))
                }
                remaining = String(remaining[nextSpecial.lowerBound...])
            } else {
                segments.append(MarkdownSegment(type: .text, content: remaining))
                remaining = ""
            }
        }

        return segments
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var copied = false

    private var highlightedCode: AttributedString {
        var attributed = AttributedString(code)
        // Basic syntax highlighting — highlight common keywords
        let keywords = ["func", "let", "var", "class", "struct", "enum", "import", "return", "if", "else", "guard", "switch", "case", "default", "for", "while", "try", "catch", "throw", "async", "await", "in", "self", "Self", "true", "false", "nil", "private", "public", "internal", "static", "final", "override", "init", "deinit", "typealias", "extension", "protocol", "where", "as", "is", "Any", "some", "optional"]

        let keywordColor = AppColors.accentAgent
        let stringColor = AppColors.accentSuccess
        let commentColor = AppColors.textTertiary

        for keyword in keywords {
            if let range = attributed.range(of: keyword) {
                attributed[range].foregroundColor = keywordColor
            }
        }

        // Highlight strings (simple)
        let stringPattern = #""[^"]*""#
        if let regex = try? NSRegularExpression(pattern: stringPattern) {
            let nsRange = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: nsRange) {
                if let range = Range(match.range, in: code) {
                    let substring = String(code[range])
                    if let attrRange = attributed.range(of: substring) {
                        attributed[attrRange].foregroundColor = stringColor
                    }
                }
            }
        }

        // Highlight comments
        let commentPattern = #"//.*$"#
        if let regex = try? NSRegularExpression(pattern: commentPattern, options: .anchorsMatchLines) {
            let nsRange = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: nsRange) {
                if let range = Range(match.range, in: code) {
                    let substring = String(code[range])
                    if let attrRange = attributed.range(of: substring) {
                        attributed[attrRange].foregroundColor = commentColor
                        attributed[attrRange].font = .system(.caption, design: .monospaced).italic()
                    }
                }
            }
        }

        return attributed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                if let lang = language {
                    Text(lang)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textTertiary)
                } else {
                    Text("code")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                        Text(copied ? "Copied!" : "Copy")
                            .font(.caption2)
                    }
                    .foregroundColor(copied ? AppColors.accentSuccess : AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightedCode)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        MessageBubbleView(
            message: Message(
                channelId: UUID(),
                authorId: UUID(),
                authorName: "Alex Chen",
                authorRole: .human,
                content: "Hey team! **Bold** and *italic* text, with `inline code`.",
                timestamp: Date()
            ),
            showAvatar: true,
            isCurrentUser: false,
            onAgentTapped: {},
            onAddReaction: { _ in },
            onReply: { _ in }
        )

        MessageBubbleView(
            message: Message(
                channelId: UUID(),
                authorId: UUID(),
                authorName: "You",
                authorRole: .human,
                content: "Got it! I'll push the fix now.",
                timestamp: Date()
            ),
            showAvatar: true,
            isCurrentUser: true,
            onAgentTapped: {},
            onAddReaction: { _ in },
            onReply: { _ in }
        )

        MessageBubbleView(
            message: Message(
                channelId: UUID(),
                authorId: UUID(),
                authorName: "Maui",
                authorRole: .agent,
                content: "Here's a code snippet:\n\n```swift\nlet result = await fetchData()\nprint(result)\n```",
                timestamp: Date(),
                reactions: [Reaction(emoji: "👍", count: 3, userIds: ["u1"], isReactedByMe: true)]
            ),
            showAvatar: true,
            isCurrentUser: false,
            onAgentTapped: {},
            onAddReaction: { _ in },
            onReply: { _ in }
        )
    }
    .background(AppColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}
