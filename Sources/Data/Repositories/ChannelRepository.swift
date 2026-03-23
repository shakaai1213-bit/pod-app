import Foundation

// Resolve name collisions: domain and DTOs both define ChannelType
typealias DomainChannelType = Domain.Entities.ChannelType

@Observable
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
            let dtos: [ChannelDTO] = try await api.get(Endpoint.channels.path)
            let remote = dtos.map { dto -> Channel in
                Channel(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    type: mapChannelType(dto.type),
                    description: dto.description ?? "",
                    isPinned: dto.isPinned,
                    unreadCount: dto.unreadCount,
                    lastMessage: nil
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
        let path = Endpoint.channelMessages(channelId: channelId.uuidString).path
        do {
            let dtos: [MessageDTO] = try await api.get(path)
            let messages = dtos.map { dto -> Message in
                Message(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    channelId: UUID(uuidString: dto.channelId) ?? channelId,
                    authorId: UUID(uuidString: dto.authorId) ?? UUID(),
                    content: dto.content,
                    timestamp: dto.timestamp,
                    isAgent: dto.isAgent,
                    agentId: dto.agentId,
                    reactions: dto.reactions?.map { r in
                        Reaction(
                            id: UUID(),
                            emoji: r.emoji,
                            userIds: r.userIds.compactMap { UUID(uuidString: $0) }
                        )
                    } ?? [],
                    threadCount: dto.threadCount
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
        let path = Endpoint.sendMessage(channelId: channelId.uuidString, content: content).path
        let dto: MessageDTO = try await api.post(path, body: SendMessageRequest(content: content))

        let message = Message(
            id: UUID(uuidString: dto.id) ?? UUID(),
            channelId: UUID(uuidString: dto.channelId) ?? channelId,
            authorId: UUID(uuidString: dto.authorId) ?? UUID(),
            content: dto.content,
            timestamp: dto.timestamp,
            isAgent: dto.isAgent,
            agentId: dto.agentId,
            reactions: [],
            threadCount: 0
        )

        await cache.syncMessages([message], for: channelId)
        return message
    }

    // MARK: - Queries

    func getChannel(id: UUID) -> Channel? {
        channels.first { $0.id == id }
    }

    func channelsByType(_ type: DomainChannelType) -> [Channel] {
        channels.filter { $0.type == type }
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

    /// Maps DTO ChannelType → Domain ChannelType
    private func mapChannelType(_ dtoType: ChannelType) -> DomainChannelType {
        switch dtoType {
        case .general:  return .general
        case .project:  return .project
        case .agent:    return .agent
        case .research: return .research
        case .alerts:   return .alerts
        }
    }
}
