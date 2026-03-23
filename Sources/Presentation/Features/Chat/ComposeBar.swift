import SwiftUI

// MARK: - Compose Bar View

struct ComposeBarView: View {
    let channelId: String
    let isSending: Bool
    let onSend: (String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @State private var showAgentMentionPicker = false
    @State private var showAttachmentSheet = false

    // Agents available for mention
    private let agents = [
        MentionCandidate(id: "agent-maui", name: "Maui", icon: "cpu"),
        MentionCandidate(id: "agent-clio", name: "Clio", icon: "book"),
        MentionCandidate(id: "agent-orca", name: "Orca", icon: "water.waves"),
    ]

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppColors.border)

            HStack(alignment: .bottom, spacing: 8) {
                // Attach button
                attachButton

                // Text input area
                inputArea

                // Bottom action row
                HStack(spacing: 4) {
                    // Agent mention
                    agentMentionButton

                    // Send button
                    sendButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(AppColors.backgroundSecondary)
        }
        .overlay(alignment: .top) {
            if showAgentMentionPicker {
                agentMentionPopover
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .sheet(isPresented: $showAttachmentSheet) {
            AttachmentPickerView { image in
                // Handle image attachment
                showAttachmentSheet = false
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
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
                    .onChange(of: text) { _, newValue in
                        // Limit to ~5 lines visually by constraining height
                        // TextEditor naturally handles scrolling
                    }

                // Voice input overlay (tap-hold on empty field)
                if text.isEmpty {
                    Color.clear
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.3) {
                            // Voice input would trigger here
                        }
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

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }
            onSend(message)
            text = ""
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
            onSend: { content in
                print("Send: \(content)")
            }
        )
    }
    .background(AppColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}
