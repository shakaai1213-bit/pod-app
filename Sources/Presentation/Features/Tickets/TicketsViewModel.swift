import Foundation
import SwiftUI

// MARK: - Ticket Domain Model

struct Ticket: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let description: String?
    let status: TicketStatus
    let priority: TicketPriority
    let assigneeAgentId: String?
    let assigneeAgentName: String?
    let ticketType: String?
    let parentTicketId: String?       // POD-4: subtask hierarchy
    let lessonsLearned: String?       // POD-4: lessons-learned capture
    let createdAt: Date
    let updatedAt: Date
    let claimedAt: Date?
    let startedAt: Date?
    let resolvedAt: Date?
    let resolutionNotes: String?
}

enum TicketStatus: String, Sendable, CaseIterable {
    case open
    case inProgress = "in_progress"
    case resolved
    case closed

    var label: String {
        switch self {
        case .open:       return "Open"
        case .inProgress: return "In Progress"
        case .resolved:   return "Resolved"
        case .closed:     return "Closed"
        }
    }

    var color: Color {
        switch self {
        case .open:       return AppColors.accentElectric
        case .inProgress: return AppColors.accentAgent
        case .resolved:   return AppColors.accentSuccess
        case .closed:     return AppColors.textTertiary
        }
    }

    var icon: String {
        switch self {
        case .open:       return "circle"
        case .inProgress: return "arrow.clockwise.circle.fill"
        case .resolved:   return "checkmark.circle.fill"
        case .closed:     return "xmark.circle.fill"
        }
    }
}

enum TicketPriority: String, Sendable, CaseIterable {
    case low
    case normal
    case medium
    case high
    case urgent

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .low:    return AppColors.textTertiary
        case .normal: return AppColors.textSecondary
        case .medium: return AppColors.accentElectric
        case .high:   return Color.orange
        case .urgent: return AppColors.accentDanger
        }
    }

    var icon: String {
        switch self {
        case .low:    return "arrow.down"
        case .normal: return "minus"
        case .medium: return "arrow.up"
        case .high:   return "exclamationmark"
        case .urgent: return "exclamationmark.2"
        }
    }
}

// MARK: - TicketDTO

struct TicketDTO: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let status: String
    let priority: String
    let assigneeAgentId: String?
    let ticketType: String?
    let parentTicketId: String?     // POD-4
    let lessonsLearned: String?    // POD-4
    let createdAt: Date
    let updatedAt: Date
    let claimedAt: Date?
    let startedAt: Date?
    let resolvedAt: Date?
    let resolutionNotes: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, priority
        case assigneeAgentId    = "assignee_agent_id"
        case ticketType         = "ticket_type"
        case parentTicketId     = "parent_ticket_id"
        case lessonsLearned     = "lessons_learned"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
        case claimedAt          = "claimed_at"
        case startedAt          = "started_at"
        case resolvedAt         = "resolved_at"
        case resolutionNotes    = "resolution_notes"
    }

    func toDomain(agentName: String? = nil) -> Ticket {
        Ticket(
            id: id,
            title: title,
            description: description,
            status: TicketStatus(rawValue: status) ?? .open,
            priority: TicketPriority(rawValue: priority) ?? .normal,
            assigneeAgentId: assigneeAgentId,
            assigneeAgentName: agentName,
            ticketType: ticketType,
            parentTicketId: parentTicketId,
            lessonsLearned: lessonsLearned,
            createdAt: createdAt,
            updatedAt: updatedAt,
            claimedAt: claimedAt,
            startedAt: startedAt,
            resolvedAt: resolvedAt,
            resolutionNotes: resolutionNotes
        )
    }
}

// MARK: - TicketsViewModel

@Observable
final class TicketsViewModel {
    var tickets: [Ticket] = []
    var isLoading = false
    var errorMessage: String?
    var selectedStatus: TicketStatus? = nil  // nil = show all
    var showCreateSheet = false

    // For create form
    var newTitle = ""
    var newDescription = ""
    var newPriority = TicketPriority.normal
    var newAssigneeAgentId = ""
    var isCreating = false

    private let api = APIClient.shared

    // b9bbe115 SSE leg: live ticket lifecycle subscription to /api/v1/tickets/stream
    // (fans team.tickets.events). On any lifecycle event we trigger a full reload —
    // payload set is small (≤~100 tickets typically) and full-reload is correct
    // by construction. Patch-in-place is a later optimization.
    private var sseManager: SSEStreamManager?
    private var sseListenTask: Task<Void, Never>?

    // POD-4: Subtask tree
    var rootTickets: [Ticket] {
        tickets.filter { $0.parentTicketId == nil }
    }

    func subtasks(of ticket: Ticket) -> [Ticket] {
        tickets.filter { $0.parentTicketId == ticket.id }
    }

