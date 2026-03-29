import SwiftUI

// MARK: - Enums & Types

enum UserStatus: String, CaseIterable {
    case online
    case busy
    case away
    case offline

    var color: Color {
        switch self {
        case .online:  return .green
        case .busy:    return .orange
        case .away:    return .yellow
        case .offline: return .gray
        }
    }

    var label: String { rawValue.capitalized }
}

enum AppColorScheme: String, CaseIterable {
    case dark
    case light
    case system

    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .dark:  return "moon.fill"
        case .light: return "sun.max.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

struct NotificationChannel: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    var enabled: Bool
}

struct NotificationEvent: Identifiable, Hashable {
    let id: String
    let name: String
    var enabled: Bool
}

struct AgentPreference: Identifiable, Hashable {
    let id: String
    let name: String
    var enabled: Bool
}

// MARK: - ViewModel

@Observable
final class SettingsViewModel {
    // MARK: Profile
    var avatarImage: UIImage?
    var userName: String = "Maui"
    var userRole: String = "Head of Engineering"
    var userEmail: String = "maui@orca.ai"
    var userStatus: UserStatus = .online

    // MARK: Appearance
    var colorScheme: AppColorScheme = .dark

    // MARK: Notifications
    var channels: [NotificationChannel] = [
        NotificationChannel(id: "general",  name: "General",   icon: "bubble.left.fill",      enabled: true),
        NotificationChannel(id: "projects", name: "Projects",  icon: "folder.fill",            enabled: true),
        NotificationChannel(id: "research", name: "Research",  icon: "magnifyingglass",        enabled: false),
        NotificationChannel(id: "alerts",   name: "Alerts",    icon: "bell.badge.fill",       enabled: true),
    ]

    var events: [NotificationEvent] = [
        NotificationEvent(id: "task_assigned",      name: "Task assigned",        enabled: true),
        NotificationEvent(id: "approval_requested", name: "Approval requested",    enabled: true),
        NotificationEvent(id: "agent_error",       name: "Agent error",           enabled: true),
        NotificationEvent(id: "mentioned",          name: "Mentioned",            enabled: true),
    ]

    // MARK: Organization
    var orgName: String = "ORCA AI"
    var memberCount: Int = 8

    // MARK: Agent Preferences
    var agents: [AgentPreference] = [
        AgentPreference(id: "maui",      name: "Maui",      enabled: true),
        AgentPreference(id: "researcher", name: "Researcher", enabled: true),
        AgentPreference(id: "builder",   name: "Builder",   enabled: true),
        AgentPreference(id: "analyst",   name: "Analyst",   enabled: false),
        AgentPreference(id: "sentinel",  name: "Sentinel",  enabled: true),
    ]

    // MARK: About
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    var gatewayReachable: Bool = false

    // MARK: Debug
    var showDebugSection: Bool = false
    var debugTapCount: Int = 0
    var showRawApiResponses: Bool = false

    private var gatewayCheckTask: Task<Void, Never>?

    init() {
        checkGatewayStatus()
    }

    func checkGatewayStatus() {
        gatewayCheckTask?.cancel()
        gatewayCheckTask = Task {
            #if targetEnvironment(simulator)
            guard let url = URL(string: "http://127.0.0.1:19002/health") else { return }
            #else
            guard let url = URL(string: "http://shakas-mac-mini.tail82d30d.ts.net:8000/health") else { return }
            #endif
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if !Task.isCancelled {
                    gatewayReachable = (response as? HTTPURLResponse)?.statusCode == 200
                }
            } catch {
                if !Task.isCancelled {
                    gatewayReachable = false
                }
            }
        }
    }

    func handleVersionTap() {
        debugTapCount += 1
        if debugTapCount >= 5 {
            withAnimation(.easeInOut(duration: 0.3)) {
                showDebugSection = true
                showRawApiResponses = true
            }
        }
    }
}

