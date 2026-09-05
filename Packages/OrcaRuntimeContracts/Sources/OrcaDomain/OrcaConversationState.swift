import Foundation

public enum OrcaTranscriptRole: String, Codable, Sendable {
    case user
    case agent
    case system
}

public enum OrcaTranscriptDeliveryState: Equatable, Sendable {
    case pending
    case persisted
    case failed(String)
}

public struct OrcaTurnRetryIdentity: Equatable, Sendable {
    public let traceID: String
    public let idempotencyKey: String

    public init(traceID: String, idempotencyKey: String) {
        self.traceID = traceID
        self.idempotencyKey = idempotencyKey
    }
}

public struct OrcaTranscriptMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let role: OrcaTranscriptRole
    public let content: String
    public let createdAt: Date
    public var deliveryState: OrcaTranscriptDeliveryState
    public let retryIdentity: OrcaTurnRetryIdentity?

    public init(
        id: String,
        role: OrcaTranscriptRole,
        content: String,
        createdAt: Date,
        deliveryState: OrcaTranscriptDeliveryState,
        retryIdentity: OrcaTurnRetryIdentity?
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.deliveryState = deliveryState
        self.retryIdentity = retryIdentity
    }
}

public struct OrcaRuntimeReceipt: Equatable, Sendable {
    public let turnID: String
    public let traceID: String
    public let source: String
    public let lane: String
    public let deliveryMode: String?
    public let responseState: String?
    public let provider: String?
    public let model: String?
    public let tier: String?
    public let computeRunID: String?

    public init(
        turnID: String,
        traceID: String,
        source: String,
        lane: String,
        deliveryMode: String?,
        responseState: String?,
        provider: String?,
        model: String?,
        tier: String?,
        computeRunID: String?
    ) {
        self.turnID = turnID
        self.traceID = traceID
        self.source = source
        self.lane = lane
        self.deliveryMode = deliveryMode
        self.responseState = responseState
        self.provider = provider
        self.model = model
        self.tier = tier
        self.computeRunID = computeRunID
    }
}

public struct OrcaConversationState: Equatable, Sendable {
    public var conversationID: String?
    public var messages: [OrcaTranscriptMessage]
    public var latestReceipt: OrcaRuntimeReceipt?

    public init(
        conversationID: String? = nil,
        messages: [OrcaTranscriptMessage] = [],
        latestReceipt: OrcaRuntimeReceipt? = nil
    ) {
        self.conversationID = conversationID
        self.messages = messages
        self.latestReceipt = latestReceipt
    }

    public mutating func appendPending(
        id: String,
        content: String,
        at date: Date,
        retryIdentity: OrcaTurnRetryIdentity? = nil
    ) {
        messages.append(OrcaTranscriptMessage(
            id: id,
            role: .user,
            content: content,
            createdAt: date,
            deliveryState: .pending,
            retryIdentity: retryIdentity
        ))
    }

    public mutating func failPending(id: String, reason: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].deliveryState = .failed(reason)
    }

    public mutating func resolvePending(id: String, with canonical: [OrcaTranscriptMessage]) {
        messages.removeAll { $0.id == id }
        mergeCanonical(canonical)
    }

    public mutating func mergeCanonical(_ canonical: [OrcaTranscriptMessage]) {
        let local = messages.filter {
            switch $0.deliveryState {
            case .pending, .failed: return true
            case .persisted: return false
            }
        }
        var byID = Dictionary(uniqueKeysWithValues: messages.compactMap { message in
            message.deliveryState == .persisted ? (message.id, message) : nil
        })
        canonical.forEach { byID[$0.id] = $0 }
        messages = Array(byID.values) + local
        messages.sort {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
    }
}

public enum OrcaRuntimeConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case ready
    case credentialsRequired
    case runtimeUpgradeRequired(String)
    case incompatible(String)
    case unavailable(String)

    public var label: String {
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

    public var isReady: Bool { self == .ready }

    public var unavailableTitle: String {
        switch self {
        case .runtimeUpgradeRequired: return "ORCA Runtime Upgrade Required"
        case .credentialsRequired: return "ORCA Connection Required"
        default: return "ORCA Unavailable"
        }
    }

    public var unavailableSymbol: String {
        switch self {
        case .runtimeUpgradeRequired: return "arrow.up.circle"
        case .credentialsRequired: return "key"
        default: return "network.slash"
        }
    }
}