    var filtered: [Ticket] {
        guard let status = selectedStatus else { return tickets }
        return tickets.filter { $0.status == status }
    }

    var openCount: Int    { tickets.filter { $0.status == .open }.count }
    var activeCount: Int  { tickets.filter { $0.status == .inProgress }.count }

    // MARK: - Load

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let dtos: [TicketDTO] = try await api.get(path: "/api/v1/tickets")

            // Fetch agent names for tickets with assignee_agent_id
            let agentIds = Set(dtos.compactMap { $0.assigneeAgentId })
            var agentNames: [String: String] = [:]

            if !agentIds.isEmpty {
                do {
                    let response: PaginatedResponse<AgentDTO> = try await api.get(path: "/api/v1/agents")
                    for agent in response.items {
                        agentNames[agent.id] = agent.name
                    }
                } catch {
                    // Ignore agent fetch errors, we'll show IDs instead
                }
            }

            tickets = dtos.map { dto in
                let agentName = dto.assigneeAgentId.flatMap { agentNames[$0] }
                return dto.toDomain(agentName: agentName)
            }.sorted { $0.createdAt > $1.createdAt }
        } catch let apiError as APIError {
            // 2026-05-07 plumbing fix: no more silent mock fallback. Surface the real error.
            tickets = []
            errorMessage = Self.userFacingMessage(for: apiError)
        } catch {
            tickets = []
            errorMessage = "Couldn't load tickets. Pull to retry."
        }
    }

    // MARK: - Error classification

    private static func userFacingMessage(for error: APIError) -> String {
        switch error.code {
        case 401, 403:
            return "Signed out. Sign in to see your tickets."
        case 404:
            return "Tickets endpoint not found. Backend may be out of date."
        case 500...599:
            return "Server returned \(error.code). Engineers notified."
        case 0:
            return "Can't reach backend. Check your connection."
        default:
            return error.message.isEmpty ? "Couldn't load tickets (\(error.code))." : error.message
        }
    }

    // MARK: - Mock Fallback (DEBUG previews only — 2026-05-07: no longer hit in production)

    #if DEBUG
    static var mockTickets: [Ticket] {
        let now = Date()
        return [
            Ticket(
                id: "TICKET-001",
                title: "Voice Companion Tab (Whisplay)",
                description: "Add Whisplay voice companion as a dedicated tab in the Pod app.",
                status: .open,
                priority: .medium,
                assigneeAgentId: "maui",
                assigneeAgentName: "Maui",
                ticketType: "feature",
                parentTicketId: nil,
                lessonsLearned: nil,
                createdAt: now.addingTimeInterval(-86400),
                updatedAt: now.addingTimeInterval(-86400),
                claimedAt: nil, startedAt: nil, resolvedAt: nil, resolutionNotes: nil
            ),
            Ticket(
                id: "TICKET-002",
                title: "Connect Projects Tab to Live Ticket Data",
                description: "Replace mock data in Projects tab with live data from ticket API.",
                status: .inProgress,
                priority: .medium,
                assigneeAgentId: "aurora",
                assigneeAgentName: "Aurora",
                ticketType: "feature",
                parentTicketId: nil,
                lessonsLearned: nil,
                createdAt: now.addingTimeInterval(-72000),
                updatedAt: now.addingTimeInterval(-3600),
                claimedAt: now.addingTimeInterval(-72000), startedAt: now.addingTimeInterval(-3600),
                resolvedAt: nil, resolutionNotes: nil
            ),
            Ticket(
                id: "TICKET-003",
                title: "Both Apps Showing Demo Data",
                description: "iPhone and iPad showing demo agents (Kai, Orca, Pulse). Need real team mock data.",
                status: .open,
                priority: .high,
                assigneeAgentId: "maui",
                assigneeAgentName: "Maui",
                ticketType: "bugfix",
                parentTicketId: nil,
                lessonsLearned: nil,
                createdAt: now.addingTimeInterval(-3600),
                updatedAt: now.addingTimeInterval(-1800),
                claimedAt: nil, startedAt: nil, resolvedAt: nil, resolutionNotes: nil
            ),
            Ticket(
                id: "TICKET-004",
                title: "Pod Trading Dashboard",
                description: "Add Trading tab with P&L, Octopus/Squid, Oracle, Earnings, and macro predictions.",
                status: .open,
                priority: .high,
                assigneeAgentId: "maui",
                assigneeAgentName: "Maui",
                ticketType: "feature",
                parentTicketId: nil,
                lessonsLearned: nil,
                createdAt: now.addingTimeInterval(-1800),
                updatedAt: now.addingTimeInterval(-1800),
                claimedAt: nil, startedAt: nil, resolvedAt: nil, resolutionNotes: nil
            ),
            // POD-4 subtask example
            Ticket(
                id: "TICKET-001-SUB",
                title: "Design Whisplay voice UX",
                description: "Design the voice companion tab UI and interaction flow.",
                status: .open,
                priority: .medium,
                assigneeAgentId: "maui",
                assigneeAgentName: "Maui",
                ticketType: "design",
                parentTicketId: "TICKET-001",
                lessonsLearned: nil,
                createdAt: now.addingTimeInterval(-80000),
                updatedAt: now.addingTimeInterval(-80000),
                claimedAt: nil, startedAt: nil, resolvedAt: nil, resolutionNotes: nil
            )
        ]
    }
    #endif

    // MARK: - Create

    @MainActor
    func createTicket() async {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isCreating = true
        defer { isCreating = false }

        let body = CreateTicketBody(
            title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            description: newDescription.isEmpty ? nil : newDescription,
            priority: newPriority.rawValue,
            assigneeAgentId: newAssigneeAgentId.isEmpty ? nil : newAssigneeAgentId,
            parentTicketId: nil,
            lessonsLearned: nil
        )

        do {
            let _: TicketDTO = try await api.post(path: "/api/v1/tickets", body: body)
            newTitle = ""
            newDescription = ""
            newAssigneeAgentId = ""
            newPriority = .normal
            showCreateSheet = false
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't create ticket: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't create ticket. Try again."
        }
    }

    // MARK: - Update Status

    @MainActor
    func updateStatus(ticketId: String, status: TicketStatus) async {
        do {
            let body = UpdateTicketBody(status: status.rawValue)
            let _: TicketDTO = try await api.patch(path: "/api/v1/tickets/\(ticketId)", body: body)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't update status: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't update status. Try again."
        }
    }

    // MARK: - Update Lessons Learned

    @MainActor
    func updateLessonsLearned(ticketId: String, lessonsLearned: String) async {
        do {
            let body = UpdateTicketLessonsBody(lessonsLearned: lessonsLearned)
            let _: TicketDTO = try await api.patch(path: "/api/v1/tickets/\(ticketId)", body: body)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't save lessons: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't save lessons. Try again."
        }
    }

    // MARK: - SSE live updates (b9bbe115 — REST + SSE + write)

    /// Start live subscription to /api/v1/tickets/stream. Reconnects with
    /// exponential backoff capped at 30s. Idempotent — calling twice is a no-op.
    @MainActor
    func startLiveUpdates() {
        guard sseListenTask == nil else { return }
        guard let token = UserDefaults.standard.string(forKey: "orca_auth_token") else { return }

        sseListenTask = Task { @MainActor in
            var backoffNanos: UInt64 = 2_000_000_000  // 2s
            while !Task.isCancelled {
                let manager = SSEStreamManager()
                self.sseManager = manager
                do {
                    let baseURL = AppState.backendURL
                    let events = await manager.connectTickets(token: token, baseURL: baseURL)
                    for try await event in events {
                        if Task.isCancelled { return }
                        switch event {
                        case .connected:
                            backoffNanos = 2_000_000_000  // reset on success
                        case .ticketLifecycle:
                            // Lifecycle delta — refresh authoritative list.
                            // Could optimize to patch-in-place using envelope.metadata.ticket_id
                            // + action, but full reload is correct + simple for current scale.
                            await self.load()
                        case .keepalive, .message, .error:
                            break  // other events not expected on this stream
                        }
                    }
                } catch {
                    // Stream ended — fall through to backoff + reconnect.
                }
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: backoffNanos)
                backoffNanos = min(backoffNanos * 2, 30_000_000_000)  // cap 30s
            }
        }
    }

    /// Cancel the live subscription. Safe to call multiple times.
    @MainActor
    func stopLiveUpdates() {
        sseListenTask?.cancel()
        sseListenTask = nil
        Task { [manager = sseManager] in
            await manager?.disconnect()
        }
        sseManager = nil
    }
}

// MARK: - Request Bodies

private struct CreateTicketBody: Encodable {
    let title: String
    let description: String?
    let priority: String
    let assigneeAgentId: String?
    let status = "open"
    let source = "pod_app"
    let parentTicketId: String?   // POD-4: subtask hierarchy
    let lessonsLearned: String?  // POD-4: lessons-learned capture

    enum CodingKeys: String, CodingKey {
        case title, description, priority, status, source
        case assigneeAgentId = "assignee_agent_id"
        case parentTicketId  = "parent_ticket_id"
        case lessonsLearned  = "lessons_learned"
    }
}

private struct UpdateTicketBody: Encodable {
    let status: String
}

private struct UpdateTicketLessonsBody: Encodable {
    let lessonsLearned: String

    enum CodingKeys: String, CodingKey {
        case lessonsLearned = "lessons_learned"
    }
}

