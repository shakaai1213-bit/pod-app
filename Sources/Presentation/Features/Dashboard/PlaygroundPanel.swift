import SwiftUI

// MARK: - Playground Panel

@MainActor
@Observable
final class PlaygroundPanelModel {
    var agents: [PlaygroundAgentReadiness] = []
    var roomCount = 0
    var unreadRoomCount = 0
    var pendingMessageCount = 0
    var attentionRoomCount = 0
    var healthStatus: String?
    var generatedAt: Date?
    var isLoading = false
    var errorMessage: String?

    var readyAgentCount: Int {
        agents.filter { $0.isReady }.count
    }

    var gatedAgentCount: Int {
        agents.filter { $0.isGated }.count
    }

    var totalPendingCount: Int {
        max(pendingMessageCount, agents.reduce(0) { $0 + $1.pendingCount })
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var nextRoomCount = 0
        var nextUnreadRoomCount = 0
        var nextPendingMessageCount = 0
        var nextAttentionRoomCount = 0
        var nextGeneratedAt: Date?
        var nextHealthStatus: String?

        do {
            let contacts: PlaygroundContactsResponseDTO = try await APIClient.shared.get(path: "/api/v1/sonar/contacts")
            nextGeneratedAt = contacts.generatedAt
            nextRoomCount = contacts.contacts.count
            nextUnreadRoomCount = contacts.contacts.filter { ($0.unreadCount ?? 0) > 0 }.count
            nextPendingMessageCount = contacts.contacts.reduce(0) { $0 + $1.pendingCount }
            nextAttentionRoomCount = contacts.contacts.filter {
                ($0.needsAttention ?? false)
                    || $0.notificationLevel == "attention"
                    || $0.notificationLevel == "urgent"
            }.count
        } catch {
            // Locker Cockpit remains the stronger Schoolhouse truth. Keep the
            // panel useful if the compatibility contact facade is unavailable.
        }

        do {
            let health: PlaygroundHealthDTO = try await APIClient.shared.get(path: "/api/v1/sonar/health")
            nextHealthStatus = health.status
            nextGeneratedAt = nextGeneratedAt ?? health.generatedAt
        } catch {
            nextHealthStatus = nil
        }

        var nextAgents: [PlaygroundAgentReadiness] = []
        var failures: [String] = []

        for agent in AgentInfo.team where agent.isReachable {
            do {
                let locker: AgentLockerDTO = try await APIClient.shared.get(
                    path: Endpoint.agentLocker(name: agent.id, limit: 4).path,
                    includeAgentToken: true
                )
                nextAgents.append(PlaygroundAgentReadiness(agent: agent, locker: locker))
            } catch {
                failures.append(agent.name)
            }
        }

        roomCount = nextRoomCount
        unreadRoomCount = nextUnreadRoomCount
        pendingMessageCount = nextPendingMessageCount
        attentionRoomCount = nextAttentionRoomCount
        generatedAt = nextGeneratedAt
        healthStatus = nextHealthStatus
        agents = nextAgents.sorted { left, right in
            if left.sortBucket != right.sortBucket { return left.sortBucket < right.sortBucket }
            if left.score != right.score { return left.score > right.score }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        if agents.isEmpty, !failures.isEmpty {
            errorMessage = "Locker Cockpit unavailable for \(failures.joined(separator: ", "))."
        } else if !failures.isEmpty {
            errorMessage = "Some lockers unavailable: \(failures.joined(separator: ", "))."
        }
    }
}

struct PlaygroundAgentReadiness: Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let icon: String
    let colorHex: String
    let score: Int
    let status: String
    let headline: String
    let channelName: String
    let policyState: String
    let pendingCount: Int
    let unreadCount: Int
    let messageCount: Int
    let canPost: Bool
    let canRun: Bool
    let canRequestResearch: Bool
    let continuityScore: Double?
    let latestPreview: String?
    let activeTicketId: String?

    init(agent: AgentInfo, locker: AgentLockerDTO) {
        id = agent.id
        name = agent.name
        role = agent.role
        icon = agent.icon
        colorHex = agent.color
        score = locker.reportCard.score
        status = locker.reportCard.status ?? "unknown"
        headline = locker.reportCard.headline ?? locker.startHere.headline ?? "Locker Cockpit loaded."
        channelName = locker.chat.channelName ?? "direct:\(agent.id)"
        policyState = locker.chat.policyState ?? "open"
        pendingCount = locker.chat.pendingCount
        unreadCount = locker.chat.unreadCount
        messageCount = locker.chat.messageCount
        canPost = locker.chat.canPost
        canRun = locker.chat.canDispatchSchoolhouseRun
        canRequestResearch = locker.chat.canRequestResearch
        continuityScore = locker.chat.continuityInputsScore
        latestPreview = locker.chat.latestMessagePreview
        activeTicketId = locker.chat.activeTicketId
    }

    var isReady: Bool {
        score >= 85 && !isGated
    }

    var isGated: Bool {
        ["protected", "ticket_required", "dormant_archive", "redacted_summary_available"].contains(policyState)
            || !canPost
    }

    var sortBucket: Int {
        if pendingCount > 0 || unreadCount > 0 { return 0 }
        if isGated { return 1 }
        if !isReady { return 2 }
        return 3
    }

