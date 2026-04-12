import SwiftUI
import Speech

// MARK: - Typing User

struct TypingUser: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isAgent: Bool
    var startedAt: Date

    init(id: String, name: String, isAgent: Bool = false) {
        self.id = id
        self.name = name
        self.isAgent = isAgent
        self.startedAt = Date()
    }
}

// MARK: - Typing Dots View

struct TypingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppColors.textSecondary.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever()
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Compose Bar View

struct ComposeBarView: View {
    let channelId: String
    let isSending: Bool
    let typingUsers: [TypingUser]
    let replyingTo: Message?
    let onSend: (String, UUID?) -> Void
    let onCancelReply: () -> Void

    @State private var text: String = ""
    @State private var editorId = UUID()  // force TextEditor to reset on send
    @FocusState private var isFocused: Bool
    @State private var showAgentMentionPicker = false
    @State private var showAttachmentSheet = false
    @StateObject private var speech = SpeechRecognizer()

    // Agents loaded from the backend
    @State private var agents: [MentionCandidate] = []

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: - Typing Indicator

    @ViewBuilder
    private var typingIndicator: some View {
        let users = typingUsers
        if !users.isEmpty {
            HStack(spacing: 6) {
                // Animated dots
                TypingDotsView()
                    .frame(width: 20, height: 12)

                Text(typingText(for: users))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(AppColors.backgroundPrimary.opacity(0.8))
        }
    }

    private func typingText(for users: [TypingUser]) -> String {
        if users.count == 1 {
            return "\(users[0].name) is typing"
        } else if users.count == 2 {
            return "\(users[0].name) and \(users[1].name) are typing"
        } else {
            return "\(users.count) people are typing"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Agent mention picker — sits ABOVE compose bar, floats up over messages
            if showAgentMentionPicker {
                agentMentionPopover
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Typing indicator
            if !typingUsers.isEmpty {
                typingIndicator
            }

            // Voice recording indicator
            if speech.isRecording {
                VoiceInputIndicator(isRecording: $speech.isRecording) {
                    speech.stopRecording()
                    if !speech.transcript.isEmpty {
                        text = speech.transcript
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Divider()
                .background(AppColors.border)

            HStack(alignment: .bottom, spacing: 8) {
                // Attach button
                attachButton

                // Text input area
                inputArea

                // Bottom action row
                HStack(spacing: 4) {
                    // Agent mention (only show if agents are loaded)
                    if !agents.isEmpty {
                        agentMentionButton
                    }

                    // Mic or Send
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending {
                        micButton
                    } else {
                        sendButton
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(AppColors.backgroundSecondary)
        }
        .sheet(isPresented: $showAttachmentSheet) {
            AttachmentPickerView { image in
                showAttachmentSheet = false
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: speech.transcript) { _, newValue in
            // Live preview while recording
            if speech.isRecording && !newValue.isEmpty {
                text = newValue
            }
        }
        .task {
            await speech.requestPermissions()
        }
        .task {
            await loadAgents()
        }
        .animation(.easeInOut(duration: 0.2), value: speech.isRecording)
    }

    // MARK: - Attach Button

    private var attachButton: some View {
        Button {
            showAttachmentSheet = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(AppColors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            // Expandable text editor
            ZStack(alignment: .topLeading) {
                // Placeholder
                if text.isEmpty {
                    Text("Message #general...")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                // TextEditor
                TextEditor(text: $text)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minHeight: 36, maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($isFocused)
                    .id(editorId)
                    .onChange(of: text) { _, newValue in
                        // Limit to ~5 lines visually by constraining height
                        // TextEditor naturally handles scrolling
                    }

                // Placeholder — no hit-testing so taps pass through to TextEditor
                if text.isEmpty {
                    Color.clear
                        .allowsHitTesting(false)
                }
            }
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isFocused ? AppColors.accentElectric.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Agent Mention Button

    private var agentMentionButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showAgentMentionPicker.toggle()
            }
        } label: {
            Image(systemName: "at")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(showAgentMentionPicker ? AppColors.accentAgent : AppColors.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    showAgentMentionPicker
                        ? AppColors.accentAgent.opacity(0.15)
                        : AppColors.backgroundTertiary
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Agent Mention Popover

    private var agentMentionPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Mention an agent")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showAgentMentionPicker = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()
                .background(AppColors.border)

            // Agent list
            ForEach(agents) { agent in
                Button {
                    insertMention(agent.name)
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showAgentMentionPicker = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AppColors.accentAgent.opacity(0.15))
                            Image(systemName: agent.icon)
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.accentAgent)
                        }
                        .frame(width: 28, height: 28)

                        Text(agent.name)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textPrimary)

                        Text("@\(agent.name.lowercased())")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)

                        Spacer()

                        Image(systemName: "arrow.turn.down.left")
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if agent.id != agents.last?.id {
                    Divider()
                        .background(AppColors.border)
                        .padding(.leading, 50)
                }
            }

            // Quick mention chips
            HStack(spacing: 6) {
                Text("Quick:")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)

                ForEach(agents) { agent in
                    Button {
                        insertMention(agent.name)
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showAgentMentionPicker = false
                        }
                    } label: {
                        Text("@\(agent.name)")
                            .font(.caption2)
                            .foregroundColor(AppColors.accentAgent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppColors.accentAgent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: 280)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
    }

    // MARK: - Mic Button

    private var micButton: some View {
        Button {
            if speech.isRecording {
                speech.stopRecording()
                if !speech.transcript.isEmpty {
                    text = speech.transcript
                }
            } else {
                isFocused = false
                speech.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(speech.isRecording ? AppColors.accentDanger : AppColors.backgroundTertiary)
                    .frame(width: 36, height: 36)
                Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(speech.isRecording ? .white : AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(speech.permissionDenied)
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }
            onSend(message, replyingTo?.id)
            text = ""
            speech.transcript = ""
            editorId = UUID()  // force TextEditor to visually clear
        } label: {
            ZStack {
                Circle()
                    .fill(
                        canSend
                            ? AppColors.accentElectric
                            : AppColors.backgroundTertiary
                    )
                    .frame(width: 36, height: 36)

                if isSending {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(
                            canSend ? .white : AppColors.textTertiary
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    // MARK: - Agent Loading

    private func loadAgents() async {
        // Nova is always available as an on-demand assistant
        let nova = MentionCandidate(id: "nova", name: "Nova", icon: "sparkle")

        do {
            let response: PaginatedResponse<AgentDTO> = try await APIClient.shared.get(path: "/api/v1/agents")
            var candidates = response.items.map { dto in
                MentionCandidate(
                    id: dto.id,
                    name: dto.name.prefix(1).uppercased() + dto.name.dropFirst(),
                    icon: iconForAgent(dto.name)
                )
            }
            // Prepend Nova if not already in the list
            if !candidates.contains(where: { $0.name.lowercased() == "nova" }) {
                candidates.insert(nova, at: 0)
            }
            agents = candidates
        } catch {
            // Fall back to just Nova
            agents = [nova]
        }
    }

    private func iconForAgent(_ name: String) -> String {
        switch name.lowercased() {
        case "nova":    return "sparkle"
        case "maui":    return "wrench.and.screwdriver"
        case "aloha":   return "doc.text"
        case "aurora":  return "sparkles"
        case "shaka":   return "person.circle"
        case "chief":   return "chart.line.uptrend.xyaxis"
        case "rooster": return "shield"
        default:        return "cpu"
        }
    }

    // MARK: - Helpers

    private func insertMention(_ name: String) {
        if text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") {
            text += "@\(name) "
        } else {
            text += " @\(name) "
        }
    }
}

// MARK: - Mention Candidate

struct MentionCandidate: Identifiable {
    let id: String
    let name: String
    let icon: String
}

// MARK: - Attachment Picker

struct AttachmentPickerView: View {
    let onImageSelected: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showPhotoPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Attachments")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.top, 16)

                HStack(spacing: 24) {
                    attachmentOption(
                        icon: "photo",
                        label: "Photo Library",
                        color: AppColors.accentAgent
                    ) {
                        showPhotoPicker = true
                    }

                    attachmentOption(
                        icon: "camera",
                        label: "Camera",
                        color: AppColors.accentElectric
                    ) {
                        // Camera capture would go here
                    }

                    attachmentOption(
                        icon: "doc",
                        label: "Document",
                        color: AppColors.accentSuccess
                    ) {
                        // Document picker would go here
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(AppColors.backgroundSecondary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.accentElectric)
                }
            }
        }
    }

    private func attachmentOption(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Voice Input Overlay

struct VoiceInputIndicator: View {
    @Binding var isRecording: Bool
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Waveform animation
            HStack(spacing: 2) {
                ForEach(0..<8, id: \.self) { i in
                    Capsule()
                        .fill(AppColors.accentDanger)
                        .frame(width: 3)
                        .frame(height: CGFloat.random(in: 8...20))
                        .animation(
                            .easeInOut(duration: 0.15)
                            .repeatForever()
                            .delay(Double(i) * 0.05),
                            value: isRecording
                        )
                }
            }
            .frame(height: 24)

            Text("Recording...")
                .font(.subheadline)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundColor(AppColors.accentDanger)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        ComposeBarView(
            channelId: "ch-general",
            isSending: false,
            typingUsers: [],
            replyingTo: nil,
            onSend: { content, replyToId in
                print("Send: \(content) (replyTo: \(replyToId?.uuidString ?? "none"))")
            },
            onCancelReply: {}
        )
    }
    .background(AppColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}
