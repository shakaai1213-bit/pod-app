import AppIntents
import SwiftUI

// MARK: - Intent Dependency Injection

/// Shared actor-based API client for App Intents
/// Uses the same baseURL and auth token as the main app
actor IntentAPIClient {
    static let shared = IntentAPIClient()

    private let baseURL = "http://192.168.4.243:8000"
    private var authToken: String?

    private init() {
        // Inherit auth token from main app's UserDefaults
        self.authToken = UserDefaults.standard.string(forKey: "orca_auth_token")
    }

    func setToken(_ token: String?) {
        self.authToken = token
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw IntentAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Api-Key")
        }

        if let body = body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw IntentAPIError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw IntentAPIError.unauthorized
        case 500...599:
            throw IntentAPIError.serverError
        default:
            throw IntentAPIError.httpError(statusCode: http.statusCode)
        }
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await makeRequest(path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let bodyData = try JSONEncoder().encode(body)
        let data = try await makeRequest(path: path, method: "POST", body: bodyData)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Agents

    func fetchAgents() async throws -> [IntentAgent] {
        try await get("/api/v1/agents")
    }

    func fetchAgentStatus(agentId: String) async throws -> IntentAgent {
        try await get("/api/v1/agents/\(agentId)/status")
    }

    // MARK: - Dashboard

    func fetchDashboardStats() async throws -> IntentDashboardStats {
        try await get("/api/v1/dashboard/stats")
    }

    // MARK: - Attention / Alerts

    func fetchAttentionItems() async throws -> IntentAttentionResponse {
        try await get("/api/v1/attention/items")
    }

    // MARK: - Approvals

    func approveRequest(requestId: String) async throws -> IntentApprovalResponse {
        let body = IntentApprovalRequest(requestId: requestId)
        return try await post("/api/v1/approvals/approve", body: body)
    }

    // MARK: - Chat

    func fetchChannels() async throws -> [IntentChannel] {
        try await get("/api/v1/chat/channels")
    }

    func sendMessage(channelId: String, content: String) async throws {
        let body = IntentSendMessageRequest(content: content, channelId: channelId)
        let _: IntentMessageResponse = try await post("/api/v1/chat/channels/\(channelId)/messages", body: body)
    }
}

// MARK: - Intent API Error

enum IntentAPIError: Swift.Error, CustomStringConvertible {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError
    case httpError(statusCode: Int)
    case decodingFailed

    var description: String {
        switch self {
        case .invalidURL:       return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .unauthorized:     return "Not authenticated"
        case .serverError:      return "Server error"
        case .httpError(let c): return "HTTP \(c)"
        case .decodingFailed:   return "Failed to decode response"
        }
    }
}

// MARK: - Intent DTOs

struct IntentAgent: Codable {
    let id: String
    let name: String
    let role: String
    let status: IntentAgentStatus
    let currentTask: String?
    let lastActivity: Date?
    let skills: [String]
    let avatarColor: String?
}

enum IntentAgentStatus: String, Codable {
    case online
    case busy
    case idle
    case offline
    case error

    var displayName: String { rawValue.capitalized }

    var emoji: String {
        switch self {
        case .online:  return "🟢"
        case .busy:    return "🟡"
        case .idle:    return "⚪"
        case .offline: return "⚫"
        case .error:   return "🔴"
        }
    }
}

struct IntentDashboardStats: Codable {
    let activeProjects: Int
    let openTasks: Int
    let teamOnline: Int
    let unreadMessages: Int
    let blockedTasks: Int
    let pendingApprovals: Int
}

struct IntentAttentionItem: Codable, Identifiable {
    let id: String
    let type: String
    let title: String
    let description: String?
    let priority: String
    let timestamp: Date?
}

struct IntentAttentionResponse: Codable {
    let items: [IntentAttentionItem]
    let totalCount: Int
}

struct IntentApprovalRequest: Encodable {
    let requestId: String
}

struct IntentApprovalResponse: Codable {
    let success: Bool
    let message: String?
}

struct IntentChannel: Codable, Identifiable {
    let id: String
    let name: String
    let type: String
    let description: String?
    let unreadCount: Int
}

struct IntentSendMessageRequest: Encodable {
    let content: String
    let channelId: String
}

struct IntentMessageResponse: Codable {
    let id: String
    let content: String
    let timestamp: Date
}

// MARK: - Channel Entity

