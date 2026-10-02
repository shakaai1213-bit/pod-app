import Foundation
import Testing
@testable import OrcaRuntimeContracts

private func message(_ id: String, type: String = "user", state: String?, kind: OrcaRuntimeTerminalKind? = nil, trace: String? = "awaited") -> OrcaRuntimeConversationMessage {
    .init(id: id, conversationID: "conversation", content: id, messageType: type == "system" ? "system" : "text", senderAgentID: type == "agent" ? "coral" : nil, traceID: trace, source: nil, lane: nil, terminalKind: kind, responseState: state, deliveryState: nil, createdAt: .distantPast, updatedAt: .distantPast)
}

@Test func polledReplyUsesAwaitedUserStateAndNewTerminalNonUserMessages() {
    let pending: [String?] = [nil, "recorded", "waiting_for_live_agent", "waiting_for_agent", "compute_running", "claimed_by_agent", "working", "delivery_degraded", "delivery_nats_failed", "agent_unresponsive"]
    for state in pending {
        #expect(!OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: "turn", awaitedTraceID: "awaited", messages: [message("turn", state: state), message("claim", type: "system", state: state)], oldIDs: ["turn"]))
    }
    for state in ["response_received", "fallback_presented", "ticket_required", "failed"] {
        #expect(OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: "turn", awaitedTraceID: "awaited", messages: [message("turn", state: state)], oldIDs: ["turn"]))
        #expect(OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: "turn", awaitedTraceID: "awaited", messages: [message("system", type: "system", state: state)], oldIDs: ["turn"]))
        #expect(!OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: "turn", awaitedTraceID: "awaited", messages: [message("other", state: state), message("old", type: "agent", state: state)], oldIDs: ["old"]))
    }
    #expect(OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: "turn", awaitedTraceID: "awaited", messages: [message("system", type: "system", state: nil, kind: .held)], oldIDs: []))
    #expect(!OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: "turn", awaitedTraceID: "awaited", messages: [message("turn", state: nil, kind: .held)], oldIDs: ["turn"]))
}

@Test func latestSuccessfulSendReplacesAwaitedUserID() {
    var policy = OrcaConsolePollingPolicy()
    policy.sent()
    policy.recordAwaitedTurn("first")
    policy.sent()
    policy.recordAwaitedTurn("second")
    #expect(policy.awaitedTurnID == "second")
    #expect(!OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: policy.awaitedTurnID, messages: [message("first", state: "response_received"), message("second", state: "working")], oldIDs: ["first", "second"]))
    #expect(OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: policy.awaitedTurnID, messages: [message("second", state: "response_received")], oldIDs: ["second"]))
}

@Test func terminalNoticeRequiresExactNonNilAwaitedTrace() {
    for trace in [nil, "earlier"] as [String?] {
        #expect(!OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: nil, awaitedTraceID: "awaited", messages: [message("notice", type: "system", state: "fallback_presented", trace: trace)], oldIDs: []))
    }
    #expect(!OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: nil, awaitedTraceID: nil, messages: [message("notice", type: "system", state: "fallback_presented", trace: nil)], oldIDs: []))
    #expect(OrcaConsolePollingPolicy.hasPolledReply(awaitedTurnID: nil, awaitedTraceID: "awaited", messages: [message("notice", type: "system", state: nil, kind: .held)], oldIDs: []))
}
