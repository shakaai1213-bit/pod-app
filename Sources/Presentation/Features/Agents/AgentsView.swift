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
                viewModel.subscribeToAgentState()
                await viewModel.loadAllInboxTails()
            }
            .onDisappear { viewModel.disconnectSSE() }
        }
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
                            selectedFocusCard = card
                        }
                }
            }

            deputyStrip
        }
    }

    private func focusCardView(_ card: AgentFocusCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.emoji)
                    .font(.system(size: 22))
                Text(card.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Spacer(minLength: 8)
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

            Divider()

            // STRETCH
            VStack(alignment: .leading, spacing: 2) {
                Text("STRETCH")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Text(card.stretch ?? "—")
                    .font(.system(size: 12))
                    .foregroundColor(card.stretch != nil ? AppColors.textPrimary : AppColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // ROADMAP
            VStack(alignment: .leading, spacing: 2) {
                Text("ROADMAP")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Text(card.roadmap ?? "—")
                    .font(.system(size: 12))
                    .foregroundColor(card.roadmap != nil ? AppColors.textPrimary : AppColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Divider()

            // Today's 3
            VStack(alignment: .leading, spacing: 3) {
                Text("TODAY'S 3")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                ForEach(Array(card.focusAreas.prefix(3).enumerated()), id: \.offset) { idx, area in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(idx + 1).")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)
                        Text(area.label)
                            .font(.system(size: 12))
                            .foregroundColor(area.label == "Loading..." ? AppColors.textTertiary : AppColors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }

            // Fish + skeleton note
            HStack {
                if card.isSkeleton {
                    Text("waiting for ORCA focus-card endpoint")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
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

private struct AgentFocusCard: Identifiable, Hashable {
    let agentId: String
    let displayName: String
    let emoji: String
    let charter: String
    let focusAreas: [AgentFocusArea]
    let fish: AgentFocusFish
    let lastLogExcerpt: String?
    let lastUpdated: Date?
    let isSkeleton: Bool
    // Reframe: STRETCH + ROADMAP (Tony 2026-05-25)
    let stretch: String?
    let roadmap: String?

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

    static func skeleton(agentId: String) -> AgentFocusCard {
        let meta = AgentFocusDefaults.mainAgentMeta[agentId]!
        return AgentFocusCard(
            agentId: agentId,
            displayName: meta.name,
            emoji: meta.emoji,
            charter: meta.charter,
            focusAreas: [
                AgentFocusArea(id: "1", label: "Loading...", evidenceRef: nil),
                AgentFocusArea(id: "2", label: "", evidenceRef: nil),
                AgentFocusArea(id: "3", label: "", evidenceRef: nil)
            ],
            fish: AgentFocusFish(name: "TBD", icon: "—"),
            lastLogExcerpt: nil,
            lastUpdated: nil,
            isSkeleton: true,
            stretch: nil,
            roadmap: nil
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
        do {
            let dto: AgentFocusCardDTO = try await APIClient.shared.get(path: "/api/v1/agents/\(agentId)/focus-card")
            return dto.toDomain(fallbackId: agentId)
        } catch {
            return AgentFocusCard.skeleton(agentId: agentId)
        }
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
    let stretch: String?
    let roadmap: String?

    enum CodingKeys: String, CodingKey {
        case charter, fish, stretch, roadmap
        case agentId = "agent_id"
        case displayName = "display_name"
        case focusAreas = "focus_areas"
        case lastLogExcerpt = "last_log_excerpt"
        case lastUpdated = "last_updated"
    }

    func toDomain(fallbackId: String) -> AgentFocusCard {
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

        return AgentFocusCard(
            agentId: id,
            displayName: displayName.replacingOccurrences(of: meta.emoji, with: "").trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: meta.emoji,
            charter: charter.isEmpty ? meta.charter : charter,
            focusAreas: paddedAreas,
            fish: AgentFocusFish(name: fish?.name ?? "TBD", icon: fish?.icon ?? "—"),
            lastLogExcerpt: lastLogExcerpt,
            lastUpdated: lastUpdated,
            isSkeleton: false,
            stretch: stretch,
            roadmap: roadmap
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("FOCUS AREAS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.textTertiary)
                        ForEach(Array(card.focusAreas.prefix(3).enumerated()), id: \.offset) { idx, area in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(idx + 1). \(area.label)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AppColors.textPrimary)
                                if let evidence = area.evidenceRef, !evidence.isEmpty {
                                    Text(evidence)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(AppColors.textTertiary)
                                }
                            }
                        }
                    }

                    HStack {
                        fishPill
                        Spacer()
                        Text(card.lastUpdatedLabel)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                    }

                    if let excerpt = card.lastLogExcerpt, !excerpt.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LAST LOG")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.textTertiary)
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
