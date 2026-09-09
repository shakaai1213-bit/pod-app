import SwiftUI
import OrcaRuntimeContracts

struct RuntimeInspectorView: View {
    @Environment(OrcaMacModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorTitle
                InspectorSection(title: "Connection") {
                    InspectorValue(label: "State", value: model.connectionState.label)
                    InspectorValue(label: "Contract", value: model.contractVersion ?? "-")
                    InspectorValue(
                        label: "Schema",
                        value: model.schemaSHA256.map { String($0.prefix(12)) } ?? "-"
                    )
                }

                InspectorSection(title: "Conversation") {
                    InspectorValue(label: "Agent", value: model.selectedAgent.name)
                    InspectorValue(label: "Lane", value: model.selectedAgent.lane.rawValue)
                    InspectorValue(
                        label: "ID",
                        value: model.selectedConversation.conversationID.map { String($0.prefix(12)) } ?? "-"
                    )
                    InspectorValue(label: "Messages", value: "\(model.selectedMessages.count)")
                }

                if let receipt = model.selectedConversation.latestReceipt {
                    InspectorSection(title: "Latest Turn") {
                        InspectorValue(label: "State", value: receipt.responseState ?? "-")
                        InspectorValue(label: "Lane", value: receipt.lane)
                        InspectorValue(label: "Source", value: receipt.source)
                        InspectorValue(label: "Route", value: receipt.tier ?? receipt.provider ?? "-")
                        InspectorValue(label: "Model", value: receipt.model ?? "-")
                        InspectorValue(label: "Trace", value: String(receipt.traceID.prefix(12)))
                        InspectorValue(
                            label: "Run",
                            value: receipt.computeRunID.map { String($0.prefix(12)) } ?? "-"
                        )
                        InspectorValue(label: "Turn", value: String(receipt.turnID.prefix(12)))
                    }
                }

                if let turn = model.selectedRuntimeTurn {
                    InspectorSection(title: "Flight Recorder") {
                        InspectorValue(label: "State", value: turn.state.rawValue)
                        InspectorValue(
                            label: "Source",
                            value: turn.clientProvenance.sourceSurface.rawValue
                        )
                        InspectorValue(label: "Events", value: "\(turn.events?.count ?? 0)")
                        InspectorValue(label: "Runs", value: workRunCount(turn))
                        InspectorValue(
                            label: "Adapter",
                            value: turn.adapter?.providerId ?? "-"
                        )
                        if let reconciliation = model.selectedRuntimeReconciliation {
                            InspectorValue(
                                label: "Cursor state",
                                value: reconciliation.cursorState.rawValue
                            )
                            InspectorValue(
                                label: "Cursor",
                                value: shortIdentifier(reconciliation.cursor)
                            )
                        }
                        ForEach((turn.events ?? []).suffix(8), id: \.eventId) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: event.eventType.isTerminal ? "checkmark.circle.fill" : "circle.fill")
                                    .font(.system(size: event.eventType.isTerminal ? 10 : 5))
                                    .foregroundStyle(event.eventType.isTerminal ? Color.green : Color.secondary)
                                    .frame(width: 12)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.eventType.rawValue)
                                        .font(.caption.monospaced())
                                    Text("\(event.sequence) · \(event.actorId)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    InspectorSection(title: "Recovery") {
                        InspectorValue(label: "Status", value: turn.recovery.status.rawValue)
                        InspectorValue(
                            label: "Last progress",
                            value: timestamp(turn.recovery.lastProgressAt)
                        )
                        if let reason = turn.recovery.reason {
                            InspectorValue(label: "Reason", value: reason)
                        }
                        if let owner = turn.recovery.retryOwner {
                            InspectorValue(label: "Retry owner", value: owner)
                        }
                        if let action = turn.recovery.recommendedAction {
                            Text(action)
                                .font(.caption)
                                .foregroundStyle(turn.recovery.isStuck ? Color.orange : Color.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    InspectorSection(title: "Client Provenance") {
                        InspectorValue(
                            label: "Version",
                            value: turn.clientProvenance.clientVersion ?? "-"
                        )
                        InspectorValue(
                            label: "Build",
                            value: turn.clientProvenance.clientBuild ?? "-"
                        )
                        InspectorValue(
                            label: "Instance",
                            value: shortIdentifier(turn.clientProvenance.clientInstanceId)
                        )
                        InspectorValue(
                            label: "Device",
                            value: shortIdentifier(turn.clientProvenance.deviceRegistrationRef)
                        )
                        InspectorValue(
                            label: "Ingress",
                            value: shortIdentifier(turn.clientProvenance.ingressEventId)
                        )
                    }

                    InspectorSection(title: "Ordering") {
                        InspectorValue(label: "Authority", value: turn.ordering.authority?.rawValue ?? "-")
                        InspectorValue(
                            label: "Sequence",
                            value: turn.ordering.sequenceSource?.rawValue ?? "-"
                        )
                        InspectorValue(
                            label: "Fallback",
                            value: turn.ordering.fallbackOrder?.rawValue ?? "-"
                        )
                    }

                    if let runs = turn.workRuns, !runs.isEmpty {
                        InspectorSection(title: "Bounded Work") {
                            ForEach(runs.suffix(8), id: \.runId) { run in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: run.isStuck ? "exclamationmark.triangle.fill" : "hammer")
                                        .font(.caption2)
                                        .foregroundStyle(run.isStuck ? Color.orange : Color.secondary)
                                        .frame(width: 12)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(run.runType)
                                            .font(.caption.monospaced())
                                        Text("\(run.status) · \(shortIdentifier(run.runId))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }

                if let memory = model.selectedConversationMemory {
                    InspectorSection(title: "Conversation Memory") {
                        InspectorValue(label: "Revision", value: "\(memory.revision)")
                        InspectorValue(
                            label: "Scope",
                            value: memory.memory.visibility?.rawValue ?? "conversation"
                        )
                        InspectorValue(
                            label: "Decisions",
                            value: "\(memory.memory.decisions?.count ?? 0)"
                        )
                        InspectorValue(
                            label: "Commitments",
                            value: "\(memory.memory.commitments?.filter { $0.status == .active }.count ?? 0)"
                        )
                        InspectorValue(
                            label: "Blockers",
                            value: "\(memory.memory.blockers?.filter { $0.status == .active }.count ?? 0)"
                        )
                        if let summary = memory.memory.activeSummary,
                           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let pending = memory.pendingProposals, !pending.isEmpty {
                            Button {
                                Task { await model.applyLatestMemoryProposal() }
                            } label: {
                                Label(
                                    model.isApplyingMemoryProposal
                                        ? "Applying Review"
                                        : "Apply Reviewed Proposal",
                                    systemImage: "checkmark.shield"
                                )
                            }
                            .disabled(model.isApplyingMemoryProposal)
                            .help("Apply the oldest pending Conversation Memory proposal")
                        }
                    }
                }

                if model.isLoadingRuntimeEvidence {
                    ProgressView("Refreshing runtime evidence")
                        .controlSize(.small)
                }

                if let error = model.runtimeEvidenceError {
                    InspectorSection(title: "Evidence Attention") {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.orcaCoral)
                            .textSelection(.enabled)
                    }
                }

                if let detail = model.connectionDetail {
                    InspectorSection(title: "Attention") {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.orcaCoral)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var inspectorTitle: some View {
        HStack(spacing: 8) {
            ConnectionDot(state: model.connectionState)
            Text("Runtime")
                .font(.headline)
            Spacer()
            if let updated = model.lastUpdatedAt {
                Text(updated, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func workRunCount(_ turn: Components.Schemas.ChatRuntimeTurnRead) -> String {
        let visible = turn.workRuns?.count ?? 0
        let limit = turn.workRunsLimit.map(String.init) ?? "-"
        return turn.workRunsTruncated == true ? "\(visible)/\(limit)+" : "\(visible)/\(limit)"
    }

    private func shortIdentifier(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        guard value.count > 20 else { return value }
        return "\(value.prefix(12))...\(value.suffix(4))"
    }

    private func timestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}

private extension Components.Schemas.ChatRuntimeEventType {
    var isTerminal: Bool {
        self == .turn_completed || self == .turn_failed || self == .turn_cancelled
    }
}
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InspectorValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
