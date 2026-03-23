import SwiftUI

// MARK: - Agent Detail Sheet

struct AgentDetailSheet: View {

    let agent: Agent
    var onViewLogs: (() -> Void)?
    var onStatusChanged: ((AgentStatus) -> Void)?
    var onPause: (() -> Void)?
    var onRestart: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus: AgentStatus
    @State private var showingPauseConfirmation = false
    @State private var showingRestartConfirmation = false
    @State private var showingConfigureSheet = false
    @State private var showingSendMessage = false

    init(
        agent: Agent,
        onViewLogs: (() -> Void)? = nil,
        onStatusChanged: ((AgentStatus) -> Void)? = nil,
        onPause: (() -> Void)? = nil,
        onRestart: (() -> Void)? = nil
    ) {
        self.agent = agent
        self.onViewLogs = onViewLogs
        self.onStatusChanged = onStatusChanged
        self.onPause = onPause
        self.onRestart = onRestart
        _selectedStatus = State(initialValue: agent.status)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    headerSection
                    statusSection
                    currentTaskSection
                    skillsSection
                    recentActivitySection
                    actionsSection
                }
                .padding(.horizontal, Theme.md)
                .padding(.bottom, Theme.xxl)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle(agent.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColors.accentElectric)
                }
            }
            .confirmationDialog(
                "Pause Agent",
                isPresented: $showingPauseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Pause \(agent.name)", role: .destructive) {
                    onPause?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(agent.name) will stop processing tasks until manually resumed.")
            }
            .confirmationDialog(
                "Restart Agent",
                isPresented: $showingRestartConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restart \(agent.name)", role: .destructive) {
                    onRestart?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will terminate the current session and start a fresh instance.")
            }
            .sheet(isPresented: $showingConfigureSheet) {
                AgentConfigureSheet(agent: agent)
            }
            .sheet(isPresented: $showingSendMessage) {
                ComposeMessageSheet(recipientName: agent.name)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: Theme.md) {
            // Large avatar with status ring
            ZStack {
                Circle()
                    .fill(agent.status.color.opacity(0.15))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(agent.status.color)
                    .frame(width: 92, height: 92)

                Circle()
                    .fill(Color(hex: agent.avatarColor))
                    .frame(width: 88, height: 88)

                Text(agent.name.prefix(1).uppercased())
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                // Status ring indicator
                Circle()
                    .strokeBorder(agent.status.color, lineWidth: 3)
                    .frame(width: 100, height: 100)
            }

            VStack(spacing: Theme.xxs) {
                Text(agent.name)
                    .podTextStyle(.title1, color: AppColors.textPrimary)

                Text(agent.role)
                    .podTextStyle(.body, color: AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.md)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Status")

            VStack(spacing: 0) {
                ForEach(AgentStatus.allCases, id: \.self) { status in
                    statusRow(status)

                    if status != AgentStatus.allCases.last {
                        Divider()
                            .background(AppColors.border)
                    }
                }
            }
            .podCard()
        }
    }

    private func statusRow(_ status: AgentStatus) -> some View {
        HStack {
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)

            Text(status.displayName)
                .podTextStyle(.body, color: AppColors.textPrimary)

            Spacer()

            if selectedStatus == status {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentElectric)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedStatus = status
            onStatusChanged?(status)
        }
        .padding(Theme.md)
    }

    // MARK: - Current Task Section

    private var currentTaskSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Current Task")

            if let task = agent.currentTask {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.accentWarning)

                    Text(task)
                        .podTextStyle(.body, color: AppColors.textPrimary)

                    Spacer()
                }
                .padding(Theme.md)
                .podCard()
            } else {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.accentSuccess)

                    Text("No active task")
                        .podTextStyle(.body, color: AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.md)
                .podCard()
            }
        }
    }

    // MARK: - Skills Section

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Skills", count: agent.skills.count)

            if agent.skills.isEmpty {
                Text("No skills configured")
                    .podTextStyle(.body, color: AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.md)
                    .podCard()
            } else {
                FlowLayout(spacing: Theme.xs) {
                    ForEach(agent.skills, id: \.self) { skill in
                        Text(skill)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.accentAgent)
                            .padding(.horizontal, Theme.sm)
                            .padding(.vertical, Theme.xxs)
                            .background(AppColors.accentAgent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(Theme.md)
                .podCard()
            }
        }
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Recent Activity", count: 10)

            VStack(spacing: 0) {
                ForEach(Array(Self.mockActivity(for: agent).enumerated()), id: \.offset) { index, item in
                    activityTimelineItem(item)

                    if index < 9 {
                        Divider()
                            .background(AppColors.border)
                            .padding(.leading, 44)
                    }
                }
            }
            .podCard()
        }
    }

    private func activityTimelineItem(_ item: AgentActivityItem) -> some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            // Timeline dot
            ZStack {
                Circle()
                    .fill(item.type.color.opacity(0.2))
                    .frame(width: 28, height: 28)

                Image(systemName: item.type.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.type.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.description)
                    .podTextStyle(.body, color: AppColors.textPrimary)
                    .lineLimit(2)

                Text(item.timestamp.relativeFormatted)
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.md)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: Theme.sm) {
            // Primary actions
            actionButton(
                icon: "bubble.left.fill",
                label: "Send Message",
                color: AppColors.accentElectric
            ) {
                showingSendMessage = true
            }

            actionButton(
                icon: "doc.text.fill",
                label: "View Logs",
                color: AppColors.textSecondary
            ) {
                onViewLogs?()
            }

            Divider()
                .background(AppColors.border)

            // Status control actions
            HStack(spacing: Theme.sm) {
                actionButton(
                    icon: "pause.circle.fill",
                    label: "Pause Agent",
                    color: AppColors.accentWarning,
                    isDestructive: true
                ) {
                    showingPauseConfirmation = true
                }

                actionButton(
                    icon: "arrow.clockwise.circle.fill",
                    label: "Restart Agent",
                    color: AppColors.accentDanger,
                    isDestructive: true
                ) {
                    showingRestartConfirmation = true
                }
            }

            actionButton(
                icon: "gearshape.fill",
                label: "Configure",
                color: AppColors.textSecondary
            ) {
                showingConfigureSheet = true
            }
        }
    }

    private func actionButton(
        icon: String,
        label: String,
        color: Color,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)

                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isDestructive ? color : AppColors.textPrimary)

                Spacer()

                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .padding(Theme.md)
            .background(isDestructive ? color.opacity(0.08) : AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(isDestructive ? color.opacity(0.2) : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: Theme.xs) {
            Text(title.uppercased())
                .podTextStyle(.label, color: AppColors.textTertiary)

            if let count = count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Mock Activity

    private static func mockActivity(for agent: Agent) -> [AgentActivityItem] {
        let now = Date()
        return [
            AgentActivityItem(type: .taskStarted, description: "Started working on PR #42 review", timestamp: now.addingTimeInterval(-120)),
            AgentActivityItem(type: .message, description: "Posted update in #projects channel", timestamp: now.addingTimeInterval(-600)),
            AgentActivityItem(type: .taskCompleted, description: "Completed code review for module auth", timestamp: now.addingTimeInterval(-1200)),
            AgentActivityItem(type: .fileCreated, description: "Created architecture_diagram.md", timestamp: now.addingTimeInterval(-1800)),
            AgentActivityItem(type: .error, description: "Connection timeout to staging — retried successfully", timestamp: now.addingTimeInterval(-2400)),
            AgentActivityItem(type: .taskStarted, description: "Began sprint planning research", timestamp: now.addingTimeInterval(-3600)),
            AgentActivityItem(type: .message, description: "Responded to @shaka in #general", timestamp: now.addingTimeInterval(-5400)),
            AgentActivityItem(type: .deployment, description: "Deployed v2.3.1 to staging environment", timestamp: now.addingTimeInterval(-7200)),
            AgentActivityItem(type: .taskCompleted, description: "Finished database migration script", timestamp: now.addingTimeInterval(-10800)),
            AgentActivityItem(type: .fileCreated, description: "Updated API documentation for /v1/agents", timestamp: now.addingTimeInterval(-14400)),
        ]
    }
}

// MARK: - Agent Activity Item

struct AgentActivityItem: Identifiable {
    let id = UUID()
    let type: ActivityEventType
    let description: String
    let timestamp: Date
}

enum ActivityEventType {
    case taskStarted
    case taskCompleted
    case message
    case fileCreated
    case deployment
    case error

    var icon: String {
        switch self {
        case .taskStarted:  return "play.circle.fill"
        case .taskCompleted: return "checkmark.circle.fill"
        case .message:    return "bubble.left.fill"
        case .fileCreated: return "doc.fill"
        case .deployment:  return "arrow.up.circle.fill"
        case .error:       return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .taskStarted:  return AppColors.accentElectric
        case .taskCompleted: return AppColors.accentSuccess
        case .message:      return AppColors.accentAgent
        case .fileCreated:   return AppColors.textSecondary
        case .deployment:   return AppColors.accentCaptain
        case .error:         return AppColors.accentDanger
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Agent Configure Sheet

struct AgentConfigureSheet: View {
    let agent: Agent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    LabeledContent("Name", value: agent.name)
                    LabeledContent("Role", value: agent.role)
                    LabeledContent("Model", value: "gpt-4o")
                }

                Section("Capabilities") {
                    ForEach(agent.skills, id: \.self) { skill in
                        Text(skill)
                    }
                }
            }
            .navigationTitle("Configure \(agent.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColors.accentElectric)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Compose Message Sheet

struct ComposeMessageSheet: View {
    let recipientName: String
    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: Theme.sm) {
                    Text("To:")
                        .podTextStyle(.body, color: AppColors.textSecondary)
                    Text(recipientName)
                        .podTextStyle(.body, color: AppColors.textPrimary)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.md)
                .background(AppColors.backgroundSecondary)

                TextEditor(text: $messageText)
                    .scrollContentBackground(.hidden)
                    .background(AppColors.backgroundPrimary)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(Theme.md)

                Spacer()
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        // TODO: Send via API
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.accentElectric)
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
