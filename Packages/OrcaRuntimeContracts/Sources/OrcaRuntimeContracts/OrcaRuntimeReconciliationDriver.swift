import Foundation

public typealias OrcaRuntimeReconciliationPoller = @Sendable (
    _ turnID: String,
    _ afterCursor: String?
) async throws -> Components.Schemas.ChatRuntimeTurnReconciliationRead

public typealias OrcaRuntimeReconciliationStreamer = @Sendable (
    _ turnID: String,
    _ afterCursor: String?
) async throws -> AsyncThrowingStream<Components.Schemas.ChatRuntimeTurnReconciliationRead, Error>

public typealias OrcaRuntimeReconciliationSleeper = @Sendable (
    _ seconds: Int
) async throws -> Void

/// Console opts in explicitly; shared clients retain the original runtime contract.
public enum OrcaRuntimeReconciliationPolicy: Sendable {
    case legacy
    case console

    func pollDelay(_ hint: Int?, previous: Int, stuck: Bool) -> Int {
        switch self {
        case .legacy: return hint ?? previous
        case .console: return OrcaConsolePollingPolicy.pollDelay(hint ?? previous, stuck: stuck)
        }
    }

    func failureDelay(_ previous: Int) -> Int {
        switch self {
        case .legacy: return min(8, max(2, previous * 2))
        case .console: return min(120, max(previous, min(8, previous * 2)))
        }
    }
}

public struct OrcaRuntimeReconciliationDriver: Sendable {
    private let policy: OrcaRuntimeReconciliationPolicy
    private let turnID: String
    private let persistedCursor: String?
    private let poll: OrcaRuntimeReconciliationPoller
    private let stream: OrcaRuntimeReconciliationStreamer
    private let persistCursor: @Sendable (String) -> Void
    private let sleep: OrcaRuntimeReconciliationSleeper

    public init(
        turnID: String,
        persistedCursor: String? = nil,
        policy: OrcaRuntimeReconciliationPolicy = .legacy,
        poll: @escaping OrcaRuntimeReconciliationPoller,
        stream: @escaping OrcaRuntimeReconciliationStreamer,
        persistCursor: @escaping @Sendable (String) -> Void = { _ in },
        sleep: @escaping OrcaRuntimeReconciliationSleeper = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.policy = policy
        self.turnID = turnID
        self.persistedCursor = persistedCursor
        self.poll = poll
        self.stream = stream
        self.persistCursor = persistCursor
        self.sleep = sleep
    }

    public func updates() -> AsyncThrowingStream<OrcaRuntimeReconciliationUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var reconciler = OrcaRuntimeTurnReconciler(
                        turnID: turnID,
                        persistedCursor: persistedCursor,
                        policy: policy
                    )
                    var pollAfterSeconds = 2
                    var consecutivePollFailures = 0

                    let initialEnvelope = try await poll(
                        turnID,
                        reconciler.reconciliationCursor
                    )
                    let initial = try reconciler.apply(initialEnvelope)
                    persistCursor(initial.cursor)
                    continuation.yield(initial)
                    if initial.turn.terminalOutcome != nil {
                        continuation.finish()
                        return
                    }
                    pollAfterSeconds = policy.pollDelay(initial.pollAfterSeconds, previous: pollAfterSeconds, stuck: initial.turn.recovery.isStuck)

                    while !Task.isCancelled {
                        do {
                            let live = try await stream(
                                turnID,
                                reconciler.reconciliationCursor
                            )
                            for try await envelope in live {
                                try Task.checkCancellation()
                                let update = try reconciler.apply(envelope)
                                persistCursor(update.cursor)
                                continuation.yield(update)
                                pollAfterSeconds = policy.pollDelay(update.pollAfterSeconds, previous: pollAfterSeconds, stuck: update.turn.recovery.isStuck)
                                if update.turn.terminalOutcome != nil {
                                    continuation.finish()
                                    return
                                }
                            }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch let error as OrcaRuntimeTimelineError {
                            throw error
                        } catch let error as OrcaRuntimeSSEError {
                            throw error
                        } catch let error as OrcaRuntimeClientError {
                            guard case .httpStatus = error else { throw error }
                        } catch {
                            // A transport disconnect falls through to the same REST cursor.
                        }

                        try await sleep(pollAfterSeconds)
                        do {
                            let envelope = try await poll(
                                turnID,
                                reconciler.reconciliationCursor
                            )
                            let update = try reconciler.apply(envelope)
                            persistCursor(update.cursor)
                            continuation.yield(update)
                            pollAfterSeconds = policy.pollDelay(update.pollAfterSeconds, previous: pollAfterSeconds, stuck: update.turn.recovery.isStuck)
                            consecutivePollFailures = 0
                            if update.turn.terminalOutcome != nil {
                                continuation.finish()
                                return
                            }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            consecutivePollFailures += 1
                            guard consecutivePollFailures < 3 else { throw error }
                            pollAfterSeconds = policy.failureDelay(pollAfterSeconds)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