struct IntentChannelEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Channel")
    static var defaultQuery = IntentChannelQuery()

    var id: String
    var name: String
    var type: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\($name)", subtitle: "\($type)")
    }

    init(id: String, name: String, type: String) {
        self.id = id
        self.name = name
        self.type = type
    }

    init(from channel: IntentChannel) {
        self.id = channel.id
        self.name = channel.name
        self.type = channel.type
    }
}

struct IntentChannelQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [IntentChannelEntity] {
        let channels: [IntentChannel] = try await IntentAPIClient.shared.fetchChannels()
        return channels
            .filter { identifiers.contains($0.id) }
            .map { IntentChannelEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [IntentChannelEntity] {
        let channels: [IntentChannel] = try await IntentAPIClient.shared.fetchChannels()
        return channels.map { IntentChannelEntity(from: $0) }
    }

    func defaultResult() async -> IntentChannelEntity? {
        try? await suggestedEntities().first
    }
}

// MARK: - Check Agent Status Intent

struct CheckAgentStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Agent Status"
    static var description = IntentDescription("Get the current status of an agent or all agents")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Agent Name")
    var agentName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Check status of \(\.$agentName)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let api = IntentAPIClient.shared

        do {
            let agents: [IntentAgent] = try await api.fetchAgents()

            if let name = agentName {
                // Filter by name (case-insensitive partial match)
                let matches = agents.filter {
                    $0.name.localizedCaseInsensitiveContains(name)
                }

                if matches.isEmpty {
                    return .result(dialog: "I couldn't find an agent named '\(name)'. Try checking all agents instead.")
                }

                let lines = matches.map { agent -> String in
                    let statusText = agent.status.displayName.lowercased()
                    let taskText = agent.currentTask.map { " — \($0)" } ?? ""
                    return "\(agent.name) is \(statusText)\(taskText)"
                }
                return .result(dialog: "\(lines.joined(separator: " "))")
            } else {
                // All agents
                let online = agents.filter { $0.status == .online || $0.status == .busy }
                let idle = agents.filter { $0.status == .idle }
                let offline = agents.filter { $0.status == .offline }
                let error = agents.filter { $0.status == .error }

                var summary = ""
                if !online.isEmpty {
                    let names = online.map(\.name).joined(separator: ", ")
                    summary += "\(online.count) active: \(names)."
                }
                if !idle.isEmpty {
                    if !summary.isEmpty { summary += " " }
                    summary += "\(idle.count) idle: \(idle.map(\.name).joined(separator: ", "))."
                }
                if !error.isEmpty {
                    if !summary.isEmpty { summary += " " }
                    let names = error.map(\.name).joined(separator: ", ")
                    summary += "\(error.count) with errors: \(names)."
                }
                if !offline.isEmpty {
                    if !summary.isEmpty { summary += " " }
                    summary += "\(offline.count) offline."
                }

                if summary.isEmpty {
                    summary = "No agents are currently registered."
                }

                return .result(dialog: "\(summary)")
            }
        } catch IntentAPIError.unauthorized {
            return .result(dialog: "You're not logged in. Please open the app and sign in first.")
        } catch {
            return .result(dialog: "Couldn't reach the agent system right now. Try again in a moment.")
        }
    }
}

// MARK: - Send Message Intent

struct SendMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Message"
    static var description = IntentDescription("Send a message to a team channel in Pod")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Channel", default: .general)
    var channel: IntentChannelEntity

    @Parameter(title: "Message")
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) to \(\.$channel)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "I can't send an empty message. What would you like to say?")
        }

        let api = IntentAPIClient.shared

        do {
            try await api.sendMessage(channelId: channel.id, content: message)
            return .result(dialog: "Message sent to #\(channel.name).")
        } catch IntentAPIError.unauthorized {
            return .result(dialog: "You're not logged in. Please open Pod and sign in first.")
        } catch {
            return .result(dialog: "Failed to send the message. Please try again.")
        }
    }
}

// MARK: - Get Team Status Intent

