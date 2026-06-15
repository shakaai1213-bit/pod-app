import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    // Persistent ViewModels — survive tab switches
    @State private var directChatViewModel = DirectChatViewModel()
    // Use @State to track selected tab - force SwiftUI to see changes
    @State private var selectedTab: AppTab = .dashboard
    // Observation token to force refresh
    @State private var tabChangeCounter: Int = 0
    // Force SwiftUI to recompose when auth state changes
    @State private var authStateKey: Int = 0
    // Hide tab bar when keyboard is visible
    @State private var isKeyboardVisible = false

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            // Use authStateKey to force SwiftUI to treat as new identity on change
            // This prevents the LoginView from "sticking" during render cycles
            if appState.isAuthenticated {
                mainTabView
                    .id("main-\(authStateKey)")
            } else {
                LoginView()
                    .id("login-\(authStateKey)")
            }

            // Global loading overlay — separate from auth state
            // Hidden when error is shown so the error sheet can be interacted with
            if appState.isLoading && !appState.showError {
                loadingOverlay
            }
        }
        .onChange(of: appState.isAuthenticated) { _, newValue in
            // Bump the key to force fresh view identity when auth changes
            authStateKey += 1
            print("[ContentView] auth state changed to \(newValue), key now \(authStateKey)")
        }
        .sheet(isPresented: Binding(
            get: { appState.showError },
            set: { appState.showError = $0 }
        )) {
            errorSheet
        }
    }

    // MARK: - Tab View

    private var mainTabView: some View {
        ZStack(alignment: .bottom) {
            // Tab content — ignore container safe areas (notch/home indicator) but NOT keyboard
            tabContent
                .ignoresSafeArea(.container, edges: [.top, .horizontal])

            // Custom tab bar — hidden when keyboard is up
            if !isKeyboardVisible {
                customTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                withAnimation(.easeOut(duration: 0.25)) { isKeyboardVisible = true }
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification) {
                withAnimation(.easeOut(duration: 0.25)) { isKeyboardVisible = false }
            }
        }
        .onChange(of: appState.pendingDirectChatAgentId) { _, agentId in
            if appState.pendingDirectChatTicketId != nil {
                return
            }
            guard let agentId, let agentInfo = AgentInfo.find(agentId) else {
                appState.pendingDirectChatAgentId = nil
                return
            }
            // Path B per Shaka 2026-05-07: deep-links to unreachable agents land on
            // the chat tab but don't push into a dead conversation view.
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = .chat }
            if agentInfo.isReachable {
                directChatViewModel.navigationPath = NavigationPath()
                directChatViewModel.navigationPath.append(agentInfo)
            }
            appState.pendingDirectChatAgentId = nil
        }
        .onChange(of: appState.pendingDirectChatTicketId) { _, ticketId in
            guard let ticketId else { return }
            let agentId = appState.pendingDirectChatAgentId ?? "maui"
            guard let agentInfo = AgentInfo.find(agentId) ?? AgentInfo.find("maui") else {
                appState.pendingDirectChatTicketId = nil
                appState.pendingDirectChatTicketTitle = nil
                appState.pendingDirectChatAgentId = nil
                appState.pendingDirectChatChannelId = nil
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = .chat }
            directChatViewModel.continueWithTicket(
                ticketId: ticketId,
                ticketTitle: appState.pendingDirectChatTicketTitle ?? ticketId,
                agent: agentInfo,
                channelId: appState.pendingDirectChatChannelId
            )
            appState.pendingDirectChatTicketId = nil
            appState.pendingDirectChatTicketTitle = nil
            appState.pendingDirectChatAgentId = nil
            appState.pendingDirectChatChannelId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pod.openWorkFlowFilter"))) { _ in
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = .work }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        // MARK: Primary 7-tab structure (L1 revamp 2026-W22)
        if selectedTab == .dashboard {
            DashboardView()
        } else if selectedTab == .chat {
            SonarView(viewModel: directChatViewModel)
        } else if selectedTab == .work {
            WorkView()
        } else if selectedTab == .crew {
            // L2: Crew tab = CrewTabView with 2-segment picker.
            // Agents segment: Focus + Agents + Workers + Protected Fund (via AgentsView).
            // Arms segment: 8 arm cards + TEAM strip (via ArmsTabView).
            CrewTabView()
        } else if selectedTab == .knowledge {
            KnowledgeView()
        } else if selectedTab == .lab {
            LabView()
        } else if selectedTab == .runtime {
            RuntimeView()
        } else if selectedTab == .maker {
            MakerView()
        } else if selectedTab == .system {
            SystemView()
        // MARK: Legacy aliases — routable via deep-link for 30-day dwell period
        } else if selectedTab == .arms {
            ArmsTabView()
        } else if selectedTab == .agents {
            AgentsView()
        } else if selectedTab == .captainsLog {
            CaptainsLogView()
        } else {
            Color.clear
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                tabBarButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 24) // Safe area bottom padding
        .background(AppColors.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    private var visibleTabs: [AppTab] {
        // Legacy cases excluded from bar (still deep-linkable).
        [.dashboard, .chat, .work, .crew, .knowledge, .lab, .runtime, .maker]
    }

    private func tabBarButton(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AppColors.accentElectric : AppColors.textSecondary)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AppColors.accentElectric : AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppColors.accentElectric.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: AppTheme.spacingLG) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.primaryAccent)
                    .scaleEffect(1.4)

                if let message = appState.loadingMessage {
                    Text(message)
                        .font(.body)
                        .foregroundColor(AppTheme.secondaryText)
                }

                // Escape hatch — dismiss spinner AND show the error so user knows what happened
                Button {
                    appState.isLoading = false
                    // Keep isAuthenticated=false and showError=true so the error sheet appears
                    // and explains WHY the connection failed
                } label: {
                    Text("Reset / Retry")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                        .underline()
                }
            }
            .padding(AppTheme.spacingXL)
            .background(AppTheme.surfaceElevated)
            .cornerRadius(AppTheme.radiusLarge)
            .shadow(color: AppTheme.glowAccent, radius: 20)
        }
    }

    // MARK: - Error Sheet

    private var errorSheet: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacingLG) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppTheme.error)

                Text(appState.errorMessage ?? "Something went wrong")
                    .font(.title2)
                    .foregroundColor(AppTheme.primaryText)
                    .multilineTextAlignment(.center)

                if let details = appState.errorDetails, !details.isEmpty {
                    ScrollView {
                        Text(details)
                            .font(.caption)
                            .foregroundColor(AppTheme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                }

                Button(action: { appState.dismissError() }) {
                    Text("Dismiss")
                        .font(.body.bold())
                        .foregroundColor(AppTheme.inverseText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacingSM)
                        .background(AppTheme.primaryAccent)
                        .cornerRadius(AppTheme.radiusMedium)
                }
                .padding(.horizontal, AppTheme.spacingXL)
            }
            .padding(AppTheme.spacingXL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.surface)
            .navigationTitle("Error")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

private enum RuntimeSurfaceMode: String, CaseIterable {
    case overview
    case fleet
    case system
    case tags

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .fleet: return "Fleet"
        case .system: return "System"
        case .tags: return "Tags"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "waveform.path.ecg"
        case .fleet: return "server.rack"
        case .system: return "cpu"
        case .tags: return "tag"
        }
    }
}

