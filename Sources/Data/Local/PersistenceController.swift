import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            CachedAgent.self,
            CachedChannel.self,
            CachedMessage.self,
            CachedStandard.self,
            ReadingHistory.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var context: ModelContext {
        container.mainContext
    }

    // MARK: - Sync: Agents

    func syncAgents(_ agents: [Agent]) async {
        let ctx = context
        for agent in agents {
            let descriptor = FetchDescriptor<CachedAgent>(
                predicate: #Predicate { $0.id == agent.id }
            )
            let existing = (try? ctx.fetch(descriptor)) ?? []

            if let cached = existing.first {
                cached.name = agent.name
                cached.role = agent.role
                cached.status = agent.status.rawValue
                cached.currentTask = agent.currentTask
                cached.lastActivity = agent.lastActivity
                cached.skills = agent.skills
                cached.avatarColor = agent.avatarColor
                cached.cachedAt = Date()
            } else {
                let cached = CachedAgent(from: agent)
                ctx.insert(cached)
            }
        }
        try? ctx.save()
    }

    // MARK: - Sync: Channels

    func syncChannels(_ channels: [Channel]) async {
        let ctx = context
        for channel in channels {
            let descriptor = FetchDescriptor<CachedChannel>(
                predicate: #Predicate { $0.id == channel.id }
            )
            let existing = (try? ctx.fetch(descriptor)) ?? []

            if let cached = existing.first {
                cached.name = channel.name
                cached.type = channel.type.rawValue
                cached.unreadCount = channel.unreadCount
                cached.lastMessagePreview = channel.lastMessage?.content
                cached.lastMessageTime = channel.lastMessage?.timestamp
                cached.isPinned = channel.isPinned
                cached.cachedAt = Date()
            } else {
                let cached = CachedChannel(from: channel)
                ctx.insert(cached)
            }
        }
        try? ctx.save()
    }

    // MARK: - Sync: Messages

    func syncMessages(_ messages: [Message], for channelId: UUID) async {
        let ctx = context

        // Upsert each message
        for message in messages {
            let descriptor = FetchDescriptor<CachedMessage>(
                predicate: #Predicate { $0.id == message.id }
            )
            let existing = (try? ctx.fetch(descriptor)) ?? []

            if let cached = existing.first {
                cached.channelId = message.channelId
                cached.authorId = message.authorId
                cached.content = message.content
                cached.timestamp = message.timestamp
                cached.isAgent = message.isAgent
                cached.agentId = message.agentId
                cached.cachedAt = Date()
            } else {
                let cached = CachedMessage(from: message)
                ctx.insert(cached)
            }
        }
        try? ctx.save()
    }

    // MARK: - Sync: Standards

    func syncStandards(_ standards: [Standard]) async {
        let ctx = context
        for standard in standards {
            let descriptor = FetchDescriptor<CachedStandard>(
                predicate: #Predicate { $0.id == standard.id }
            )
            let existing = (try? ctx.fetch(descriptor)) ?? []

            if let cached = existing.first {
                cached.title = standard.title
                cached.category = standard.category.rawValue
                cached.content = standard.content
                cached.isFavorite = standard.isFavorite
                cached.readingPosition = standard.readingPosition
                cached.updatedAt = standard.updatedAt
                cached.cachedAt = Date()
            } else {
                let cached = CachedStandard(from: standard)
                ctx.insert(cached)
            }
        }
        try? ctx.save()
    }

    // MARK: - Fetch: Agents

    func fetchCachedAgents() -> [CachedAgent] {
        let descriptor = FetchDescriptor<CachedAgent>(
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchCachedAgent(id: UUID) -> CachedAgent? {
        let descriptor = FetchDescriptor<CachedAgent>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Fetch: Channels

    func fetchCachedChannels() -> [CachedChannel] {
        let descriptor = FetchDescriptor<CachedChannel>(
            sortBy: [
                SortDescriptor(\.isPinned, order: .reverse),
                SortDescriptor(\.lastMessageTime, order: .reverse)
            ]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchCachedChannel(id: UUID) -> CachedChannel? {
        let descriptor = FetchDescriptor<CachedChannel>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Fetch: Messages

    func fetchCachedMessages(channelId: UUID, limit: Int = 50) -> [CachedMessage] {
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { $0.channelId == channelId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        var fetchDescriptor = descriptor
        fetchDescriptor.fetchLimit = limit
        return (try? context.fetch(fetchDescriptor)) ?? []
    }

    // MARK: - Fetch: Standards

    func fetchRecentStandards(limit: Int = 10) -> [CachedStandard] {
        var descriptor = FetchDescriptor<CachedStandard>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchFavorites() -> [CachedStandard] {
        let descriptor = FetchDescriptor<CachedStandard>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchStandardsByCategory(_ category: String) -> [CachedStandard] {
        let descriptor = FetchDescriptor<CachedStandard>(
            predicate: #Predicate { $0.category == category },
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Reading History

    func updateReadingHistory(standardId: UUID, position: Int) {
        let descriptor = FetchDescriptor<ReadingHistory>(
            predicate: #Predicate { $0.standardId == standardId }
        )
        let existing = (try? context.fetch(descriptor)) ?? []

        if let history = existing.first {
            history.lastReadAt = Date()
            history.readingPosition = position
        } else {
            let history = ReadingHistory(standardId: standardId, lastReadAt: Date(), readingPosition: position)
            context.insert(history)
        }
        try? context.save()
    }

    func fetchReadingHistory(standardId: UUID) -> ReadingHistory? {
        let descriptor = FetchDescriptor<ReadingHistory>(
            predicate: #Predicate { $0.standardId == standardId }
        )
        return (try? context.fetch(descriptor))?.first
    }

    func fetchRecentlyRead(limit: Int = 10) -> [ReadingHistory] {
        var descriptor = FetchDescriptor<ReadingHistory>(
            sortBy: [SortDescriptor(\.lastReadAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Favorites Toggle

    func toggleFavorite(standardId: UUID) {
        let descriptor = FetchDescriptor<CachedStandard>(
            predicate: #Predicate { $0.id == standardId }
        )
        guard let cached = (try? context.fetch(descriptor))?.first else { return }
        cached.isFavorite.toggle()
        try? context.save()
    }

    // MARK: - Clear

    func clearAll() async {
        let ctx = context
        try? ctx.delete(model: CachedAgent.self)
        try? ctx.delete(model: CachedChannel.self)
        try? ctx.delete(model: CachedMessage.self)
        try? ctx.delete(model: CachedStandard.self)
        try? ctx.delete(model: ReadingHistory.self)
        try? ctx.save()
    }

    func clearMessages(for channelId: UUID) async {
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        let messages = (try? context.fetch(descriptor)) ?? []
        for msg in messages {
            context.delete(msg)
        }
        try? context.save()
    }
}
