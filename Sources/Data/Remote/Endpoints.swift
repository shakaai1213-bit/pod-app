import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum Endpoint {
    // MARK: - User

    case me

    // MARK: - Chat

    case channels
    case channelMessages(channelId: String)
    case sendMessage(channelId: String, content: String, replyToId: String? = nil)

    // MARK: - Boards

    case boards
    case boardTasks(boardId: String)

    // MARK: - Agents

    case agents
    case ticket(id: String)
    case agentStatus(agentId: String)
    case agentInboxTail(name: String, limit: Int)   // POD-5 (c797ada1): non-destructive inbox tail
    case agentActivationContext(name: String, limit: Int)
    case agentLocker(name: String, limit: Int)
    case planner(agentId: UUID)
    case createPlannerItem(agentId: UUID, PlannerItemCreateRequest)
    case updatePlannerItem(agentId: UUID, itemId: String, PlannerItemUpdateRequest)
    case deletePlannerItem(agentId: UUID, itemId: String)
    case leadPlate(leadId: String)

    // MARK: - Health

    case health

    // MARK: - Projects (ORCA MC)

    case listProjects(status: String? = nil)
    case createProject(ProjectCreateRequest)
    case getProject(UUID)
    case updateProject(UUID)
    case listProjectTasks(projectId: UUID)
    case createProjectTask(projectId: UUID, title: String, priority: Int?, status: String?)

    // MARK: - Memory

    case memoryCandidateReviewExport
}

// MARK: - Endpoint Configuration

extension Endpoint {
    private static let basePath = "/api/v1"

    var path: String {
        switch self {
        case .me:
            return "\(Endpoint.basePath)/users/me"

        case .channels:
            return "\(Endpoint.basePath)/chat/channels"

        case .channelMessages(let channelId):
            return "\(Endpoint.basePath)/chat/channels/\(channelId)/messages"

        case .sendMessage(let channelId, _, _):
            return "\(Endpoint.basePath)/chat/channels/\(channelId)/messages"

        case .boards:
            return "\(Endpoint.basePath)/boards"

        case .boardTasks(let boardId):
            return "\(Endpoint.basePath)/boards/\(boardId)/tasks"

        case .agents:
            return "\(Endpoint.basePath)/agents"

        case .ticket(let id):
            let safeId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            return "\(Endpoint.basePath)/tickets/\(safeId)"

        case .agentStatus(let agentId):
            return "\(Endpoint.basePath)/agents/\(agentId)/status"

        case .agentInboxTail(let name, let limit):
            return "\(Endpoint.basePath)/agents/\(name)/inbox-tail?limit=\(limit)"

        case .agentActivationContext(let name, let limit):
            return "\(Endpoint.basePath)/agents/\(name)/activation-context?limit=\(limit)"

        case .agentLocker(let name, let limit):
            return "\(Endpoint.basePath)/agents/\(name)/locker-cockpit?limit=\(limit)"

        case .planner(let agentId):
            return "\(Endpoint.basePath)/planner/\(agentId.uuidString)"

        case .createPlannerItem(let agentId, _):
            return "\(Endpoint.basePath)/planner/\(agentId.uuidString)/items"

        case .updatePlannerItem(let agentId, let itemId, _):
            let safeItemId = itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemId
            return "\(Endpoint.basePath)/planner/\(agentId.uuidString)/items/\(safeItemId)"

        case .deletePlannerItem(let agentId, let itemId):
            let safeItemId = itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemId
            return "\(Endpoint.basePath)/planner/\(agentId.uuidString)/items/\(safeItemId)"

        case .leadPlate(let leadId):
            return "\(Endpoint.basePath)/leads/\(leadId)/plate"

        case .health:
            return "\(Endpoint.basePath)/health"

        case .listProjects(let status):
            var path = "\(Endpoint.basePath)/projects/"
            if let s = status { path += "?status=\(s)" }
            return path

        case .createProject:
            return "\(Endpoint.basePath)/projects/"

        case .getProject(let id):
            return "\(Endpoint.basePath)/projects/\(id)"

        case .updateProject(let id):
            return "\(Endpoint.basePath)/projects/\(id)"

        case .listProjectTasks(let projectId):
            return "\(Endpoint.basePath)/projects/\(projectId)/tasks"

        case .createProjectTask(let projectId, _, _, _):
            return "\(Endpoint.basePath)/projects/\(projectId)/tasks"

        case .memoryCandidateReviewExport:
            return "\(Endpoint.basePath)/memory/candidates/review-export"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .sendMessage, .createProject, .createProjectTask, .memoryCandidateReviewExport, .createPlannerItem:
            return .post
        case .updateProject, .updatePlannerItem:
            return .patch
        case .deletePlannerItem:
            return .delete
        default:
            return .get
        }
    }

    var body: Data? {
        switch self {
        case .sendMessage(_, let content, let replyToId):
            let request = SendMessageRequest(content: content, replyToId: replyToId)
            return try? JSONEncoder().encode(request)
        case .createProject(let req):
            return try? JSONEncoder().encode(req)
        case .createProjectTask(_, let title, let priority, let status):
            struct Body: Encodable {
                let title: String; let priority: Int?; let status: String?
            }
            return try? JSONEncoder().encode(Body(title: title, priority: priority, status: status))
        case .createPlannerItem(_, let request):
            return try? JSONEncoder().encode(request)
        case .updatePlannerItem(_, _, let request):
            return try? JSONEncoder().encode(request)
        default:
            return nil
        }
    }
}

struct PlannerItemCreateRequest: Encodable {
    let kind: String
    let title: String
    let body: String?
    let lane: String
    let priority: String
    let sourceType: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case kind, title, body, lane, priority, status
        case sourceType = "source_type"
    }

    init(
        kind: String = "planner_item",
        title: String,
        body: String? = nil,
        lane: String,
        priority: String = "medium",
        sourceType: String? = "manual",
        status: String? = "active"
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.lane = lane
        self.priority = priority
        self.sourceType = sourceType
        self.status = status
    }
}

struct PlannerItemUpdateRequest: Encodable {
    let title: String?
    let body: String?
    let lane: String?
    let priority: String?
    let status: String?

    init(title: String? = nil, body: String? = nil, lane: String? = nil, priority: String? = nil, status: String? = nil) {
        self.title = title
        self.body = body
        self.lane = lane
        self.priority = priority
        self.status = status
    }
}