struct GetTeamStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Team Status"
    static var description = IntentDescription("Get an overview of the team's current status")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let api = IntentAPIClient.shared

        do {
            async let agentsTask = api.fetchAgents()
            async let statsTask = api.fetchDashboardStats()

            let (agents, stats) = try await (agentsTask, statsTask)

            let onlineCount = agents.filter { $0.status == .online || $0.status == .busy }.count
            let errorCount = agents.filter { $0.status == .error }.count
            let offlineCount = agents.filter { $0.status == .offline }.count

            var parts: [String] = []

            // Agent summary
            if onlineCount > 0 {
                parts.append("\(onlineCount) agent\(onlineCount == 1 ? "" : "s") online")
            }
            if errorCount > 0 {
                parts.append("\(errorCount) with error\(errorCount == 1 ? "" : "s")")
            }
            if offlineCount > 0 {
                parts.append("\(offlineCount) offline")
            }

            var summary = parts.isEmpty ? "No agents registered." : "\(parts.joined(separator: ", "))."

            // Project/task summary
            if stats.activeProjects > 0 {
                summary += " \(stats.activeProjects) active project\(stats.activeProjects == 1 ? "" : "s")."
            }
            if stats.blockedTasks > 0 {
                summary += " \(stats.blockedTasks) blocked task\(stats.blockedTasks == 1 ? "" : "s")."
            }
            if stats.pendingApprovals > 0 {
                summary += " \(stats.pendingApprovals) pending approval\(stats.pendingApprovals == 1 ? "" : "s")."
            }

            return .result(dialog: summary)
        } catch IntentAPIError.unauthorized {
            return .result(dialog: "You're not logged in. Please open Pod and sign in first.")
        } catch {
            return .result(dialog: "Couldn't load team status right now. Try again shortly.")
        }
    }
}

// MARK: - Get Attention Items Intent

struct GetAttentionItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Attention Items"
    static var description = IntentDescription("See what needs your attention — blocked tasks, errors, pending approvals")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[String]> {
        let api = IntentAPIClient.shared

        do {
            let response: IntentAttentionResponse = try await api.fetchAttentionItems()

            if response.items.isEmpty {
                return .result(
                    dialog: "All clear! Nothing needs your attention right now.",
                    value: []
                )
            }

            // Build a concise summary for Siri
            var lines: [String] = []
            for item in response.items.prefix(5) {
                let priorityMark = item.priority == "critical" ? "🚨 " :
                                   item.priority == "high" ? "⚠️ " : ""
                lines.append("\(priorityMark)\(item.title)")
            }

            let suffix = response.totalCount > 5 ? " and \(response.totalCount - 5) more items." : "."
            let summary = lines.joined(separator: " ") + suffix

            let values = response.items.map { "\($0.type): \($0.title)" }

            return .result(dialog: summary, value: values)
        } catch IntentAPIError.unauthorized {
            return .result(dialog: "You're not logged in. Please open Pod and sign in first.", value: [])
        } catch {
            return .result(dialog: "Couldn't load attention items. Please try again.", value: [])
        }
    }
}

// MARK: - Approve Request Intent

struct ApproveRequestIntent: AppIntent {
    static var title: LocalizedStringResource = "Approve Request"
    static var description = IntentDescription("Approve a pending request by its ID")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Request ID")
    var requestId: String

    static var parameterSummary: some ParameterSummary {
        Summary("Approve request \(\.$requestId)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "Please provide a valid request ID.")
        }

        let api = IntentAPIClient.shared

        do {
            let response: IntentApprovalResponse = try await api.approveRequest(requestId: requestId)

            if response.success {
                return .result(dialog: response.message ?? "Request approved successfully.")
            } else {
                return .result(dialog: response.message ?? "Approval failed. Please check the request ID.")
            }
        } catch IntentAPIError.unauthorized {
            return .result(dialog: "You're not logged in. Please open Pod and sign in first.")
        } catch {
            return .result(dialog: "Couldn't approve the request. Please try again or open Pod.")
        }
    }
}

// MARK: - Start Focus Mode Intent

struct StartFocusModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Focus Mode"
    static var description = IntentDescription("Turn on Do Not Disturb and silence non-critical notifications")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Duration", default: 60)
    var durationMinutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Focus mode for \(\.$durationMinutes) minutes")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Persist focus state for the app to pick up
        let endTime = Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
        UserDefaults(suiteName: "group.com.orca.pod")?.set(endTime, forKey: "focusModeEndTime")
        UserDefaults(suiteName: "group.com.orca.pod")?.set(true, forKey: "focusModeActive")

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        let duration = formatter.string(from: TimeInterval(durationMinutes * 60)) ?? "\(durationMinutes) minutes"

        return .result(dialog: "Focus mode activated for \(duration). I'll quiet non-essential alerts until then.")
    }
}

// MARK: - Stop Focus Mode Intent

struct StopFocusModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Focus Mode"
    static var description = IntentDescription("Turn off Focus Mode and restore notifications")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults(suiteName: "group.com.orca.pod")?.set(nil, forKey: "focusModeEndTime")
        UserDefaults(suiteName: "group.com.orca.pod")?.set(false, forKey: "focusModeActive")

        return .result(dialog: "Focus mode deactivated. Notifications restored.")
    }
}