private extension String {
    var runtimeDisplayLabel: String {
        replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

private struct RuntimeView: View {
    @State private var model = RuntimeViewModel()
    @State private var selectedMode: RuntimeSurfaceMode = .overview

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    header
                    runtimeModePicker
                    runtimeModeContent
                }
                .padding(.horizontal, Theme.md)
                .padding(.top, Theme.lg)
                .padding(.bottom, Theme.xxl)
            }
            .background(AppColors.backgroundPrimary)
            .refreshable { await model.load() }
            .task { await model.load() }
            .navigationTitle("Runtime")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Runtime")
                    .podTextStyle(.title1, color: AppColors.textPrimary)
                Text("ORCA health, fleet registry, compute routes, and live state tags")
                    .podTextStyle(.body, color: AppColors.textSecondary)
            }

            Spacer()

            Button {
                Task { await model.load() }
            } label: {
                Image(systemName: model.isLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.accentElectric)
                    .frame(width: 38, height: 38)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(Circle())
            }
            .disabled(model.isLoading)
        }
    }

    private var runtimeModePicker: some View {
        Picker("Runtime view", selection: $selectedMode) {
            ForEach(RuntimeSurfaceMode.allCases, id: \.self) { mode in
                Label(mode.title, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var runtimeModeContent: some View {
        switch selectedMode {
        case .overview:
            controlRoomSection
            summaryStrip
            startupTruthSection
            computeSummarySection
            classificationSyncSection
        case .fleet:
            runtimeFleetSection
            computeRoutesSection
            classificationSyncSection
        case .system:
            LabSystemContent()
        case .tags:
            summaryStrip
            tagGroup(title: "Core", prefixes: ["orca.", "nats.", "compute.", "memory."])
            tagGroup(title: "Agents", prefixes: ["agent."])
            tagGroup(title: "Workers", prefixes: ["worker."])
            tagGroup(title: "Surfaces", prefixes: ["surface."])
        }
    }

    private var controlRoomSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CONTROL ROOM")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                    Text(model.controlRoomDigest?.status.runtimeDisplayLabel ?? "Digest unavailable")
                        .podTextStyle(.caption, color: controlRoomColor)
                }

                Spacer()

                if let digest = model.controlRoomDigest {
                    Text("\(digest.signalCount) signal\(digest.signalCount == 1 ? "" : "s")")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(controlRoomColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(controlRoomColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if let digest = model.controlRoomDigest {
                if let generatedAt = digest.generatedAt {
                    Text("Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }

                VStack(alignment: .leading, spacing: Theme.xs) {
                    ForEach(digest.sections.prefix(4)) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Theme.xs) {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                if let status = section.status, !status.isEmpty {
                                    Text(status.runtimeDisplayLabel.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(statusRuntimeColor(status))
                                }
                            }
                            if let summary = section.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            } else if model.isLoading {
                Text("Loading ORCA control room...")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            } else {
                Text("Control room digest unavailable.")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            }
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(controlRoomColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var controlRoomColor: Color {
        statusRuntimeColor(model.controlRoomDigest?.status ?? "unknown")
    }

    private func statusRuntimeColor(_ status: String) -> Color {
        switch status.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "ok", "ready", "running", "active", "loaded", "healthy", "green", "good":
            return AppColors.accentSuccess
        case "warning", "warn", "degraded", "stale", "yellow", "needs_attention":
            return AppColors.accentWarning
        case "error", "failed", "down", "critical", "red", "unavailable":
            return AppColors.accentDanger
        default:
            return AppColors.textTertiary
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: Theme.sm) {
            runtimeMetric("Tags", value: model.tags.count, color: AppColors.accentElectric)
            runtimeMetric("Stale", value: model.staleCount, color: model.staleCount > 0 ? AppColors.accentWarning : AppColors.accentSuccess)
            runtimeMetric("Errors", value: model.errorCount, color: model.errorCount > 0 ? AppColors.accentDanger : AppColors.accentSuccess)
        }
    }

    private var fundSurfaceSection: some View {
        NavigationLink {
            TradingView()
        } label: {
            HStack(alignment: .top, spacing: Theme.sm) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.accentWarning)
                    .frame(width: 32, height: 32)
                    .background(AppColors.accentWarning.opacity(0.10))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Fund Surface")
                        .podTextStyle(.headline, color: AppColors.textPrimary)
                    Text("Read-only Fund landing, earnings quality research, gates, and evidence from ORCA.")
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                        .lineLimit(2)
                    Text("Research only · not a trade signal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentWarning)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.accentWarning.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var runtimeFleetSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Text("FLEET REGISTRY")
                    .podTextStyle(.label, color: AppColors.textTertiary)

                Spacer()

                if let generatedAt = model.runtimeRegistryGeneratedAt {
                    Text(generatedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            if let summary = model.runtimeRegistrySummary {
                HStack(spacing: Theme.sm) {
                    runtimeMetric("Units", value: summary.total, color: AppColors.accentElectric)
                    runtimeMetric("Petals", value: summary.byKind["petal"] ?? 0, color: AppColors.accentSuccess)
                    runtimeMetric("Watchdogs", value: summary.byKind["watchdog"] ?? 0, color: AppColors.accentWarning)
                }

                VStack(spacing: Theme.xs) {
                    ForEach(model.runtimeUnits.prefix(12)) { unit in
                        RuntimeUnitRow(unit: unit) { action in
                            Task { await model.classify(unit: unit, action: action) }
                        }
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
            } else if let error = model.errorMessage {
                Text(error)
                    .podTextStyle(.caption, color: AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private var startupTruthSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("STARTUP TRUTH")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                    Text(model.startupStatus?.ok == true ? "Schoolhouse core is reachable" : "Startup broken — check components below")
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                }

                Spacer()

                if let checkedAt = model.startupStatus?.checkedAt {
                    Text(checkedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            if let status = model.startupStatus {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                    ForEach(status.components) { component in
                        StartupStatusChip(component: component)
                    }
                }
            } else if model.isLoading {
                Text("Loading startup truth...")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            } else {
                Text("Startup truth unavailable.")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            }
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    private var computeRoutesSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("COMPUTE ROUTES")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                    Text(model.computeRouteRegistry?.routerURL ?? "Route registry unavailable")
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if let routes = model.computeRouteRegistry?.routes {
                    Text("\(routes.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.accentElectric)
                }
            }

            if let registry = model.computeRouteRegistry {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                    ForEach(registry.routes) { route in
                        ComputeRouteChip(route: route)
                    }
                }
            } else if model.isLoading {
                Text("Loading compute routes...")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            } else {
                Text("Compute route registry unavailable.")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            }
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    private var computeSummarySection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("COMPUTE HEALTH")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                    Text(model.computeSummary?.status.capitalized ?? "Summary unavailable")
                        .podTextStyle(.caption, color: computeSummaryColor)
                }

                Spacer()

                if let latest = model.computeSummary?.latest {
                    Text((latest.actualTier ?? latest.route).uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(latest.fallbackUsed ? AppColors.accentWarning : AppColors.accentSuccess)
                }
            }

            if let summary = model.computeSummary {
                HStack(spacing: Theme.sm) {
                    runtimeMetric("Runs", value: summary.total, color: AppColors.accentElectric)
                    runtimeMetric("Fallback", value: summary.fallback, color: summary.fallback > 0 ? AppColors.accentWarning : AppColors.accentSuccess)
                    runtimeMetric("Failed", value: summary.failed, color: summary.failed > 0 ? AppColors.accentDanger : AppColors.accentSuccess)
                }

                HStack(spacing: Theme.xs) {
                    computePill("fallback \(Int(summary.fallbackRate * 100))%", color: summary.fallbackRate >= 0.5 ? AppColors.accentWarning : AppColors.textTertiary)
                    computePill("anonymous \(summary.anonymousCount)", color: summary.anonymousCount > 0 ? AppColors.accentWarning : AppColors.textTertiary)
                    if let latency = summary.avgLatencyMs {
                        computePill("\(latency)ms avg", color: AppColors.textTertiary)
                    }
                }

                if let latest = summary.latest {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(latest.taskHint) · \(latest.model ?? "unknown model")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Text(computeRouteLine(latest))
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(2)
                        Text(latest.error ?? latest.backend ?? "No latest error")
                            .font(.caption2)
                            .foregroundStyle(latest.error == nil ? AppColors.textTertiary : AppColors.accentWarning)
                            .lineLimit(2)
                    }
                }
            } else if model.isLoading {
                Text("Loading compute summary...")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            } else {
                Text("Compute summary unavailable.")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            }
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    private var computeSummaryColor: Color {
        switch model.computeSummary?.status {
        case "good": return AppColors.accentSuccess
        case "warning", "degraded": return AppColors.accentWarning
        case "unavailable": return AppColors.accentDanger
        default: return AppColors.textTertiary
        }
    }

    private func computePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.backgroundSecondary)
            .clipShape(Capsule())
    }

    private func computeRouteLine(_ latest: ComputeRunSummaryLatestDTO) -> String {
        let requested = latest.requestedRoute ?? latest.route
        let actual = latest.actualTier ?? latest.route
        let backend = latest.actualBackend ?? latest.backend ?? "unknown backend"
        if requested == actual {
            return "actual \(actual) / \(backend)"
        }
        return "requested \(requested) -> actual \(actual) / \(backend)"
    }

    private var classificationSyncSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CLEANUP REVIEW")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                    if let preview = model.classificationSyncPreview {
                        Text("\(preview.total) reviewed runtime decision\(preview.total == 1 ? "" : "s")")
                            .podTextStyle(.caption, color: AppColors.textSecondary)
                    } else {
                        Text("No reviewed runtime decisions yet")
                            .podTextStyle(.caption, color: AppColors.textSecondary)
                    }
                }

                Spacer()

                Button {
                    Task { await model.exportRuntimeSync() }
                } label: {
                    Image(systemName: model.isExportingRuntimeSync ? "hourglass" : "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.accentElectric)
                        .frame(width: 36, height: 36)
                        .background(AppColors.backgroundSecondary)
                        .clipShape(Circle())
                }
                .disabled(model.isExportingRuntimeSync || (model.classificationSyncPreview?.total ?? 0) == 0)
            }

            if let preview = model.classificationSyncPreview, !preview.byAction.isEmpty {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(preview.byAction.sorted(by: { $0.key < $1.key }), id: \.key) { action, count in
                        Text("\(action.replacingOccurrences(of: "_", with: " ")) \(count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(Capsule())
                    }
                }
            }

            if let message = model.runtimeExportMessage {
                Text(message)
                    .podTextStyle(.caption, color: AppColors.textTertiary)
                    .lineLimit(2)
            }

            if !model.classificationSyncExports.isEmpty {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    ForEach(model.classificationSyncExports.prefix(3)) { artifact in
                        HStack(spacing: Theme.xs) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.accentElectric)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artifact.exportId)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                Text(artifact.markdownPath)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: Theme.xs)
                            Text(artifact.updatedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
                .padding(Theme.xs)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    private func runtimeMetric(_ label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .podTextStyle(.caption, color: AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.sm)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }

    @ViewBuilder
    private func tagGroup(title: String, prefixes: [String]) -> some View {
        let tags = model.tags.filter { tag in prefixes.contains { tag.tagId.hasPrefix($0) } }
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: Theme.sm) {
                Text(title.uppercased())
                    .podTextStyle(.label, color: AppColors.textTertiary)

                VStack(spacing: Theme.xs) {
                    ForEach(tags) { tag in
                        LiveStateRow(tag: tag)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
            }
        }
    }
}

@Observable
private final class RuntimeViewModel {
    var tags: [StateTagDTO] = []
    var runtimeUnits: [RuntimeUnitDTO] = []
    var runtimeRegistrySummary: RuntimeRegistrySummaryDTO?
    var runtimeRegistryGeneratedAt: Date?
    var controlRoomDigest: ControlRoomDigestDTO?
    var classificationSyncPreview: RuntimeClassificationSyncPreviewDTO?
    var classificationSyncExports: [RuntimeClassificationSyncArtifactDTO] = []
    var startupStatus: StartupStatusResponseDTO?
    var computeSummary: ComputeRunSummaryDTO?
    var computeRouteRegistry: ComputeRouteRegistryDTO?
    var runtimeExportMessage: String?
    var isLoading = false
    var isClassifying = false
    var isExportingRuntimeSync = false
    var errorMessage: String?

    var staleCount: Int { tags.filter(\.stale).count }
    var errorCount: Int { tags.filter { $0.quality?.lowercased() == "error" }.count }

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // L5: partial-load resilience — all requests fire in parallel via async let,
        // but each is awaited with try? so one unavailable endpoint doesn't
        // blank the entire Runtime screen.
        async let stateResponse: StateRegistryResponse = APIClient.shared.get(path: "/api/v1/state-registry?limit=80")
        async let runtimeResponse: RuntimeRegistryResponseDTO = APIClient.shared.get(path: "/api/v1/runtime-registry?limit=120")
        async let controlRoomResponse: ControlRoomDigestDTO = APIClient.shared.get(path: "/api/v1/control-room/digest")
        async let syncResponse: RuntimeClassificationSyncPreviewDTO = APIClient.shared.get(path: "/api/v1/runtime-registry/classification-sync/preview?limit=20")
        async let syncExportsResponse: RuntimeClassificationSyncExportsDTO = APIClient.shared.get(path: "/api/v1/runtime-registry/classification-sync/exports?limit=5")
        async let startupResponse: StartupStatusResponseDTO = APIClient.shared.get(path: "/api/v1/startup/status")
        async let computeSummaryResponse: ComputeRunSummaryDTO = APIClient.shared.get(path: "/api/v1/compute/runs/summary?window_hours=24")
        async let computeRouteResponse: ComputeRouteRegistryDTO = APIClient.shared.get(path: "/api/v1/compute/runs/routes")

        if let response = try? await stateResponse {
            tags = response.items.sorted { lhs, rhs in
                if lhs.stale != rhs.stale { return lhs.stale && !rhs.stale }
                return lhs.tagId < rhs.tagId
            }
        } else {
            tags = []
        }

        if let runtime = try? await runtimeResponse {
            runtimeRegistrySummary = runtime.summary
            runtimeRegistryGeneratedAt = runtime.generatedAt
            runtimeUnits = runtime.items.sorted { lhs, rhs in
                if lhs.statusSort != rhs.statusSort { return lhs.statusSort < rhs.statusSort }
                if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
                return lhs.name < rhs.name
            }
        } else {
            runtimeRegistrySummary = nil
            runtimeRegistryGeneratedAt = nil
            runtimeUnits = []
            errorMessage = "Fleet registry unavailable."
        }

        controlRoomDigest = try? await controlRoomResponse
        classificationSyncPreview = try? await syncResponse
        classificationSyncExports = (try? await syncExportsResponse)?.items ?? []
        startupStatus = try? await startupResponse
        computeSummary = try? await computeSummaryResponse
        computeRouteRegistry = try? await computeRouteResponse
    }

    @MainActor
    func classify(unit: RuntimeUnitDTO, action: RuntimeClassificationAction) async {
        isClassifying = true
        errorMessage = nil
        defer { isClassifying = false }

        do {
            let request = RuntimeClassificationRequestDTO(
                unitId: unit.id,
                action: action.rawValue,
                reviewer: "maui",
                note: action.defaultNote(for: unit),
                mergeTarget: nil
            )
            let _: RuntimeClassificationResponseDTO = try await APIClient.shared.post(
                path: "/api/v1/runtime-registry/classifications",
                body: request
            )
            await load()
        } catch {
            errorMessage = "Runtime classification failed."
        }
    }

    @MainActor
    func exportRuntimeSync() async {
        isExportingRuntimeSync = true
        errorMessage = nil
        runtimeExportMessage = nil
        defer { isExportingRuntimeSync = false }

        do {
            let response: RuntimeClassificationSyncExportDTO = try await APIClient.shared.post(
                path: "/api/v1/runtime-registry/classification-sync/export",
                body: EmptyRequestDTO()
            )
            runtimeExportMessage = "Exported \(response.total) decision\(response.total == 1 ? "" : "s"): \(response.exportId)"
            await load()
        } catch {
            errorMessage = "Runtime export failed."
        }
    }
}

private struct RuntimeRegistryResponseDTO: Decodable {
    let generatedAt: Date?
    let summary: RuntimeRegistrySummaryDTO
    let items: [RuntimeUnitDTO]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case summary, items
    }
}

private struct RuntimeRegistrySummaryDTO: Decodable {
    let total: Int
    let byKind: [String: Int]
    let byStatus: [String: Int]
    let byOwner: [String: Int]
    let byClassification: [String: Int]

    enum CodingKeys: String, CodingKey {
        case total
        case byKind = "by_kind"
        case byStatus = "by_status"
        case byOwner = "by_owner"
        case byClassification = "by_classification"
    }
}

private struct RuntimeUnitDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let owner: String?
    let status: String
    let scriptPath: String?
    let launchAgentLabel: String?
    let cadence: String?
    let lastExitCode: Int?
    let pid: Int?
    let logPaths: [String]
    let statePaths: [String]
    let docs: [String]
    let classification: String?
    let classifiedBy: String?
    let classifiedAt: Date?
    let classificationNote: String?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, owner, status, cadence, pid, docs, classification
        case scriptPath = "script_path"
        case launchAgentLabel = "launch_agent_label"
        case lastExitCode = "last_exit_code"
        case logPaths = "log_paths"
        case statePaths = "state_paths"
        case classifiedBy = "classified_by"
        case classifiedAt = "classified_at"
        case classificationNote = "classification_note"
    }

    var statusSort: Int {
        switch status {
        case "running": return 0
        case "loaded": return 1
        case "script_only": return 2
        case "disabled": return 4
        default: return 3
        }
    }
}

private enum RuntimeClassificationAction: String, CaseIterable {
    case keep
    case merge
    case retire
    case needsOwner = "needs_owner"
    case needsDocs = "needs_docs"
    case needsOrcaState = "needs_orca_state"

    var title: String {
        switch self {
        case .keep: return "Keep"
        case .merge: return "Merge"
        case .retire: return "Retire"
        case .needsOwner: return "Needs owner"
        case .needsDocs: return "Needs docs"
        case .needsOrcaState: return "Needs ORCA state"
        }
    }

    var icon: String {
        switch self {
        case .keep: return "checkmark.circle"
        case .merge: return "arrow.triangle.merge"
        case .retire: return "archivebox"
        case .needsOwner: return "person.crop.circle.badge.questionmark"
        case .needsDocs: return "doc.badge.gearshape"
        case .needsOrcaState: return "rectangle.connected.to.line.below"
        }
    }

    func defaultNote(for unit: RuntimeUnitDTO) -> String {
        switch self {
        case .keep:
            return "Pod runtime review: keep \(unit.name) in the active fleet."
        case .merge:
            return "Pod runtime review: merge candidate. Needs explicit merge target before host changes."
        case .retire:
            return "Pod runtime review: retire candidate. Host runtime remains unchanged pending review."
        case .needsOwner:
            return "Pod runtime review: owner must be assigned before this unit is trusted."
        case .needsDocs:
            return "Pod runtime review: documentation is required before this unit is trusted."
        case .needsOrcaState:
            return "Pod runtime review: unit needs ORCA state/health tags."
        }
    }
}

private struct RuntimeClassificationRequestDTO: Encodable {
    let unitId: String
    let action: String
    let reviewer: String
    let note: String
    let mergeTarget: String?
}

private struct RuntimeClassificationResponseDTO: Decodable {
    let ok: Bool
    let classificationId: String
    let unit: RuntimeUnitDTO
    let action: String

    enum CodingKeys: String, CodingKey {
        case ok, unit, action
        case classificationId = "classification_id"
    }
}

private struct RuntimeClassificationSyncPreviewDTO: Decodable {
    let total: Int
    let byAction: [String: Int]
    let items: [RuntimeClassificationSyncItemDTO]
    let overlayPath: String
    let auditPath: String
    let mode: String

    enum CodingKeys: String, CodingKey {
        case total, items, mode
        case byAction = "by_action"
        case overlayPath = "overlay_path"
        case auditPath = "audit_path"
    }
}

private struct RuntimeClassificationSyncItemDTO: Decodable, Identifiable {
    let unitId: String
    let action: String
    let reviewedBy: String?
    let reviewedAt: String?
    let classificationId: String?
    let note: String?
    let unit: RuntimeUnitDTO?

    var id: String { classificationId ?? "\(unitId)-\(action)" }

    enum CodingKeys: String, CodingKey {
        case action, note, unit
        case unitId = "unit_id"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case classificationId = "classification_id"
    }
}

private struct RuntimeClassificationSyncExportDTO: Decodable {
    let ok: Bool
    let exportId: String
    let total: Int
    let markdownPath: String
    let yamlPath: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok, total, message
        case exportId = "export_id"
        case markdownPath = "markdown_path"
        case yamlPath = "yaml_path"
    }
}

private struct RuntimeClassificationSyncExportsDTO: Decodable {
    let total: Int
    let items: [RuntimeClassificationSyncArtifactDTO]
}

private struct RuntimeClassificationSyncArtifactDTO: Decodable, Identifiable {
    var id: String { exportId }
    let exportId: String
    let markdownPath: String
    let yamlPath: String?
    let updatedAt: Date
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case exportId = "export_id"
        case markdownPath = "markdown_path"
        case yamlPath = "yaml_path"
        case updatedAt = "updated_at"
        case sizeBytes = "size_bytes"
    }
}

private struct StartupStatusResponseDTO: Decodable {
    let ok: Bool
    let checkedAt: Date
    let components: [StartupStatusComponentDTO]

    enum CodingKeys: String, CodingKey {
        case ok, components
        case checkedAt = "checked_at"
    }
}

private struct StartupStatusComponentDTO: Decodable, Identifiable {
    let id: String
    let label: String
    let status: String
    let detail: String
    let source: String
    let endpoint: String?
    let checkedAt: Date
    let latencyMs: Int?

    enum CodingKeys: String, CodingKey {
        case id, label, status, detail, source, endpoint
        case checkedAt = "checked_at"
        case latencyMs = "latency_ms"
    }
}

private struct ComputeRunSummaryDTO: Decodable {
    let windowHours: Int
    let status: String
    let total: Int
    let succeeded: Int
    let failed: Int
    let fallback: Int
    let fallbackRate: Double
    let avgLatencyMs: Int?
    let latest: ComputeRunSummaryLatestDTO?
    let latestError: String?
    let anonymousCount: Int
    let byRoute: [ComputeRunSummaryBucketDTO]
    let byTaskHint: [ComputeRunSummaryBucketDTO]
    let byBackend: [ComputeRunSummaryBucketDTO]

    enum CodingKeys: String, CodingKey {
        case status, total, succeeded, failed, fallback, latest
        case windowHours = "window_hours"
        case fallbackRate = "fallback_rate"
        case avgLatencyMs = "avg_latency_ms"
        case latestError = "latest_error"
        case anonymousCount = "anonymous_count"
        case byRoute = "by_route"
        case byTaskHint = "by_task_hint"
        case byBackend = "by_backend"
    }
}

private struct ComputeRunSummaryLatestDTO: Decodable {
    let id: String
    let traceId: String?
    let surface: String
    let taskHint: String
    let route: String
    let requestedRoute: String?
    let actualTier: String?
    let actualBackend: String?
    let model: String?
    let backend: String?
    let status: String
    let fallbackUsed: Bool
    let latencyMs: Int?
    let error: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, surface, route, model, backend, status, error
        case traceId = "trace_id"
        case taskHint = "task_hint"
        case requestedRoute = "requested_route"
        case actualTier = "actual_tier"
        case actualBackend = "actual_backend"
        case fallbackUsed = "fallback_used"
        case latencyMs = "latency_ms"
        case createdAt = "created_at"
    }
}

private struct ComputeRunSummaryBucketDTO: Decodable, Identifiable {
    var id: String { key }
    let key: String
    let total: Int
    let succeeded: Int
    let failed: Int
    let fallback: Int
    let fallbackRate: Double
    let avgLatencyMs: Int?

    enum CodingKeys: String, CodingKey {
        case key, total, succeeded, failed, fallback
        case fallbackRate = "fallback_rate"
        case avgLatencyMs = "avg_latency_ms"
    }
}

private struct ComputeRouteRegistryDTO: Decodable {
    let source: String
    let routerURL: String
    let routes: [ComputeRouteDTO]

    enum CodingKeys: String, CodingKey {
        case source, routes
        case routerURL = "router_url"
    }
}

private struct ComputeRouteDTO: Decodable, Identifiable {
    var id: String { route }
    let route: String
    let status: String
    let defaultFor: [String]
    let capabilities: [String]
    let fallback: String?
    let providerKeysRequired: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case route, status, capabilities, fallback, notes
        case defaultFor = "default_for"
        case providerKeysRequired = "provider_keys_required"
    }
}

private struct EmptyRequestDTO: Encodable {}

private struct RuntimeUnitRow: View {
    let unit: RuntimeUnitDTO
    let onClassify: (RuntimeClassificationAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.xs) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: Theme.xs) {
                    Text(unit.name)
                        .podTextStyle(.caption, color: AppColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: Theme.xs)
                    if let classification = unit.classification {
                        Text(classification.replacingOccurrences(of: "_", with: " ").uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(classificationColor)
                            .lineLimit(1)
                    }
                    Text(unit.kind.uppercased())
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                    classificationMenu
                }

                HStack(spacing: Theme.xs) {
                    Text(unit.status)
                    if let owner = unit.owner {
                        Text(owner)
                    }
                    if let cadence = unit.cadence {
                        Text(cadence)
                    }
                    if let pid = unit.pid {
                        Text("pid \(pid)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)

                if let scriptPath = unit.scriptPath {
                    Text(scriptPath)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }

                if let note = unit.classificationNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, Theme.xs)
    }

    private var classificationMenu: some View {
        Menu {
            ForEach(RuntimeClassificationAction.allCases, id: \.rawValue) { action in
                Button {
                    onClassify(action)
                } label: {
                    Label(action.title, systemImage: action.icon)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 24, height: 24)
        }
    }

    private var icon: String {
        switch unit.kind {
        case "petal": return "leaf.fill"
        case "watchdog": return "shield.lefthalf.filled"
        case "bridge": return "point.3.connected.trianglepath.dotted"
        case "worker": return "hammer.fill"
        default: return "gearshape.fill"
        }
    }

    private var statusColor: Color {
        switch unit.status {
        case "running": return AppColors.accentSuccess
        case "loaded", "script_only": return AppColors.accentElectric
        case "disabled": return AppColors.textTertiary
        default: return AppColors.accentWarning
        }
    }

    private var classificationColor: Color {
        switch unit.classification {
        case "keep": return AppColors.accentSuccess
        case "retire": return AppColors.accentDanger
        case "merge", "needs_owner", "needs_docs", "needs_orca_state": return AppColors.accentWarning
        default: return AppColors.textTertiary
        }
    }
}

private struct StartupStatusChip: View {
    let component: StartupStatusComponentDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                Text(component.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(component.status.capitalized)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)

            Text(component.detail)
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(2)

            if let latency = component.latencyMs {
                Text("\(latency)ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.24), lineWidth: 1)
        )
    }

    private var color: Color {
        switch component.status {
        case "good": return AppColors.accentSuccess
        case "degraded", "unknown": return AppColors.accentWarning
        case "unavailable": return AppColors.accentDanger
        default: return AppColors.textTertiary
        }
    }

    private var icon: String {
        switch component.id {
        case "orca": return "checkmark.seal.fill"
        case "nats": return "antenna.radiowaves.left.and.right"
        case "compute": return "cpu"
        case "compute_history": return "chart.xyaxis.line"
        case "mermaid": return "hammer.fill"
        case "chat_sse": return "bubble.left.and.bubble.right.fill"
        case "ticket_sse": return "ticket.fill"
        default: return "circle.grid.cross"
        }
    }
}

private struct ComputeRouteChip: View {
    let route: ComputeRouteDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                Text(route.route)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(route.status.replacingOccurrences(of: "_", with: " "))
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)

            if !route.defaultFor.isEmpty {
                Text(route.defaultFor.prefix(3).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(2)
            } else if !route.capabilities.isEmpty {
                Text(route.capabilities.prefix(2).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(2)
            }

            if let fallback = route.fallback {
                Text("fallback \(fallback)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }

            if route.providerKeysRequired {
                Label("API key", systemImage: "key")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentWarning)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.24), lineWidth: 1)
        )
    }

    private var color: Color {
        switch route.status {
        case "active": return AppColors.accentSuccess
        case "fallback": return AppColors.accentElectric
        case "future_optional": return AppColors.accentWarning
        default: return AppColors.textTertiary
        }
    }

    private var icon: String {
        switch route.route {
        case "auto": return "arrow.triangle.branch"
        case "spark": return "bolt.fill"
        case "kimi": return "text.magnifyingglass"
        case "local": return "shield.lefthalf.filled"
        default: return "cpu"
        }
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var token: String = UserDefaults.standard.string(forKey: "orca_auth_token") ?? AppState.localBearerTokenFallback() ?? ""
    @State private var networkStatus: String = ""   // live network diagnostic
    @FocusState private var isTokenFocused: Bool

    var body: some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            // Logo / Brand
            VStack(spacing: AppTheme.spacingSM) {
                Image(systemName: "cpu")
                    .font(.system(size: 64))
                    .foregroundColor(AppTheme.primaryAccent)
                    .shadow(color: AppTheme.glowAccent, radius: 20)

                Text("ORCA")
                    .font(.system(size: 40, weight: .bold, design: .default))
                    .foregroundColor(AppTheme.primaryText)

                Text("Mission Control")
                    .font(.title3)
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()

            // Token input
            VStack(spacing: AppTheme.spacingMD) {
                VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                    HStack {
                        Text("API Token")
                            .font(.caption)
                            .foregroundColor(AppTheme.secondaryText)
                        Spacer()
                        if !token.isEmpty {
                            Text("\(token.count) chars")
                                .font(.caption2)
                                .foregroundColor(AppTheme.primaryAccent)
                        }
                    }

                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(AppTheme.secondaryText)

                        SecureField("Paste your token", text: $token)
                            .textFieldStyle(.plain)
                            .foregroundColor(AppTheme.primaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isTokenFocused)
                            .submitLabel(.go)
                            .onSubmit {
                                Task { await submitToken() }
                            }
                    }
                    .padding(AppTheme.spacingSM)
                    .background(AppTheme.surface)
                    .cornerRadius(AppTheme.radiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMedium)
                            .stroke(token.isEmpty ? AppTheme.border : AppTheme.primaryAccent, lineWidth: 1)
                    )
                }

                // Live network status
                if !networkStatus.isEmpty || !appState.authDiagnostics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !networkStatus.isEmpty {
                            Text(networkStatus)
                                .font(.caption.monospaced())
                                .foregroundColor(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !appState.authDiagnostics.isEmpty {
                            Divider()
                                .overlay(AppTheme.border)
                            ForEach(Array(appState.authDiagnostics.suffix(6).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(AppTheme.tertiaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(AppTheme.spacingSM)
                    .background(AppTheme.surface)
                    .cornerRadius(AppTheme.radiusMedium)
                }

                Button {
                    Task {
                        await submitToken()
                    }
                } label: {
                    HStack {
                        if appState.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(AppTheme.inverseText)
                                .scaleEffect(0.8)
                        } else {
                            Text("Connect")
                                .font(.body.bold())
                        }
                    }
                    .foregroundColor(AppTheme.inverseText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingSM + 4)
                    .background(AppTheme.primaryAccent)
                    .cornerRadius(AppTheme.radiusMedium)
                }
                .buttonStyle(.plain)
                .disabled(appState.isLoading || token.isEmpty)

            }
            .padding(.horizontal, AppTheme.spacingXL)

            Spacer()

            Text("Connecting to ORCA: \(AppState.backendURL)")
                .font(.caption)
                .foregroundColor(AppTheme.tertiaryText)
                .padding(.bottom, AppTheme.spacingLG)
        }
        .background(AppTheme.background)
        .onAppear {
            Task {
                await checkNetwork()
            }
        }
    }

    // MARK: - Network Check

    @MainActor
    private func checkNetwork() async {
        networkStatus = "Checking network..."
        guard let url = URL(string: "\(AppState.backendURL)/health") else {
            networkStatus = "❌ Invalid URL"
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                networkStatus = "✅ Backend reachable (HTTP \(http.statusCode))"
            } else {
                networkStatus = "✅ Backend responded"
            }
        } catch {
            networkStatus = "❌ Cannot reach backend: \(error.localizedDescription)"
        }
    }

    // MARK: - Auth

    @MainActor
    private func submitToken() async {
        guard !token.isEmpty else { return }
        
        networkStatus = "Authenticating..."
        // authenticate() sets isAuthenticated=true on success
        await appState.authenticate(token: token)
        // After authenticate() returns, SwiftUI will re-render because AppState is @MainActor @Published
        if appState.isAuthenticated {
            networkStatus = "✅ Authenticated! Loading..."
        } else if let err = appState.errorMessage {
            networkStatus = "❌ \(err)"
        } else {
            networkStatus = "Auth complete"
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
}
