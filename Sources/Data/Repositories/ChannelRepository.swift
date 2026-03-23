import Foundation

@MainActor
final class ChannelRepository {
    private let api = APIClient.shared
    private let cache = PersistenceController.shared

    var channels: [Channel] = []
    var isLoading: Bool = false
    var lastError: Error?

    private init() {}

    // MARK: - Load

    func loadChannels() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let dtos: [ChannelDTO] = try await api.get(path: Endpoint.channels.path)
            let remote = dtos.map { dto -> Channel in
                Channel(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    type: mapChannelType(dto.type),
                    lastMessage: dto.description,
                    lastMessageTimestamp: nil,
                    unreadCount: dto.unreadCount,
                    isPinned: dto.isPinned,
                    isMuted: false
                )
            }
            channels = remote
            await cache.syncChannels(remote)
        } catch {
            lastError = error
            let cached = cache.fetchCachedChannels()
            channels = cached.map { $0.toChannel() }
        }
    }

    // MARK: - Load Messages for Channel

    func loadMessages(channelId: UUID) async -> [Message] {
        do {
            let dtos: [MessageDTO] = try await api.get(
                path: Endpoint.channelMessages(channelId: channelId.uuidString).path
            )
            let messages = dtos.map { dto -> Message in
                Message(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    channelId: UUID(uuidString: dto.channelId) ?? channelId,
                    authorId: UUID(uuidString: dto.authorId) ?? UUID(),
                    isAgent: dto.isAgent,
                    agentId: dto.agentId,
                    content: dto.content,
                    timestamp: dto.timestamp,
                    reactions: dto.reactions?.map { r in
                        Reaction(
                            emoji: r.emoji,
                            count: r.count,
                            userIds: r.userIds,
                            isReactedByMe: false
                        )
                    } ?? []
                )
            }
            await cache.syncMessages(messages, for: channelId)
            return messages
        } catch {
            let cached = cache.fetchCachedMessages(channelId: channelId)
            return cached.map { $0.toMessage() }
        }
    }

    // MARK: - Send Message

    func sendMessage(channelId: UUID, content: String) async throws -> Message {
        let dto: MessageDTO = try await api.post(
            path: Endpoint.sendMessage(channelId: channelId.uuidString, content: content).path,
            body: SendMessageRequest(content: content)
        )

        let message = Message(
            id: UUID(uuidString: dto.id) ?? UUID(),
            channelId: UUID(uuidString: dto.channelId) ?? channelId,
            authorId: UUID(uuidString: dto.authorId) ?? UUID(),
            isAgent: dto.isAgent,
            agentId: dto.agentId,
            content: dto.content,
            timestamp: dto.timestamp,
            reactions: []
        )

        await cache.syncMessages([message], for: channelId)
        return message
    }

    // MARK: - Queries

    func getChannel(id: UUID) -> Channel? {
        channels.first { $0.id == id }
    }

    func channelsByType(_ type: DTOChatChannelType) -> [Channel] {
        channels.filter { reverseMapChannelType($0.type) == type }
    }

    var pinnedChannels: [Channel] {
        channels.filter { $0.isPinned }
    }

    var totalUnreadCount: Int {
        channels.reduce(0) { $0 + $1.unreadCount }
    }

    // MARK: - Cached Messages

    func getCachedMessages(channelId: UUID) -> [Message] {
        cache.fetchCachedMessages(channelId: channelId).map { $0.toMessage() }
    }

    // MARK: - Mapping

    private func mapChannelType(_ dtoType: DTOChatChannelType) -> ChatChannelType {
        switch dtoType {
        case .general:   return .general
        case .project:   return .projects
        case .agent:     return .agents
        case .research:  return .research
        case .alerts:    return .alerts
        }
    }

    private func reverseMapChannelType(_ vmType: ChatChannelType) -> DTOChatChannelType {
        switch vmType {
        case .general:   return .general
        case .projects:  return .project
        case .agents:    return .agent
        case .research:  return .research
        case .alerts:    return .alerts
        }
    }
}