// MARK: - View

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var showingProfileEditor = false
    @State private var showingAgentPicker = false
    @State private var showingWallDisplayLauncher = false

    var body: some View {
        NavigationStack {
            List {
                wallDisplaySection
                profileSection
                appearanceSection
                notificationsSection
                organizationSection
                agentPreferencesSection
                aboutSection
                if viewModel.showDebugSection {
                    debugSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .preferredColorScheme(colorScheme)
            .sheet(isPresented: $showingWallDisplayLauncher) {
                WallDisplayLauncherView()
            }
        }
    }

    // MARK: - Wall Display Section

    private var wallDisplaySection: some View {
        Section {
            Button {
                showingWallDisplayLauncher = true
            } label: {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(AppColors.accentElectric)
                        .frame(width: 32, height: 32)
                        .background(AppColors.accentElectric.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ambient Wall Display")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Full-screen team status for iPad")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("iPad Display")
        }
    }

    // MARK: - Color Scheme

    private var colorScheme: ColorScheme? {
        switch viewModel.colorScheme {
        case .dark:  return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                AvatarView(
                    name: viewModel.userName,
                    status: nil,
                    size: .xl,
                    showRing: true
                )
                .onTapGesture { showingProfileEditor = true }
                .accessibilityLabel("Profile avatar, tap to edit")

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.userName)
                        .font(.headline)
                    Text(viewModel.userRole)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(viewModel.userEmail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        } header: {
            Text("Profile")
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                HStack {
                    Image(systemName: scheme.icon)
                        .foregroundStyle(scheme == viewModel.colorScheme ? .blue : .secondary)
                        .frame(width: 24)
                    Text(scheme.label)
                    Spacer()
                    if scheme == viewModel.colorScheme {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.colorScheme = scheme
                    }
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Default theme is Dark.")
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Group {
            Section {
                ForEach($viewModel.channels) { $channel in
                    Toggle(isOn: $channel.enabled) {
                        Label(channel.name, systemImage: channel.icon)
                    }
                    .tint(.blue)
                }
            } header: {
                Text("Channels")
            } footer: {
                Text("Choose which channels send push notifications.")
            }

            Section {
                ForEach($viewModel.events) { $event in
                    Toggle(isOn: $event.enabled) {
                        Text(event.name)
                    }
                    .tint(.blue)
                }
            } header: {
                Text("Events")
            } footer: {
                Text("Get notified for these events across all channels.")
            }
        }
    }

    // MARK: - Organization Section

    private var organizationSection: some View {
        Section {
            HStack {
                Text("Organization")
                Spacer()
                Text(viewModel.orgName)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Members")
                Spacer()
                Text("\(viewModel.memberCount)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Organization")
        }
    }

    // MARK: - Agent Preferences Section

    private var agentPreferencesSection: some View {
        Section {
            ForEach($viewModel.agents) { $agent in
                Toggle(isOn: $agent.enabled) {
                    Text(agent.name)
                }
                .tint(.blue)
            }
        } header: {
            Text("Dashboard Agents")
        } footer: {
            Text("Select which agents appear on your Dashboard.")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.handleVersionTap()
                    }
            }

            HStack {
                HStack(spacing: 6) {
                    Text("ORCA MC Gateway")
                    Circle()
                        .fill(viewModel.gatewayReachable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .overlay {
                            if viewModel.gatewayReachable {
                                Circle()
                                    .stroke(Color.green.opacity(0.5), lineWidth: 2)
                                    .scaleEffect(1.5)
                            }
                        }
                }
                Spacer()
                Text(viewModel.gatewayReachable ? "Connected" : "Offline")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Debug Section

    private var debugSection: some View {
        Section {
            Toggle(isOn: $viewModel.showRawApiResponses) {
                Label("Show Raw API Responses", systemImage: "ladybug.fill")
            }
            .tint(.orange)

            if viewModel.showRawApiResponses {
                NavigationLink {
                    DebugLogView()
                } label: {
                    Label("View API Log", systemImage: "list.bullet.rectangle")
                }
            }
        } header: {
            HStack {
                Text("Debug")
                Text("⚠️")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Debug Log View

struct DebugLogView: View {
    @State private var entries: [DebugLogEntry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No API Calls Logged",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Network requests will appear here when enabled.")
                )
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.endpoint)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.blue)
                            Spacer()
                            Text(entry.method)
                                .font(.caption2.bold())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(methodColor(entry.method).opacity(0.2))
                                .foregroundStyle(methodColor(entry.method))
                                .clipContent()
                        }
                        if let body = entry.requestBody {
                            Text(body)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("API Log")
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        entries.removeAll()
                    }
                }
            }
        }
    }

    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET":    return .green
        case "POST":   return .blue
        case "PUT":    return .orange
        case "DELETE": return .red
        default:       return .secondary
        }
    }
}

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let endpoint: String
    let method: String
    let requestBody: String?
}

// MARK: - Clip Content Extension

extension View {
    @ViewBuilder
    func clipContent() -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
