import SwiftUI

// MARK: - Agents View (Cockpit, per SPEC-POD-AGENTS-TAB-2026-05-23)
// Slice 1: section frames + headers + design tokens wired. Data + actions in subsequent slices.

struct AgentsView: View {

    @EnvironmentObject private var appState: AppState
    @State private var viewModel = AgentsViewModel()
    @State private var focusModel = AgentFocusCardsModel()
    @State private var selectedAgent: Agent?
    @State private var selectedFocusCard: AgentFocusCard?
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

                    focusCardsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    protectedChiefFundSection
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
                await focusModel.load(force: true)
                await viewModel.loadAgents()
                await viewModel.loadAllInboxTails()
            }
            .sheet(item: $selectedFocusCard) { card in
                AgentFocusCardDetailSheet(card: card)
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
                await focusModel.load()
                await viewModel.loadAgents()
                consumePendingActivationAgent()
                viewModel.subscribeToAgentState()
                await viewModel.loadAllInboxTails()
            }
            .onDisappear { viewModel.disconnectSSE() }
        }
    }

    @MainActor
    private func consumePendingActivationAgent() {
        let name = UserDefaults.standard.string(forKey: "pod.pendingActivationAgentName")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let name, !name.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: "pod.pendingActivationAgentName")
        selectedAgent = viewModel.agents.first { $0.name.lowercased() == name }
    }

    // MARK: - FOCUS CARDS

    private var focusCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FOCUS CARDS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                if focusModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(focusModel.mainCards) { card in
                    focusCardView(card)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let agent = agentForFocusCard(card) {
                                selectedAgent = agent
                            } else {
                                selectedFocusCard = card
                            }
                        }
                }
            }

            deputyStrip
        }
    }

    private func focusCardView(_ card: AgentFocusCard) -> some View {
        let agent = agentForFocusCard(card)
        return VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.emoji)
                    .font(.system(size: 22))
                Text(card.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                if let agent {
                    focusStatusPill(agent)
                }
                Spacer(minLength: 8)
                if let unread = agent.map({ viewModel.unreadCount(for: $0.name) }), unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                }
                Text(card.lastUpdatedLabel)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }

            // Charter
            Text(card.charter)
                .font(.system(size: 12))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let agent {
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(agent.status.color)
                    Text(agent.currentTask ?? agent.role)
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text((agent.lastActivity ?? Date()).relativeFormatted)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(agent.status.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            Divider()

            // STRETCH + ROADMAP side-by-side (Tony 2026-05-25 reframe)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STRETCH")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                        .kerning(0.5)
                    ForEach(Array(card.stretch.prefix(3).enumerated()), id: \.offset) { idx, item in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(idx + 1).")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppColors.textTertiary)
                            Text(item.isEmpty ? "—" : item)
                                .font(.system(size: 11))
                                .foregroundColor(item.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ROADMAP")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                        .kerning(0.5)
                    roadmapRow("30d", card.roadmap.d30)
                    roadmapRow("60d", card.roadmap.d60)
                    roadmapRow("90d", card.roadmap.d90)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // THIS WEEK — from GET /api/v1/agents/{name}/weekly-plan (graceful 404 = nil)
            VStack(alignment: .leading, spacing: 4) {
                Text("THIS WEEK")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                if let milestones = card.thisWeek {
                    ForEach(Array(milestones.prefix(5).enumerated()), id: \.element.id) { _, milestone in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(milestone.statusDot)
                                .font(.system(size: 11))
                            Text(milestone.title)
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } else {
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            Divider()

            // Today's 3 from morning daily log + Fish chip
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TODAY'S 3")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                        .kerning(0.5)
                    if card.isSkeleton {
                        Text("waiting for morning log")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                    } else {
                        ForEach(Array(card.focusAreas.prefix(3).enumerated()), id: \.offset) { idx, area in
                            if !area.label.isEmpty {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(idx + 1).")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(AppColors.textTertiary)
                                    Text(area.label)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                fishChip(card.fish)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(card.tint.opacity(0.35), lineWidth: 1)
        )
    }

    private func agentForFocusCard(_ card: AgentFocusCard) -> Agent? {
        viewModel.agents.first { $0.name.lowercased() == card.id }
    }

    private func focusStatusPill(_ agent: Agent) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(agent.status.color)
                .frame(width: 6, height: 6)
            Text(agent.status.displayName.lowercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(agent.status.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(agent.status.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var deputyStrip: some View {
        HStack(spacing: 8) {
            ForEach(focusModel.deputies) { deputy in
                let agent = viewModel.agents.first { $0.name.localizedCaseInsensitiveCompare(deputy.displayName) == .orderedSame }
                HStack(spacing: 8) {
                    Text(deputy.emoji)
                        .font(.system(size: 18))
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(deputy.displayName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                            Circle()
                                .fill(agent?.status.color ?? deputy.statusColor)
                                .frame(width: 6, height: 6)
                        }
                        Text(agent?.currentTask ?? deputy.currentTicket)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 64)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(AppColors.border, lineWidth: 0.5)
                )
            }
        }
    }

    private func roadmapRow(_ horizon: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(horizon)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(AppColors.accentElectric)
                .frame(width: 24, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 11))
                .foregroundColor(value.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                .lineLimit(2)
        }
    }

    private func fishChip(_ fish: AgentFocusFish) -> some View {
        HStack(spacing: 4) {
            Text(fish.icon)
            Text(fish.name)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(AppColors.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(AppColors.backgroundTertiary)
        .clipShape(Capsule())
    }

    // MARK: - Protected Chief/Fund

    private var protectedChiefFundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("PROTECTED · CHIEF/FUND")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Text("Read-only")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.accentWarning)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppColors.accentWarning.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 2)

            Text("P&L, positions, orders, wallets, bot changes, and kill switches stay Chief/Rooster/Tony gated. Pod shows registry context only.")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
                .padding(10)
                .background(AppColors.accentWarning.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(ChiefFundContent.bots) { bot in
                    chiefFundMiniCard(bot)
                }
            }
        }
    }

    private func chiefFundMiniCard(_ bot: ChiefFundBot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(bot.emoji)
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bot.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(bot.owner)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    Image(systemName: bot.mode.icon)
                        .font(.system(size: 8, weight: .bold))
                    Text(bot.mode.label)
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(bot.mode.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(bot.mode.color.opacity(0.12))
                .clipShape(Capsule())
            }

            Text(bot.role)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)

            Text(bot.reviewGate.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.accentWarning)
                .lineLimit(1)
        }
        .padding(10)
        .frame(minHeight: 92, alignment: .topLeading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppColors.accentWarning.opacity(0.18), lineWidth: 1)
        )
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

// MARK: - Agent Focus Cards

private struct AgentFocusArea: Identifiable, Hashable {
    let id: String
    let label: String
    let evidenceRef: String?
}

private struct AgentFocusFish: Hashable {
    let name: String
    let icon: String
}

// L7c reshape (SPEC-POD-AGENT-FOCUS-CARDS v1, Tony 2026-05-25):
// Card = STRETCH (3 aspirational items) + ROADMAP (30d/60d/90d) + THIS WEEK + Fish + Today's 3.

private struct WeeklyMilestone: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
    let status: String  // "planned" | "shipped" | "dropped"

    var statusDot: String {
        switch status {
        case "shipped": return "✅"
        case "dropped": return "❌"
        default:        return "🔲"
        }
    }
}

private struct AgentRoadmap: Hashable {
    let d30: String
    let d60: String
    let d90: String

    static let empty = AgentRoadmap(d30: "", d60: "", d90: "")
}

private struct AgentFocusCard: Identifiable, Hashable {
    let agentId: String
    let displayName: String
    let emoji: String
    let charter: String
    let stretch: [String]            // 3 aspirational areas (REFRAME)
    let roadmap: AgentRoadmap         // 30d / 60d / 90d trajectory
    let thisWeek: [WeeklyMilestone]?  // Weekly plan milestones from /api/v1/agents/{name}/weekly-plan
    let focusAreas: [AgentFocusArea]  // Today's 3 from morning daily log
    let fish: AgentFocusFish
    let lastLogExcerpt: String?
    let lastUpdated: Date?
    let isSkeleton: Bool

    var id: String { agentId.lowercased() }

    var tint: Color {
        switch id {
        case "maui": return AppColors.accentSuccess
        case "aloha": return Color(hexString: "A855F7")
        case "chief": return Color(hexString: "22C55E")
        case "rooster": return AppColors.accentDanger
        default: return AppColors.accentElectric
        }
    }

    var lastUpdatedLabel: String {
        guard let lastUpdated else { return "pending" }
        return lastUpdated.relativeFormatted
    }

    /// Render spec v1 defaults before the daily-log extractor petal wires up.
    static func skeleton(agentId: String) -> AgentFocusCard {
        let meta = AgentFocusDefaults.mainAgentMeta[agentId]!
        return AgentFocusCard(
            agentId: agentId,
            displayName: meta.name,
            emoji: meta.emoji,
            charter: meta.charter,
            stretch: AgentFocusDefaults.stretch[agentId] ?? ["", "", ""],
            roadmap: AgentFocusDefaults.roadmap[agentId] ?? .empty,
            thisWeek: nil,
            focusAreas: [
                AgentFocusArea(id: "1", label: "Waiting for morning log", evidenceRef: nil),
                AgentFocusArea(id: "2", label: "", evidenceRef: nil),
                AgentFocusArea(id: "3", label: "", evidenceRef: nil)
            ],
            fish: AgentFocusDefaults.fish[agentId] ?? AgentFocusFish(name: "—", icon: "—"),
            lastLogExcerpt: nil,
            lastUpdated: nil,
            isSkeleton: true
        )
    }
}

private struct AgentFocusDeputy: Identifiable {
    let id: String
    let displayName: String
    let emoji: String
    let currentTicket: String
    let statusColor: Color
}

private enum AgentFocusDefaults {
    static let mainAgentOrder = ["maui", "aloha", "chief", "rooster"]
    static let mainAgentMeta: [String: (name: String, emoji: String, charter: String)] = [
        "maui": ("Maui", "🪝", "Pod / Lifecycle / Compute / Codex orchestrator"),
        "aloha": ("Aloha", "🌸", "Backbone / Nerve / Flywheel / Doctrine gate"),
        "chief": ("Chief", "🦅", "Trading / P&L / Funding"),
        "rooster": ("Rooster", "🐓", "Security / Research / Knowledge")
    ]

    // SPEC-POD-AGENT-FOCUS-CARDS-2026-W22 v1 defaults — render before extractor petal lands.
    static let stretch: [String: [String]] = [
        "maui":    ["Speed of build", "Architectural taste", "Codex orchestration mastery"],
        "aloha":   ["Crisp communication", "Organized team", "ORCA standards"],
        "chief":   ["Disciplined trading conviction", "Funding velocity", "Learning loop compounding"],
        "rooster": ["Security posture", "Adversarial thinking", "Research depth"]
    ]

    static let roadmap: [String: AgentRoadmap] = [
        "maui": AgentRoadmap(
            d30: "Pod cockpit V1 LIVE",
            d60: "Memory Spine V2 + Project Automation v1.0",
            d90: "Voice surface Phase 1 + Jarvis Arms autonomous"
        ),
        "aloha": AgentRoadmap(
            d30: "Wiki→Pod auto-pairing fully closed",
            d60: "Doc-ledger drives weekly retro signal",
            d90: "agent_focus_card as ORCA entity"
        ),
        "chief": AgentRoadmap(
            d30: "Funding-squeeze v1.4 LIVE",
            d60: "Live capital deployment gate passed",
            d90: "Strategy Journal sources forward bets"
        ),
        "rooster": AgentRoadmap(
            d30: "35341da6 closed + harm-gate doctrine LIVE",
            d60: "Guardian Phase 2 secure-by-design",
            d90: "Security telemetry visible on Pod Dashboard"
        )
    ]

    static let fish: [String: AgentFocusFish] = [
        "maui":    AgentFocusFish(name: "Starfish",   icon: "⭐"),
        "aloha":   AgentFocusFish(name: "Held",       icon: "—"),
        "chief":   AgentFocusFish(name: "Chieffish",  icon: "🐟"),
        "rooster": AgentFocusFish(name: "Roosterfish", icon: "🐔")
    ]
}

@MainActor
@Observable
private final class AgentFocusCardsModel {
    private(set) var mainCards: [AgentFocusCard] = AgentFocusDefaults.mainAgentOrder.map { AgentFocusCard.skeleton(agentId: $0) }
    let deputies: [AgentFocusDeputy] = [
        AgentFocusDeputy(id: "coral", displayName: "Coral", emoji: "🪸", currentTicket: "Compute support", statusColor: AppColors.accentSuccess),
        AgentFocusDeputy(id: "reef", displayName: "Reef", emoji: "🐡", currentTicket: "Tools support", statusColor: AppColors.accentSuccess)
    ]
    private(set) var isLoading = false

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && mainCards.contains(where: { !$0.isSkeleton }) { return }

        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: AgentFocusCard.self) { group in
            for agentId in AgentFocusDefaults.mainAgentOrder {
                group.addTask {
                    await Self.loadCard(agentId: agentId)
                }
            }

            var loaded: [AgentFocusCard] = []
            for await card in group {
                loaded.append(card)
            }
            mainCards = AgentFocusDefaults.mainAgentOrder.compactMap { id in
                loaded.first { $0.id == id }
            }
        }
    }

    private static func loadCard(agentId: String) async -> AgentFocusCard {
        // Fetch focus card + weekly plan concurrently; graceful fallback on either.
        async let focusCardResult: AgentFocusCardDTO? = {
            (try? await APIClient.shared.get(path: "/api/v1/agents/\(agentId)/focus-card"))
        }()
        async let weeklyPlanResult: [WeeklyMilestone]? = {
            (try? await APIClient.shared.get(path: "/api/v1/agents/\(agentId)/weekly-plan"))
        }()

        let (dto, weeklyPlan) = await (focusCardResult, weeklyPlanResult)
        guard let dto else { return AgentFocusCard.skeleton(agentId: agentId) }
        return dto.toDomain(fallbackId: agentId, weeklyPlan: weeklyPlan)
    }
}

private struct AgentFocusCardDTO: Decodable {
    let agentId: String
    let displayName: String
    let charter: String
    let focusAreas: [FocusAreaDTO]
    let fish: FishDTO?
    let lastLogExcerpt: String?
    let lastUpdated: Date?
    let stretch: [String]?
    let roadmap: RoadmapDTO?
    let thisWeek: [WeeklyMilestone]?

    enum CodingKeys: String, CodingKey {
        case charter, fish, stretch, roadmap
        case agentId = "agent_id"
        case displayName = "display_name"
        case focusAreas = "focus_areas"
        case lastLogExcerpt = "last_log_excerpt"
        case lastUpdated = "last_updated"
        case thisWeek = "this_week"
    }

    func toDomain(fallbackId: String, weeklyPlan: [WeeklyMilestone]? = nil) -> AgentFocusCard {
        let id = agentId.lowercased()
        let meta = AgentFocusDefaults.mainAgentMeta[id] ?? AgentFocusDefaults.mainAgentMeta[fallbackId]!
        let normalizedAreas = Array(focusAreas.prefix(3)).enumerated().map { idx, area in
            AgentFocusArea(
                id: String(area.id ?? idx + 1),
                label: area.label,
                evidenceRef: area.evidenceRef
            )
        }
        let paddedAreas = normalizedAreas + (normalizedAreas.count..<3).map {
            AgentFocusArea(id: String($0 + 1), label: "", evidenceRef: nil)
        }

        // STRETCH + ROADMAP fall back to spec v1 defaults when API omits them.
        let stretchValues = stretch.map { Array($0.prefix(3)) + Array(repeating: "", count: max(0, 3 - $0.count)) }
            ?? AgentFocusDefaults.stretch[id] ?? ["", "", ""]
        let roadmapValue = roadmap.map { AgentRoadmap(d30: $0.d30 ?? "", d60: $0.d60 ?? "", d90: $0.d90 ?? "") }
            ?? AgentFocusDefaults.roadmap[id] ?? .empty
        let fishValue = fish.map { AgentFocusFish(name: $0.name, icon: $0.icon) }
            ?? AgentFocusDefaults.fish[id] ?? AgentFocusFish(name: "—", icon: "—")

        // weekly-plan endpoint takes precedence; DTO field is fallback; nil = endpoint not live yet.
        let thisWeekValue = weeklyPlan ?? thisWeek

        return AgentFocusCard(
            agentId: id,
            displayName: displayName.replacingOccurrences(of: meta.emoji, with: "").trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: meta.emoji,
            charter: charter.isEmpty ? meta.charter : charter,
            stretch: stretchValues,
            roadmap: roadmapValue,
            thisWeek: thisWeekValue,
            focusAreas: paddedAreas,
            fish: fishValue,
            lastLogExcerpt: lastLogExcerpt,
            lastUpdated: lastUpdated,
            isSkeleton: false
        )
    }

    struct FocusAreaDTO: Decodable {
        let id: Int?
        let label: String
        let evidenceRef: String?

        enum CodingKeys: String, CodingKey {
            case id, label
            case evidenceRef = "evidence_ref"
        }
    }

    struct FishDTO: Decodable {
        let name: String
        let icon: String
    }

    struct RoadmapDTO: Decodable {
        let d30: String?
        let d60: String?
        let d90: String?

        enum CodingKeys: String, CodingKey {
            case d30 = "30d"
            case d60 = "60d"
            case d90 = "90d"
        }
    }
}

private struct AgentFocusCardDetailSheet: View {
    let card: AgentFocusCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Text(card.emoji)
                            .font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(AppColors.textPrimary)
                            Text(card.charter)
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Spacer()
                    }

                    // STRETCH (3 aspirational areas)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STRETCH")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.textTertiary)
                            .kerning(0.5)
                        ForEach(Array(card.stretch.prefix(3).enumerated()), id: \.offset) { idx, item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(AppColors.textTertiary)
                                Text(item.isEmpty ? "—" : item)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(item.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // ROADMAP (30d/60d/90d trajectory)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROADMAP")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.textTertiary)
                            .kerning(0.5)
                        detailRoadmapRow("30d", card.roadmap.d30)
                        detailRoadmapRow("60d", card.roadmap.d60)
                        detailRoadmapRow("90d", card.roadmap.d90)
                    }

                    HStack {
                        fishPill
                        Spacer()
                        Text(card.lastUpdatedLabel)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                    }

                    // Today's 3 from morning daily log
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TODAY'S 3 (from morning log)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.textTertiary)
                            .kerning(0.5)
                        if card.isSkeleton {
                            Text("Waiting for morning log extraction")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textTertiary)
                        } else {
                            ForEach(Array(card.focusAreas.prefix(3).enumerated()), id: \.offset) { idx, area in
                                if !area.label.isEmpty {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("\(idx + 1).")
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                            .foregroundColor(AppColors.textTertiary)
                                        Text(area.label)
                                            .font(.system(size: 13))
                                            .foregroundColor(AppColors.textPrimary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }

                    if let excerpt = card.lastLogExcerpt, !excerpt.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LAST LOG")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.textTertiary)
                                .kerning(0.5)
                            Text(excerpt)
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(20)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Focus Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppColors.accentElectric)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var fishPill: some View {
        HStack(spacing: 5) {
            Text(card.fish.icon)
            Text(card.fish.name)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(AppColors.textSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(AppColors.backgroundSecondary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppColors.border, lineWidth: 0.5))
    }

    private func detailRoadmapRow(_ horizon: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(horizon)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(AppColors.accentElectric)
                .frame(width: 36, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13))
                .foregroundColor(value.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
