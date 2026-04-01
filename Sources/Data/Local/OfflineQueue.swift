import Foundation
import SwiftData

// MARK: - CachedQueueMessage (SwiftData model for offline queue)

@Model
final class CachedQueueMessage {
    @Attribute(.unique) var id: UUID
    var channelId: UUID
    var content: String
    var queueStateRaw: String  // "pending", "sending", "sent", "failed"
    var createdAt: Date
    var attempts: Int
    var lastError: String?

    var queueState: QueueState {
        get { QueueState(rawValue: queueStateRaw) ?? .pending }
        set { queueStateRaw = newValue.rawValue }
    }

    enum QueueState: String, Codable {
        case pending
        case sending
        case sent
        case failed
    }

    init(id: UUID, channelId: UUID, content: String, queueStateRaw: String, createdAt: Date, attempts: Int, lastError: String?) {
        self.id = id
        self.channelId = channelId
        self.content = content
        self.queueStateRaw = queueStateRaw
        self.createdAt = createdAt
        self.attempts = attempts
        self.lastError = lastError
    }
}

// MARK: - OfflineQueue Actor

/// Offline message queue.
/// Messages sent while offline are stored locally and flushed when reconnected.
@MainActor
final class OfflineQueue {
    // Uses CachedQueueMessage.QueueState from the CachedQueueMessage model.

    struct QueueEntry: Sendable {
        let id: UUID
        let channelId: UUID
        let content: String
        let queueState: CachedQueueMessage.QueueState
    }

    // MARK: - State

    private let modelContainer: ModelContainer

    // MARK: - Init

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Enqueue

    /// Stores a message in the offline queue with .pending state.
    func enqueue(channelId: UUID, content: String) async -> UUID {
        let ctx = modelContainer.mainContext
        let cached = CachedQueueMessage(
            id: UUID(),
            channelId: channelId,
            content: content,
            queueStateRaw: CachedQueueMessage.QueueState.pending.rawValue,
            createdAt: Date(),
            attempts: 0,
            lastError: nil
        )
        ctx.insert(cached)
        try? ctx.save()
        return cached.id
    }

    // MARK: - Flush

    /// Sends all pending messages via the API. Updates state to .sent on success,
    /// .failed on error. Returns the IDs that were successfully sent.
    func flush() async -> [UUID] {
        let ctx = modelContainer.mainContext
        let pending = fetchPending(in: ctx)

        var sentIds: [UUID] = []

        for cached in pending {
            cached.queueStateRaw = CachedQueueMessage.QueueState.sending.rawValue
            try? ctx.save()

            do {
                let _: MessageDTO = try await APIClient.shared.post(
                    path: Endpoint.sendMessage(
                        channelId: cached.channelId.uuidString,
                        content: cached.content,
                        replyToId: nil
                    ).path,
                    body: SendMessageRequest(content: cached.content, replyToId: nil)
                )
                cached.queueStateRaw = CachedQueueMessage.QueueState.sent.rawValue
                try? ctx.save()
                sentIds.append(cached.id)
            } catch {
                cached.attempts += 1
                cached.lastError = error.localizedDescription
                cached.queueStateRaw = CachedQueueMessage.QueueState.failed.rawValue
                try? ctx.save()
            }
        }

        return sentIds
    }

    /// Returns all pending + sending message IDs so callers can update UI state.
    func pendingIds() async -> [UUID] {
        let ctx = modelContainer.mainContext
        return fetchPending(in: ctx).map(\.id)
    }

    /// Returns the current state for a given message ID, if it's in the cache.
    func state(for id: UUID) async -> CachedQueueMessage.QueueState? {
        let ctx = modelContainer.mainContext
        let descriptor = FetchDescriptor<CachedQueueMessage>(
            predicate: #Predicate { $0.id == id }
        )
        guard let cached = (try? ctx.fetch(descriptor))?.first else { return nil }
        return CachedQueueMessage.QueueState(rawValue: cached.queueStateRaw)
    }

    /// Removes a message from the queue (after successful send).
    func remove(id: UUID) async {
        let ctx = modelContainer.mainContext
        let descriptor = FetchDescriptor<CachedQueueMessage>(
            predicate: #Predicate { $0.id == id }
        )
        guard let cached = (try? ctx.fetch(descriptor))?.first else { return }
        ctx.delete(cached)
        try? ctx.save()
    }

    /// Marks a message as failed manually (for retry).
    func markFailed(id: UUID, error: String?) async {
        let ctx = modelContainer.mainContext
        let descriptor = FetchDescriptor<CachedQueueMessage>(
            predicate: #Predicate { $0.id == id }
        )
        guard let cached = (try? ctx.fetch(descriptor))?.first else { return }
        cached.queueStateRaw = CachedQueueMessage.QueueState.failed.rawValue
        cached.lastError = error
        try? ctx.save()
    }

    // MARK: - Private

    private func fetchPending(in ctx: ModelContext) -> [CachedQueueMessage] {
        let pending = CachedQueueMessage.QueueState.pending.rawValue
        let sending = CachedQueueMessage.QueueState.sending.rawValue
        let descriptor = FetchDescriptor<CachedQueueMessage>(
            predicate: #Predicate {
                $0.queueStateRaw == pending || $0.queueStateRaw == sending
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? ctx.fetch(descriptor)) ?? []
    }
}

