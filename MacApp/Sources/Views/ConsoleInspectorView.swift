import SwiftUI

struct ConsoleInspectorView: View {
    @Environment(OrcaMacModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: model.selectedSection.symbol)
                        .foregroundStyle(Color.orcaCyan)
                    Text("Inspector")
                        .font(.headline)
                    Spacer()
                    if model.selectedSnapshot.updatedAt != .distantPast {
                        Text(model.selectedSnapshot.updatedAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let record = model.selectedRecord {
                    InspectorSection(title: record.group) {
                        Text(record.title)
                            .font(.body.weight(.semibold))
                            .textSelection(.enabled)
                        if let subtitle = record.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let status = record.status {
                            InspectorValue(label: "Status", value: status)
                        }
                    }

                    if !record.fields.isEmpty {
                        InspectorSection(title: "Details") {
                            ForEach(record.fields) { field in
                                InspectorValue(label: field.label, value: field.value)
                            }
                        }
                    }

                    if let approval = record.approval {
                        ApprovalWhySection(approval: approval)
                        ApprovalDecisionSection(recordID: record.id, approval: approval)
                    }

                    if let ticket = record.ticket {
                        InspectorSection(title: "Ticket") {
                            InspectorValue(label: "ID", value: ticket.id)
                            InspectorValue(label: "Summary", value: ticket.summary)
                            if let status = ticket.status {
                                InspectorValue(label: "Status", value: status)
                            }
                            if let agent = ticket.agentSlug {
                                InspectorValue(label: "Agent", value: agent)
                            }
                            if let blockedOn = ticket.blockedOn {
                                InspectorValue(label: "Blocked On", value: blockedOn)
                            }
                            if let approvalState = ticket.approvalState {
                                InspectorValue(label: "Approval State", value: approvalState)
                            }
                            if let url = ticketURL(for: ticket.endpoint) {
                                Link("Open ticket endpoint", destination: url)
                            } else {
                                InspectorValue(label: "Endpoint", value: ticket.endpoint)
                            }
                        }
                        OpenTicketChatHook(ticketID: ticket.id)
                    }
                } else {
                    InspectorSection(title: "Section") {
                        InspectorValue(label: "View", value: model.selectedSection.title)
                        InspectorValue(label: "Records", value: "\(model.selectedSnapshot.records.count)")
                        InspectorValue(label: "Sources", value: "\(model.selectedSnapshot.sources.count)")
                    }
                }

                if !model.selectedSnapshot.sources.isEmpty {
                    InspectorSection(title: "ORCA Sources") {
                        ForEach(model.selectedSnapshot.sources, id: \.self) { source in
                            Text(source)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                if let error = model.sectionError {
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

    private func ticketURL(for endpoint: String) -> URL? {
        guard endpoint.hasPrefix("/api/v1/tickets/"),
              let origin = OrcaMacModel.normalizedEndpoint(model.serverAddress),
              let url = URL(string: endpoint, relativeTo: origin)?.absoluteURL else { return nil }
        return url
    }
}

/// Named integration point for SPEC-TICKET-SCOPED-CHAT-2026-09-19.
/// This section intentionally does not open or create ticket chat.
private struct OpenTicketChatHook: View {
    let ticketID: String

    var body: some View {
        EmptyView()
    }
}

private struct ApprovalWhySection: View {
    let approval: ConsoleApprovalRecord

    var body: some View {
        if let reason = approval.reason {
            InspectorSection(title: "Why") {
                Text(reason)
                    .font(.caption)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let gate = approval.approvalGate {
                    InspectorValue(label: "Gate", value: gate)
                }
                if let requestedBy = approval.requestedBy {
                    InspectorValue(label: "Requested by", value: requestedBy)
                }
            }
        } else if approval.isProtectedTicketContext {
            InspectorSection(title: "Why") {
                Text("Protected ticket — details withheld")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ApprovalDecisionSection: View {
    @Environment(OrcaMacModel.self) private var model
    let recordID: String
    let approval: ConsoleApprovalRecord

    @State private var rejectionReason = ""

    var body: some View {
        InspectorSection(title: "Decision") {
            if approval.showsDecisionControl {
                Button {
                    Task {
                        await model.decideTicketApproval(
                            recordID: recordID,
                            decision: .approved,
                            reason: "Approved from ORCA Console."
                        )
                    }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.orcaGreen)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Reject")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orcaCoral)
                    TextField("Rejection reason (required)", text: $rejectionReason)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Rejection reason")
                    Button {
                        Task {
                            await model.decideTicketApproval(
                                recordID: recordID,
                                decision: .rejected,
                                reason: rejectionReason
                            )
                        }
                    } label: {
                        Label("Reject", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.orcaCoral)
                    .disabled(rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .disabled(model.isDecidingApproval)
            } else if let reason = approval.blockReason {
                Label(reason.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.orcaAmber)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.isDecidingApproval {
                ProgressView()
                    .controlSize(.small)
            }
            if let error = model.approvalError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.orcaCoral)
                    .textSelection(.enabled)
            }
            if let notice = model.approvalNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(Color.orcaGreen)
                    .textSelection(.enabled)
            }
        }
    }
}
