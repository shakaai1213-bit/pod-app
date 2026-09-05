import SwiftUI
import OrcaAPI

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
                Picker("Work view", selection: workModeSelection) {
                    ForEach(ConsoleWorkMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
                if model.workMode == .agentWork {
                    Picker("Agent", selection: workControlAgentSelection) {
                        ForEach(model.agents) { agent in
                            Text(agent.name).tag(agent.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .help("Choose named agent work control")
                }
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
        } else if section == .work, model.workMode == .portfolio {
            WorkPortfolioView()
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

    private var workModeSelection: Binding<ConsoleWorkMode> {
        Binding(
            get: { model.workMode },
            set: { model.selectWorkMode($0) }
        )
    }

    private var groupNames: [String] {
        model.selectedSnapshot.records.reduce(into: []) { groups, record in
            if !groups.contains(record.group) { groups.append(record.group) }
        }
    }
}

private struct WorkPortfolioView: View {
    @Environment(OrcaMacModel.self) private var model

    private var featuredBoards: [OrcaBoardDirectoryItem] {
        Array(model.boards.filter(\.isProduct).prefix(6))
    }

    var body: some View {
        if model.boards.isEmpty, let error = model.boardPlanError {
            ContentUnavailableView(
                "ORCA Board Data Unavailable",
                systemImage: "rectangle.3.group",
                description: Text(error)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.boards.isEmpty, model.isLoadingBoardPlan {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !featuredBoards.isEmpty {
                        productSection
                    }
                    boardPlanSection
                    if let error = model.boardPlanError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Color.orcaCoral)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var productSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MAIN PRODUCTS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(featuredBoards.count) products")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210, maximum: 310), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(featuredBoards) { board in
                    let plan = model.boardPlansByID[board.id]
                    Button { model.selectBoard(board.id) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox")
                                    .foregroundStyle(Color.orcaCyan)
                                Text(board.displayName)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 12) {
                                portfolioMetric(plan?.counts["in_progress"], "working")
                                portfolioMetric(plan?.counts["up_next"], "up next")
                                portfolioMetric(plan?.counts["waiting_on"], "waiting")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(board.id == model.selectedBoardID ? Color.orcaCyan : Color(nsColor: .separatorColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var boardPlanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BOARD PLAN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(model.boardPlan?.boardName ?? "ORCA Work")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                Menu {
                    ForEach(model.boards) { board in
                        Button { model.selectBoard(board.id) } label: {
                            if board.id == model.selectedBoardID {
                                Label(board.displayName, systemImage: "checkmark")
                            } else {
                                Text(board.displayName)
                            }
                        }
                    }
                } label: {
                    Label("All Boards", systemImage: "rectangle.grid.2x2")
                }
                .menuStyle(.borderlessButton)
                Button { Task { await model.refreshBoardPortfolio() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoadingBoardPlan)
                .help("Refresh board plan")
            }

            if let plan = model.boardPlan {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(plan.lanes) { lane in
                            laneView(lane)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(Color.orcaGreen)
                    Text("\(plan.selectionMode.replacingOccurrences(of: "_", with: " ").capitalized) · ORCA")
                    Spacer()
                    Text(plan.computedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if model.isLoadingBoardPlan {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }

    private func laneView(_ lane: OrcaBoardPlanLane) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lane.title.uppercased())
                    .font(.caption.weight(.bold))
                Spacer()
                Text("\(lane.cards.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if lane.cards.isEmpty {
                Text("No work in this lane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                ForEach(lane.cards) { card in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(card.title)
                            .font(.body.weight(.medium))
                            .lineLimit(2)
                        if let subtitle = card.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let warning = card.resolvedIntegrityWarnings.first {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                        HStack {
                            if card.resolvedFacets.isEmpty {
                                Label(card.objectType.capitalized, systemImage: facetIcon(card.objectType))
                            } else {
                                ForEach(["ticket", "task", "agent_run"], id: \.self) { type in
                                    let count = card.resolvedFacets.filter { $0.objectType == type }.count
                                    if count > 0 {
                                        Label("\(count)", systemImage: facetIcon(type))
                                            .help("\(count) \(facetLabel(type, count: count))")
                                    }
                                }
                            }
                            Spacer()
                            Text(card.canonicalState.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                }
            }
        }
        .frame(width: 260, alignment: .top)
    }

    private func facetIcon(_ type: String) -> String {
        switch type {
        case "ticket": return "ticket.fill"
        case "project": return "square.stack.3d.up.fill"
        case "agent_run": return "play.circle.fill"
        default: return "checklist"
        }
    }

    private func facetLabel(_ type: String, count: Int) -> String {
        let label = type == "agent_run" ? "run" : type
        return count == 1 ? label : "\(label)s"
    }

    private func portfolioMetric(_ value: Int?, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value.map(String.init) ?? "-")
                .font(.caption.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
