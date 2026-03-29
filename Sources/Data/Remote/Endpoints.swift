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
    case sendMessage(channelId: String, content: String)

    // MARK: - Boards

    case boards
    case boardTasks(boardId: String)

    // MARK: - Agents

    case agents
    case agentStatus(agentId: String)

    // MARK: - Health

    case health
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

        case .sendMessage(let channelId, _):
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
        }
    }

    var method: HTTPMethod {
        switch self {
        case .sendMessage:
            return .post
        default:
            return .get
        }
    }

    var body: Data? {
        switch self {
        case .sendMessage(_, let content):
            let request = SendMessageRequest(content: content)
            return try? JSONEncoder().encode(request)
        default:
            return nil
        }
    }
}
