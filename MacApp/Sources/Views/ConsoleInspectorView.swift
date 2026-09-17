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
                        ApprovalDecisionSection(recordID: record.id, approval: approval)
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
}

private struct ApprovalDecisionSection: View {
    @Environment(OrcaMacModel.self) private var model
    let recordID: String
    let approval: ConsoleApprovalRecord

    @State private var rejectionReason = ""

    var body: some View {
        InspectorSection(title: "Decision") {
            if approval.canResolve {
                TextField("Rejection reason (required to reject)", text: $rejectionReason)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
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
