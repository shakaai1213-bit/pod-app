import Foundation

enum TranscriptRole: String, Sendable {
    case user
    case agent
    case system
}

enum TranscriptDeliveryState: Equatable, Sendable {
    case pending
    case persisted
    case failed(String)
}

struct TranscriptMessage: Identifiable, Equatable, Sendable {
    let id: String
    let role: TranscriptRole
    let content: String
    let createdAt: Date
    var deliveryState: TranscriptDeliveryState
    let retryIdentity: TurnRetryIdentity?
}

struct TurnRetryIdentity: Equatable, Sendable {
    let traceID: String
    let idempotencyKey: String
}

struct RuntimeReceipt: Equatable, Sendable {
    let turnID: String
    let traceID: String
    let source: String
    let lane: String
    let deliveryMode: String?
    let responseState: String?
    let provider: String?
    let model: String?
    let tier: String?
    let computeRunID: String?
}

struct ConversationState: Equatable, Sendable {
    var conversationID: String?
    var messages: [TranscriptMessage] = []
    var latestReceipt: RuntimeReceipt?

    mutating func appendPending(
        id: String,
        content: String,
        at date: Date,
        retryIdentity: TurnRetryIdentity? = nil
    ) {
        messages.append(
            TranscriptMessage(
                id: id,
                role: .user,
                content: content,
                createdAt: date,
                deliveryState: .pending,
                retryIdentity: retryIdentity
            )
        )
    }

    mutating func failPending(id: String, reason: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].deliveryState = .failed(reason)
    }

    mutating func resolvePending(id: String, with canonical: [TranscriptMessage]) {
        messages.removeAll { $0.id == id }
        mergeCanonical(canonical)
    }

    mutating func mergeCanonical(_ canonical: [TranscriptMessage]) {
        let pending = messages.filter {
            if case .pending = $0.deliveryState { return true }
            if case .failed = $0.deliveryState { return true }
            return false
        }
        var byID = Dictionary(uniqueKeysWithValues: messages
            .filter { $0.deliveryState == .persisted }
            .map { ($0.id, $0) })
        canonical.forEach { byID[$0.id] = $0 }
        messages = Array(byID.values) + pending
        messages.sort {
            if $0.createdAt == $1.createdAt { return $0.id < $1.id }
            return $0.createdAt < $1.createdAt
        }
    }
}

enum RuntimeConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case ready
    case credentialsRequired
    case runtimeUpgradeRequired(String)
    case incompatible(String)
    case unavailable(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .ready: return "Connected"
        case .credentialsRequired: return "Connection required"
        case .runtimeUpgradeRequired: return "Runtime upgrade required"
        case .incompatible: return "Contract mismatch"
        case .unavailable: return "Unavailable"
        }
    }

    var isReady: Bool { self == .ready }

    var unavailableTitle: String {
        switch self {
        case .runtimeUpgradeRequired: return "ORCA Runtime Upgrade Required"
        case .credentialsRequired: return "ORCA Connection Required"
        default: return "ORCA Unavailable"
        }
    }

    var unavailableSymbol: String {
        switch self {
        case .runtimeUpgradeRequired: return "arrow.up.circle"
        case .credentialsRequired: return "key"
        default: return "network.slash"
        }
    }
}
