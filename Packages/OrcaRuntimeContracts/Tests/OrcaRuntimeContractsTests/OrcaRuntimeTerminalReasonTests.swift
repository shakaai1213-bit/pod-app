import Foundation
import Testing
@testable import OrcaRuntimeContracts

@Test("Reply-blocked error code maps to a precise, route-neutral reason")
func replyBlockedErrorCodeIsPrecise() throws {
    let reason = try #require(
        OrcaRuntimeTerminalReason(errorCode: "reply_blocked_operational_claim")
    )
    #expect(reason == .replyBlockedOperationalClaim)
    #expect(reason.title.contains("operational-claim guard"))
    // It must not claim the route or the agent was unavailable.
    #expect(!reason.title.lowercased().contains("route"))
    #expect(!reason.title.lowercased().contains("unreachable"))
    #expect(reason.detail.contains("The route itself was available"))
}

@Test("Legacy agent_unresponsive stays distinct from a blocked reply")
func agentUnresponsiveRemainsDistinct() throws {
    let reason = try #require(OrcaRuntimeTerminalReason(errorCode: " Agent_Unresponsive "))
    #expect(reason == .agentUnresponsive)
    #expect(reason != .replyBlockedOperationalClaim)
}

@Test("Unknown or empty codes never crash and are kept verbatim")
func unknownErrorCodesAreKeptVerbatim() throws {
    #expect(OrcaRuntimeTerminalReason(errorCode: nil) == nil)
    #expect(OrcaRuntimeTerminalReason(errorCode: "   ") == nil)
    let future = try #require(OrcaRuntimeTerminalReason(errorCode: "some_future_code"))
    #expect(future == .other("some_future_code"))
    #expect(future.title == "some_future_code")
}

@Test("reply_blocked lane is recognized without widening the terminal kind enum")
func replyBlockedLaneIsNotATerminalKind() {
    #expect(OrcaRuntimeTerminalReason.isReplyBlocked(lane: "reply_blocked"))
    #expect(OrcaRuntimeTerminalReason.isReplyBlocked(lane: " Reply_Blocked "))
    #expect(!OrcaRuntimeTerminalReason.isReplyBlocked(lane: "frontier_unavailable"))
    #expect(!OrcaRuntimeTerminalReason.isReplyBlocked(lane: nil))
    // terminal_kind is a closed enum in the generated client; the new lane must not
    // be mistaken for one (older builds decode it as an ordinary system message).
    #expect(OrcaRuntimeTerminalKind(lane: "reply_blocked") == nil)
}

@Test("A server terminal outcome carrying the new error_code decodes unchanged")
func terminalOutcomeWithNewErrorCodeDecodes() throws {
    let json = """
    {
      "state": "failed",
      "summary": "Coral replied, but ORCA's operational-claim guard held the reply back.",
      "error_code": "reply_blocked_operational_claim",
      "evidence_refs": [],
      "completed_at": "2026-10-02T01:06:12Z"
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let outcome = try decoder.decode(
        Components.Schemas.ChatRuntimeTerminalOutcomeRead.self,
        from: Data(json.utf8)
    )
    #expect(outcome.terminalKind == nil)
    let terminal = OrcaRuntimeTerminal(generated: outcome)
    #expect(terminal.state == "failed")
    #expect(OrcaRuntimeTerminalReason(errorCode: terminal.errorCode) == .replyBlockedOperationalClaim)
}
