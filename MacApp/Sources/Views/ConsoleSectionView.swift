import SwiftUI

struct ConsoleSectionView: View {
    @Environment(OrcaMacModel.self) private var model
    let section: ConsoleSection

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(section == .fund ? Color.orcaGreen : Color.orcaCyan)
                .frame(width: 34, height: 34)
                .background(
                    (section == .fund ? Color.orcaGreen : Color.orcaCyan).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(section.title)
                        .font(.headline)
                    if section.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if section == .work {
                Picker("Agent", selection: workControlAgentSelection) {
                    ForEach(model.agents) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .help("Choose named agent work control")
            }
            if model.isLoadingSection {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await model.refreshSelectedSection() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!model.connectionState.isReady || model.isLoadingSection)
            .help("Refresh \(section.title)")
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if !model.connectionState.isReady {
            ContentUnavailableView(
                model.connectionState.unavailableTitle,
                systemImage: model.connectionState.unavailableSymbol,
                description: model.connectionDetail.map(Text.init)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.sectionError, model.selectedSnapshot.records.isEmpty {
            ContentUnavailableView(
                "ORCA Data Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if !model.selectedSnapshot.metrics.isEmpty {
                    metrics
                    Divider()
                }
                records
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130, maximum: 210), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(model.selectedSnapshot.metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if let status = metric.status {
                        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2)
                            .foregroundStyle(statusColor(status))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var records: some View {
        List(selection: recordSelection) {
            ForEach(groupNames, id: \.self) { group in
                Section(group) {
                    ForEach(model.selectedSnapshot.records.filter { $0.group == group }) { record in
                        ConsoleRecordRow(record: record)
                            .tag(record.id)
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if model.selectedSnapshot.records.isEmpty && !model.isLoadingSection {
                ContentUnavailableView(
                    "No \(section.title) Records",
                    systemImage: section.symbol
                )
            }
        }
    }

    private var recordSelection: Binding<String?> {
        Binding(
            get: { model.selectedRecordID },
            set: { model.selectRecord($0) }
        )
    }

    private var workControlAgentSelection: Binding<String> {
        Binding(
            get: { model.selectedAgentID },
            set: { model.selectWorkControlAgent($0) }
        )
    }

    private var groupNames: [String] {
        model.selectedSnapshot.records.reduce(into: []) { groups, record in
            if !groups.contains(record.group) { groups.append(record.group) }
        }
    }
}

private struct ConsoleRecordRow: View {
    let record: ConsoleRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let subtitle = record.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            if let status = record.status {
                Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor(status))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

func statusColor(_ raw: String) -> Color {
    let value = raw.lowercased()
    if value.contains("ok") || value.contains("ready") || value.contains("complete") || value.contains("running") {
        return .orcaGreen
    }
    if value.contains("attention") || value.contains("blocked") || value.contains("failed") || value.contains("offline") {
        return .orcaCoral
    }
    if value.contains("pending") || value.contains("review") || value.contains("claim") {
        return .orcaAmber
    }
    return .secondary
}
