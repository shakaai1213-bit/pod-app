import Foundation

/// The precise reason ORCA recorded for a failed turn.
///
/// `error_code` on the runtime terminal outcome and `lane` on a chat message are
/// free strings in the shipped contract, so this type never fails on an unknown
/// value: an unrecognized code is preserved as `.other` and shown verbatim rather
/// than being collapsed into "agent unreachable". `terminal_kind` is a closed enum
/// in the generated client and is intentionally not widened for this reason.
public enum OrcaRuntimeTerminalReason: Equatable, Sendable {
    /// The named agent answered, but ORCA's operational-claim guard refused to
    /// deliver the reply. The route was healthy.
    case replyBlockedOperationalClaim
    /// ORCA never received a reply from the named agent.
    case agentUnresponsive
    /// A code this build does not recognize, kept verbatim.
    case other(String)

    public static let replyBlockedLane = "reply_blocked"

    public init?(errorCode: String?) {
        guard let raw = errorCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "reply_blocked_operational_claim":
            self = .replyBlockedOperationalClaim
        case "agent_unresponsive":
            self = .agentUnresponsive
        default:
            self = .other(raw)
        }
    }

    /// True when a chat message lane marks a reply ORCA withheld.
    public static func isReplyBlocked(lane: String?) -> Bool {
        lane?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == replyBlockedLane
    }

    /// Short label for the flight recorder and message chrome.
    public var title: String {
        switch self {
        case .replyBlockedOperationalClaim:
            return "Reply blocked by ORCA's operational-claim guard"
        case .agentUnresponsive:
            return "No reply from the agent"
        case .other(let code):
            return code
        }
    }

    /// One sentence that never claims more than ORCA recorded.
    public var detail: String {
        switch self {
        case .replyBlockedOperationalClaim:
            return "The agent replied, but ORCA withheld the reply because it was classified as a live system-status claim without a verified work-result contract. The route itself was available."
        case .agentUnresponsive:
            return "ORCA did not receive a reply from the named agent before the turn timed out."
        case .other(let code):
            return "ORCA recorded the terminal reason \(code)."
        }
    }
}