    var policyLabel: String {
        policyState.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var statusLabel: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct PlaygroundPanelView: View {
    let model: PlaygroundPanelModel
    let onChatTap: (() -> Void)?

    private let playgroundColor = Color(hexString: "26A6B8")

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            panelHeader
            panelContent
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(playgroundColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var panelHeader: some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(playgroundColor)

            Text("PLAYGROUND")
                .podTextStyle(.label, color: AppColors.textTertiary)

            if let health = model.healthStatus, !health.isEmpty {
                Text("· \(health.replacingOccurrences(of: "_", with: " "))")
                    .podTextStyle(.label, color: statusColor(health))
                    .lineLimit(1)
            }

            Spacer()

            if model.isLoading {
                ProgressView().scaleEffect(0.55)
            }
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        if !model.agents.isEmpty {
            summaryStrip
            agentList
            actionRow
        } else if model.isLoading {
            Text("Loading Schoolhouse readiness...")
                .podTextStyle(.caption, color: AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = model.errorMessage {
            Text(error)
                .podTextStyle(.caption, color: AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
            actionRow
        } else {
            Text("Playground is waiting for Locker Cockpit data.")
                .podTextStyle(.caption, color: AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            actionRow
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: Theme.xs) {
            metricPill("\(model.readyAgentCount)/\(model.agents.count)", label: "ready", color: AppColors.accentSuccess)
            metricPill("\(model.totalPendingCount)", label: "pending", color: model.totalPendingCount > 0 ? AppColors.accentWarning : AppColors.textTertiary)
            metricPill("\(model.gatedAgentCount)", label: "gated", color: model.gatedAgentCount > 0 ? AppColors.accentWarning : AppColors.textTertiary)
            if model.roomCount > 0 {
                metricPill("\(model.roomCount)", label: "rooms", color: playgroundColor)
            }
            if model.attentionRoomCount > 0 {
                metricPill("\(model.attentionRoomCount)", label: "attention", color: AppColors.accentWarning)
            }
        }
    }

    private var agentList: some View {
        VStack(spacing: 0) {
            ForEach(model.agents.prefix(6)) { agent in
                agentRow(agent)

                if agent.id != model.agents.prefix(6).last?.id {
                    Divider().opacity(0.28)
                }
            }
        }
    }

    private func agentRow(_ agent: PlaygroundAgentReadiness) -> some View {
        HStack(alignment: .top, spacing: Theme.xs) {
            Image(systemName: agent.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hexString: agent.colorHex))
                .frame(width: 24, height: 24)
                .background(Color(hexString: agent.colorHex).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(agent.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Text("\(agent.score)%")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(scoreColor(agent.score, gated: agent.isGated))

                    if agent.pendingCount > 0 {
                        Text("\(agent.pendingCount) pending")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.accentWarning)
                    }

                    Spacer(minLength: 0)
                }

                Text(agent.headline)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    statusChip(agent.statusLabel, color: scoreColor(agent.score, gated: agent.isGated))
                    statusChip(agent.policyLabel, color: policyColor(agent.policyState))
                    if agent.canRun {
                        statusChip("Run", color: AppColors.accentSuccess)
                    }
                    if agent.canRequestResearch {
                        statusChip("Research", color: playgroundColor)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var actionRow: some View {
        HStack(spacing: Theme.sm) {
            Button {
                onChatTap?()
            } label: {
                Label("Open Playground", systemImage: "arrow.up.forward.app.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(playgroundColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(playgroundColor.opacity(0.10))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            if let generatedAt = model.generatedAt {
                Text(relativeAge(generatedAt))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(.top, Theme.xs)
    }

    private func metricPill(_ value: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.caption2.weight(.bold))
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }

    private func statusChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func scoreColor(_ score: Int, gated: Bool) -> Color {
        if gated { return AppColors.accentWarning }
        if score >= 85 { return AppColors.accentSuccess }
        if score >= 65 { return AppColors.accentWarning }
        return AppColors.accentDanger
    }

    private func policyColor(_ policy: String) -> Color {
        switch policy {
        case "open":
            return AppColors.accentSuccess
        case "protected", "ticket_required", "redacted_summary_available":
            return AppColors.accentWarning
        case "dormant_archive":
            return AppColors.textTertiary
        default:
            return playgroundColor
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "healthy", "ready", "ok":
            return AppColors.accentSuccess
        case "degraded", "attention":
            return AppColors.accentWarning
        case "failed", "error":
            return AppColors.accentDanger
        default:
            return playgroundColor
        }
    }

    private func relativeAge(_ date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 90 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h" }
        return "\(Int(elapsed / 86400))d"
    }
}

private struct PlaygroundContactsResponseDTO: Decodable {
    let generatedAt: Date
    let contacts: [PlaygroundContactDTO]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case contacts
    }
}

private struct PlaygroundContactDTO: Decodable {
    let pendingCount: Int
    let unreadCount: Int?
    let needsAttention: Bool?
    let notificationLevel: String?

    enum CodingKeys: String, CodingKey {
        case pendingCount = "pending_count"
        case unreadCount = "unread_count"
        case needsAttention = "needs_attention"
        case notificationLevel = "notification_level"
    }
}

private struct PlaygroundHealthDTO: Decodable {
    let status: String
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case generatedAt = "generated_at"
    }
}
