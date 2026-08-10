import SwiftUI

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
