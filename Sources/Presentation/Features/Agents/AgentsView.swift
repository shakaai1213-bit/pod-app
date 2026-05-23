import SwiftUI

// MARK: - Agents View (Cockpit, per SPEC-POD-AGENTS-TAB-2026-05-23)
// Slice 1: section frames + headers + design tokens wired. Data + actions in subsequent slices.

struct AgentsView: View {

    @EnvironmentObject private var appState: AppState
    @State private var viewModel = AgentsViewModel()
    @State private var selectedAgent: Agent?
    @State private var showingLogStream: Agent?
    @State private var agentsFilter: AgentsFilter = .active

    enum AgentsFilter: String, CaseIterable, Identifiable {
        case all, active, support, archived
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 16)

                    agentsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    lanesStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    workersSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    computeStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    natsStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80)
                }
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable {
                await viewModel.loadAgents()
                await viewModel.loadAllInboxTails()
            }
            .sheet(item: $selectedAgent) { agent in
                AgentDetailSheet(
                    agent: agent,
                    onViewLogs: { showingLogStream = agent },
                    onStatusChanged: { newStatus in
                        Task { await viewModel.updateAgentState(agent.id, newStatus) }
                    },
                    onPause: { Task { await viewModel.pauseAgent(agent.id) } },
                    onRestart: { Task { await viewModel.restartAgent(agent.id) } },
                    onStartChat: { appState.pendingDirectChatAgentId = agent.name.lowercased() }
                )
            }
            .fullScreenCover(item: $showingLogStream) { agent in
                LogStreamView(agent: agent)
            }
            .task {
                await viewModel.loadAgents()
                viewModel.subscribeToAgentState()
                await viewModel.loadAllInboxTails()
            }
            .onDisappear { viewModel.disconnectSSE() }
        }
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Agents")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            Text("The crew — who's alive, who's doing what.")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - AGENTS Section (§3)

    private var agentsSection: some View {
        let allFiltered = filteredAgents
        return VStack(spacing: 0) {
            HStack {
                Text("AGENTS · \(activeCount) active")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            filterChipRow
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.agents.isEmpty {
                    skeletonAgentRows
                } else if allFiltered.isEmpty {
                    emptyState(icon: "person.crop.circle.dashed", text: "No agents matching filter. Try All.")
                } else {
                    ForEach(Array(allFiltered.enumerated()), id: \.element.id) { idx, agent in
                        VStack(spacing: 0) {
                            if idx > 0 {
                                Divider().background(AppColors.border).padding(.horizontal, 14)
                            }
                            agentRow(agent)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedAgent = agent }
                        }
                    }
                }
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
        }
    }

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AgentsFilter.allCases) { filter in
                    let isOn = agentsFilter == filter
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { agentsFilter = filter }
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                            .foregroundColor(isOn ? Color.black : AppColors.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(isOn ? AppColors.textPrimary : Color.clear)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(isOn ? Color.clear : AppColors.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 30)
                }
            }
        }
    }

    private var filteredAgents: [Agent] {
        let all = viewModel.agents
        switch agentsFilter {
        case .all:      return AgentRosterPolicy.filterActive(all) + AgentRosterPolicy.filterDormant(all)
        case .active:   return all.filter { $0.rosterLane == .activeMain }
                             .sorted { AgentRosterPolicy.sortKey(for: $0.name) < AgentRosterPolicy.sortKey(for: $1.name) }
        case .support:  return all.filter { $0.rosterLane == .supportRuntime }
                             .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .archived: return AgentRosterPolicy.filterDormant(all)
        }
    }

    private var activeCount: Int {
        viewModel.agents.filter { $0.rosterLane == .activeMain }.count
    }

    // Per spec §3.2 — emoji avatar (charter-tinted), name, charter line, last-seen, NATS lane.
    private func agentRow(_ agent: Agent) -> some View {
        HStack(spacing: 12) {
            agentGlyph(agent)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    let unread = viewModel.unreadCount(for: agent.name)
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                    }
                }
                Text(agent.role)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                statusPill(agent)
                Text((agent.lastActivity ?? Date()).relativeFormatted)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
    }

    // Charter-tinted background, emoji glyph centered. Mapping from TEAM.md (verified).
    private func agentGlyph(_ agent: Agent) -> some View {
        let n = agent.name.lowercased()
        let emoji: String = {
            switch n {
            case "aloha": return "🌸"
            case "maui": return "🪝"
            case "chief": return "🦅"
            case "rooster": return "🐓"
            case "coral": return "🪸"
            case "reef": return "🐚"
            case "aurora": return "🌋"
            case "shaka", "shaka-agent": return "🤙"
            case "luna": return "🌙"
            default: return "🐠"
            }
        }()
        let tint = Color(hexString: agent.avatarColor ?? "#6B46C1")
        return ZStack {
            Circle().fill(tint.opacity(0.18)).frame(width: 36, height: 36)
            Circle().strokeBorder(tint.opacity(0.4), lineWidth: 1).frame(width: 36, height: 36)
            Text(emoji).font(.system(size: 20))
        }
    }

    private func statusPill(_ agent: Agent) -> some View {
        let (label, color): (String, Color) = {
            if AgentRosterPolicy.isDormantOrArchived(agent) {
                return ("archived", AppColors.textTertiary)
            }
            switch agent.rosterLane {
            case .activeMain:     return ("active", AppColors.accentSuccess)
            case .supportRuntime: return ("support", AppColors.accentSuccess.opacity(0.7))
            case .dormantArchive: return ("archived", AppColors.textTertiary)
            case .unknown:        return ("review", AppColors.accentWarning)
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
        }
    }

    // MARK: - LANES mini-strip (Addendum A.2: Merman lives here, not in WORKERS)

    private var lanesStrip: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LANES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            HStack(spacing: 10) {
                laneCard(emoji: "🧜‍♂️", name: "Merman", desc: "Triage (T2 rules)")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }

    private func laneCard(emoji: String, name: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - WORKERS Section (§4) — Slice 1: shell with hardcoded names; dispatch in later slice

    private var workersSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WORKERS · idle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Button {
                    // Slice 5 will wire dispatch sheet.
                } label: {
                    Text("+ Dispatch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            VStack(spacing: 0) {
                workerRow(emoji: "🧜‍♀️", name: "Mermaid", lane: "Bounded worker · briefs, evidence", status: "live", statusColor: AppColors.accentSuccess)
                Divider().background(AppColors.border).padding(.horizontal, 14)
                workerRow(emoji: "🐢", name: "Turtle", lane: "Slow-path coordinator", status: "building", statusColor: AppColors.accentWarning)
                Divider().background(AppColors.border).padding(.horizontal, 14)
                workerRow(emoji: "⛏️", name: "Miner", lane: "Index, extraction, mining", status: "live", statusColor: AppColors.accentSuccess)
                Divider().background(AppColors.border).padding(.horizontal, 14)
                workerRow(emoji: "🦪", name: "Pearl", lane: "Spawned Claude pearls (Maui-only)", status: "live", statusColor: AppColors.accentSuccess)
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
        }
    }

    private func workerRow(emoji: String, name: String, lane: String, status: String, statusColor: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusColor.opacity(0.15)).frame(width: 36, height: 36)
                Text(emoji).font(.system(size: 20))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(lane)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    // MARK: - COMPUTE strip (§6) — placeholders this slice

    private var computeStrip: some View {
        HStack(spacing: 16) {
            Text("COMPUTE")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            stripStat("—", "calls/hr")
            stripStat("—", "mix")
            stripStat("—", "anon")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }

    // MARK: - NATS strip (§7) — placeholders this slice

    private var natsStrip: some View {
        HStack(spacing: 12) {
            Text("NATS")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            Circle().fill(AppColors.textTertiary).frame(width: 8, height: 8)
            Text("status pending")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textTertiary)
            Spacer(minLength: 0)
            Text("last: —")
                .font(.system(size: 11))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }

    private func stripStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(AppColors.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AppColors.textTertiary)
        }
    }

    // MARK: - Skeleton / Empty helpers

    private var skeletonAgentRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(AppColors.backgroundTertiary).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(AppColors.backgroundTertiary).frame(width: 90, height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(AppColors.backgroundTertiary).frame(width: 140, height: 10)
                    }
                    Spacer()
                }
                .padding(14)
                Divider().background(AppColors.border)
            }
        }
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.textTertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(14)
    }
}

// MARK: - Agent Status Extension (kept for back-compat with other surfaces)

extension AgentState {
    var color: Color {
        switch self {
        case .online: return AppColors.accentSuccess
        case .busy:   return AppColors.accentWarning
        case .idle:   return AppColors.textTertiary
        case .offline: return AppColors.textMuted
        case .error:  return AppColors.accentDanger
        case .provisioning: return AppColors.accentWarning
        }
    }

    static var displayOrder: [AgentState] {
        [.online, .busy, .idle, .error, .offline]
    }
}

// MARK: - Date Relative Formatting

extension Date {
    var relativeFormatted: String {
        let seconds = Int(-timeIntervalSinceNow)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let mins = seconds / 60
            return "\(mins)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else {
            let days = seconds / 86400
            return "\(days)d ago"
        }
    }
}
