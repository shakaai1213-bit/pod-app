import Foundation
import Testing
@testable import OrcaRuntimeContracts

// Regression tests from Rooster’s FIX1 delta review.

/// A reply made of two agent messages (an interim one, then the final answer) while the runtime turn is still working.
/// The reconcile call keeps reporting a healthy, non-terminal turn, so the turn is genuinely still in progress.
@Test func testInterimAgentMessageDoesNotEndFastPollingWhileTurnIsWorking() {
    var policy = OrcaConsolePollingPolicy()
    let t0 = Date(timeIntervalSince1970: 0)
    policy.sent(now: t0)
    policy.updated(turn: "turn", terminal: false, stuck: false, hint: 2, now: t0)
    let arrivals: [(String, Double)] = [("interim", 6.0), ("final", 40.1)]
    var seen = Set<String>()
    var now = 4.0
    var finalVisibleAt: Double?
    var polls: [Double] = []
    while now <= 300, finalVisibleAt == nil {
        polls.append(now)
        let fresh = arrivals.filter { $0.1 <= now && !seen.contains($0.0) }
        fresh.forEach { seen.insert($0.0) }
        if fresh.contains(where: { $0.0 == "final" }) { finalVisibleAt = now }
        policy.messagesMerged(changed: !fresh.isEmpty, replyArrived: !fresh.isEmpty, now: t0.addingTimeInterval(now))
        now += policy.messageInterval
    }
    let late = (finalVisibleAt ?? 999) - 40.1
    print("PROBE interim+final (turn still working): message polls at \(polls), final visible at \(finalVisibleAt ?? -1), late by \(late)")
    #expect(late <= 4)
}

/// Grace boundary: one second before the limit the fast cadence still holds, at the limit it ends.
@Test func testGraceBoundaryIsExactlyThreeHundredSeconds() {
    var policy = OrcaConsolePollingPolicy()
    let t0 = Date(timeIntervalSince1970: 0)
    policy.sent(now: t0)
    policy.messagesMerged(changed: false, now: t0.addingTimeInterval(299))
    #expect(policy.awaitingReply)
    #expect(policy.messageInterval == 4)
    policy.messagesMerged(changed: false, now: t0.addingTimeInterval(300))
    #expect(!policy.awaitingReply)
    #expect(policy.messageInterval == 8)
}

/// A new send re-arms the wait even after the grace expired.
@Test func testSendAfterGraceRearmsAwaitingReply() {
    var policy = OrcaConsolePollingPolicy()
    let t0 = Date(timeIntervalSince1970: 0)
    policy.sent(now: t0)
    policy.messagesMerged(changed: false, now: t0.addingTimeInterval(400))
    #expect(!policy.awaitingReply)
    policy.sent(now: t0.addingTimeInterval(401))
    #expect(policy.awaitingReply)
    policy.messagesMerged(changed: false, now: t0.addingTimeInterval(405))
    #expect(policy.messageInterval == 4)
}
