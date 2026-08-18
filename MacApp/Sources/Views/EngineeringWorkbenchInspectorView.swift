import OrcaAPI
import SwiftUI

struct EngineeringWorkbenchInspectorView: View {
    @Environment(OrcaMacModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "hammer")
                        .foregroundStyle(Color.orcaCyan)
                    Text("Workbench")
                        .font(.headline)
                    Spacer()
                    if let lastUpdatedAt = model.lastUpdatedAt {
                        Text(lastUpdatedAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                hostSection
                ticketSection

                if let operation = model.selectedWorkbenchOperation {
                    operationSection(operation)
                    evidenceSection(operation)
                    approvalSection(operation)
                } else {
                    InspectorSection(title: "Operations") {
                        InspectorValue(
                            label: "Total",
                            value: "\(model.workbenchSession?.counts["total"] ?? 0)"
                        )
                        InspectorValue(
                            label: "Selected pane",
                            value: model.selectedWorkbenchPane.title
                        )
                    }
                }

                if let notice = model.workbenchNotice {
                    InspectorSection(title: "Latest") {
                        Text(notice)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }

                if let error = model.workbenchError {
                    InspectorSection(title: "Attention") {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.orcaCoral)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hostSection: some View {
        InspectorSection(title: "Engineering Host") {
            if let contract = model.workbenchContract {
                InspectorValue(label: "Host", value: contract.host.hostID)
                InspectorValue(label: "State", value: contract.host.state)
                InspectorValue(label: "Lane", value: contract.workerLane)
                InspectorValue(label: "Policy", value: String(contract.policySHA256.prefix(12)))
                Text(contract.host.reason)
                    .font(.caption)
                    .foregroundStyle(contract.host.ready ? Color.orcaGreen : Color.orcaAmber)
                    .textSelection(.enabled)
            } else {
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ticketSection: some View {
        InspectorSection(title: "Ticket") {
            if let ticket = model.selectedWorkbenchTicket {
                Text(ticket.title)
                    .font(.body.weight(.semibold))
                    .textSelection(.enabled)
                InspectorValue(label: "Status", value: ticket.status)
                if let flowState = ticket.flowState {
                    InspectorValue(label: "Flow", value: flowState)
                }
                if let priority = ticket.priority {
                    InspectorValue(label: "Priority", value: priority)
                }
                if let nextAction = ticket.nextAction {
                    Text(nextAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else {
                Text("No ticket selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func operationSection(_ operation: OrcaEngineeringOperation) -> some View {
        InspectorSection(title: "AgentRun") {
            InspectorValue(label: "ID", value: operation.id)
            InspectorValue(label: "Action", value: operation.actionID)
            InspectorValue(label: "Status", value: operation.status)
            InspectorValue(label: "Agent", value: operation.agentSlug)
            InspectorValue(label: "Root", value: operation.rootID)
            InspectorValue(label: "Path", value: operation.relativePath)
            InspectorValue(label: "Trace", value: operation.traceID)
            if let outcome = operation.outcome {
                Text(outcome)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            if let error = operation.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.orcaCoral)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func evidenceSection(_ operation: OrcaEngineeringOperation) -> some View {
        if operation.evidence != nil || operation.artifacts != nil {
            InspectorSection(title: "Evidence") {
                if let evidence = operation.evidence {
                    Text(evidence)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if let artifacts = operation.artifacts,
                   let data = try? JSONEncoder().encode(artifacts),
                   let text = String(data: data, encoding: .utf8) {
                    Text(text)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func approvalSection(_ operation: OrcaEngineeringOperation) -> some View {
        if operation.requiresApproval {
            InspectorSection(title: "Approval") {
                InspectorValue(
                    label: "State",
                    value: operation.approvalStatus ?? "missing"
                )
                if operation.approvalStatus == "pending" {
                    HStack(spacing: 8) {
                        Button {
                            Task { await model.decideWorkbenchApproval(operation: operation, decision: "approved") }
                        } label: {
                            Label("Approve", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.orcaGreen)

                        Button {
                            Task { await model.decideWorkbenchApproval(operation: operation, decision: "rejected") }
                        } label: {
                            Label("Reject", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(model.isSubmittingWorkbench)
                }
            }
        }
    }
}
