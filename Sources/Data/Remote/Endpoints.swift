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
    case agentStatus(agentId: String)

    // MARK: - Health

    case health

    // MARK: - Projects (ORCA MC)

    case listProjects(status: String? = nil)
    case createProject(ProjectCreateRequest)
    case getProject(UUID)
    case updateProject(UUID)
    case listProjectTasks(projectId: UUID)
    case createProjectTask(projectId: UUID, title: String, priority: Int?, status: String?)
}

// MARK: - Endpoint Configuration

extension Endpoint {
    private static let basePath = "/api/v1"

    var path: String {
        switch self {
        case .me:
            return "\(Endpoint.basePath)/users/me"

        case .channels:
            return "\(Endpoint.basePath)/channels"

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

        case .agentStatus(let agentId):
            return "\(Endpoint.basePath)/agents/\(agentId)/status"

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
        }
    }

    var method: HTTPMethod {
        switch self {
        case .sendMessage, .createProject, .createProjectTask:
            return .post
        case .updateProject:
            return .patch
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
        default:
            return nil
        }
    }
}
