import Foundation
import Testing
@testable import OrcaRuntimeContracts

// Regression probes supplied by Rooster (RO-998).

/// The owner condition says a reply that arrives 40.1 s after sending is shown within 4 s. The PR's own test proves it for a healthy
/// outstanding turn. Here the reconcile call fails once right after the send (a 404 or a network error).
@Test func probeReplyAtFortySecondsAfterReconcileFailure() {
    var policy = OrcaConsolePollingPolicy()
    policy.sent()
    policy.failed(now: Date(timeIntervalSince1970: 0))
    var nextPoll = 4.0
    let arrival = 40.1
    var ticks: [Double] = []
    while nextPoll < arrival {
        ticks.append(nextPoll)
        policy.messagesMerged(changed: false)
        nextPoll += policy.messageInterval
    }
    print("PROBE reconcile-failure: message polls at \(ticks), reply visible at \(nextPoll), late by \(nextPoll - arrival)")
    #expect(nextPoll - arrival <= 4)
}

/// The same scenario when the message poll itself keeps succeeding and only the reconcile call failed, but the failure is NOT allowed to
/// demote message polling (the behaviour I would expect): expressed as the property "a failed reconcile does not change messageInterval".
@Test func probeReconcileFailureDoesNotChangeMessageInterval() {
    var policy = OrcaConsolePollingPolicy()
    policy.sent()
    let before = policy.messageInterval
    policy.failed(now: Date(timeIntervalSince1970: 0))
    policy.messagesMerged(changed: false)
    print("PROBE interval after one failed reconcile and one unchanged message poll: \(policy.messageInterval) (healthy baseline would stay \(before))")
    #expect(policy.messageInterval == before)
}

/// Terminal-turn list bound (64): the PR does not test it.
@Test func probeTerminalTurnListIsBounded() {
    var policy = OrcaConsolePollingPolicy()
    let now = Date(timeIntervalSince1970: 0)
    for i in 0..<65 { policy.updated(turn: "t\(i)", terminal: true, stuck: false, hint: nil, now: now) }
    // the oldest are forgotten, the newest are retained
    #expect(policy.shouldReconcile(turn: "t64", now: now) == false)
    #expect(policy.shouldReconcile(turn: "t1", now: now) == false)
    #expect(policy.shouldReconcile(turn: "t0", now: now) == true)
}

@Test func awaitingReplyGraceExpiresWithoutTurnUpdates() {
    var policy = OrcaConsolePollingPolicy()
    let sent = Date(timeIntervalSince1970: 0)
    policy.sent(now: sent)
    for tick in stride(from: 4, through: 296, by: 4) {
        policy.failed(now: sent.addingTimeInterval(Double(tick)))
        policy.messagesMerged(changed: false, now: sent.addingTimeInterval(Double(tick)))
        #expect(policy.messageInterval == 4)
    }
    policy.messagesMerged(changed: false, now: sent.addingTimeInterval(300))
    #expect(!policy.awaitingReply)
    #expect(policy.messageInterval == 8)
    policy.messagesMerged(changed: false, now: sent.addingTimeInterval(308))
    #expect(policy.messageInterval == 16)
}

@Test func awaitingReplyClearsOnlyForReplyTerminalStuckOrMessageFailure() {
    let now = Date()
    for reason in 0..<4 {
        var policy = OrcaConsolePollingPolicy()
        policy.sent(now: now)
        policy.updated(turn: "turn", terminal: false, stuck: false, hint: nil, now: now)
        policy.failed(now: now)
        #expect(policy.awaitingReply)
        switch reason {
        case 0: policy.messagesMerged(changed: true, agentMessageMerged: true, now: now)
        case 1: policy.updated(turn: "turn", terminal: true, stuck: false, hint: nil, now: now)
        case 2: policy.updated(turn: "turn", terminal: false, stuck: true, hint: nil, now: now)
        default: policy.messagesFailed()
        }
        #expect(!policy.awaitingReply)
        policy.updated(turn: "turn", terminal: false, stuck: false, hint: nil, now: now)
        #expect(!policy.awaitingReply)
    }
}
