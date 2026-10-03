import OrcaAPI
import SwiftUI
import OrcaDesign

struct EngineeringWorkbenchView: View {
    @Environment(OrcaMacModel.self) private var model
    @State private var ticketQuery = ""
    @State private var showingTicketSearch = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            paneBar
            Divider()
            content
        }
        .background(OrcaPalette.backgroundPrimary)
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "hammer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OrcaPalette.accentElectric)
                    .frame(width: 34, height: 34)
                    .background(OrcaPalette.accentElectric.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Workbench")
                        .font(.headline)
                    Text(model.selectedWorkbenchTicket?.title ?? "Choose a ticket for one agent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)
                hostIndicator

                if model.isLoadingWorkbench || model.isSubmittingWorkbench {
                    ProgressView().controlSize(.small)
                }

                Button {
                    Task { await model.refreshWorkbench() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!model.connectionState.isReady || model.isLoadingWorkbench)
                .help("Refresh Workbench")
            }

            HStack(spacing: 10) {
                Text("Agent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Agent", selection: agentSelection) {
                    Text("View All Agents in Work ↗").tag("all_agents")
                    Divider()
                    ForEach(model.agents) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .help("Workbench actions use one agent. All Agents opens the separate read-only Work view.")

                TextField("Search \(selectedAgentName)'s tickets by title or ID", text: $ticketQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search \(selectedAgentName)'s Workbench tickets")
                    .onSubmit { showingTicketSearch = true }

                Button("Results (\(matchingWorkbenchTickets.count))") {
                    showingTicketSearch = true
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showingTicketSearch, arrowEdge: .bottom) {
                    ticketSearchPopover
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(OrcaPalette.backgroundSecondary)
    }

    private var selectedAgentName: String {
        model.agents.first(where: { $0.id == model.selectedAgentID })?.name ?? "this agent"
    }

    private var matchingWorkbenchTickets: [WorkbenchTicketSummary] {
        let query = ticketQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.workbenchTickets }
        return model.workbenchTickets.filter { ticket in
            ticket.title.localizedCaseInsensitiveContains(query)
                || ticket.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var ticketSearchPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(selectedAgentName)'s Workbench tickets")
                .font(.headline)
            Text("This list is scoped to the selected agent. Changing agents keeps your search.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.selectedWorkbenchTicketID != nil {
                Button {
                    model.selectWorkbenchTicket(nil)
                    showingTicketSearch = false
                } label: {
                    Label("Clear ticket selection", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Workbench ticket selection")
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if matchingWorkbenchTickets.isEmpty {
                        if model.isLoadingWorkbench {
                            ProgressView("Loading \(selectedAgentName)'s tickets…")
                                .padding(8)
                        } else {
                            Text(model.workbenchTickets.isEmpty
                                 ? "No Workbench tickets loaded for \(selectedAgentName)."
                                 : "No matching tickets for \(selectedAgentName).")
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                    } else {
                        ForEach(matchingWorkbenchTickets) { ticket in
                            Button {
                                model.selectWorkbenchTicket(ticket.id)
                                showingTicketSearch = false
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: model.selectedWorkbenchTicketID == ticket.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(OrcaPalette.accentElectric)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(ticket.title)
                                            .font(.subheadline.weight(.medium))
                                        Text("\(String(ticket.id.prefix(8))) · \(ticket.status.replacingOccurrences(of: "_", with: " "))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 420, height: 380)
    }

    private var paneBar: some View {
        HStack(spacing: 0) {
            ForEach(WorkbenchPane.allCases) { pane in
                Button {
                    model.selectedWorkbenchPane = pane
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Text(pane.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Rectangle()
                            .fill(
                                model.selectedWorkbenchPane == pane
                                    ? OrcaPalette.accentElectric
                                    : Color.clear
                            )
                            .frame(height: 2)
                    }
                    .foregroundStyle(
                        model.selectedWorkbenchPane == pane
                            ? Color.primary
                            : Color.secondary
                    )
                    .frame(
                        minWidth: WorkbenchPane.minimumControlWidth,
                        maxWidth: .infinity
                    )
                    .padding(.horizontal, 2)
                    .padding(.top, 6)
                }
                .buttonStyle(.plain)
                .help(pane.title)
                .accessibilityLabel(pane.title)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(OrcaPalette.backgroundSecondary)
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
        } else if model.workbenchContract == nil, let error = model.workbenchError {
            ContentUnavailableView(
                "Workbench Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.selectedWorkbenchTicketID == nil {
            ContentUnavailableView("No Ticket Selected", systemImage: "ticket")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                controls
                Divider()
                operationList
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Project folder", selection: $model.workbenchRootID) {
                    ForEach(model.workbenchContract?.roots ?? []) { root in
                        Text(root.label).tag(root.id)
                    }
                }
                .frame(width: 180)
                .help("Choose where file, diff, test, and terminal actions run. This does not filter tickets.")

                if [.workspace, .files, .diff, .terminal].contains(model.selectedWorkbenchPane) {
                    TextField("Relative path", text: $model.workbenchRelativePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(minWidth: 180)
                }

                Spacer()
            }

            if let root = model.selectedWorkbenchRoot {
                Text("Project folder: \(root.description)\nTicket search is independent of this folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            switch model.selectedWorkbenchPane {
            case .workspace:
                actionRow(["workspace.snapshot", "git.status"])
            case .files:
                actionRow(["file.read"])
            case .diff:
                actionRow(["git.diff"])
                TextEditor(text: $model.workbenchPatchDraft)
                    .font(.caption.monospaced())
                    .frame(minHeight: 82, maxHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(OrcaPalette.border, lineWidth: 1)
                    )
                actionRow(["patch.draft"])
            case .tests:
                actionRow(["test.backend", "test.swift-package", "test.pod", "test.console"])
            case .terminal:
                HStack(spacing: 8) {
                    TextField("Search query", text: $model.workbenchSearchQuery)
                        .textFieldStyle(.roundedBorder)
                    actionRow(["search.rg"])
                }
            case .workers, .evidence, .approvals:
                EmptyView()
            }
        }
        .padding(14)
        .background(OrcaPalette.backgroundSecondary)
    }

    private func actionRow(_ actionIDs: [String]) -> some View {
        let actions = actionIDs.compactMap { id in
            model.workbenchContract?.actions.first(where: { $0.id == id })
        }
        let disabledReasons = actions
            .filter { !canRun($0) }
            .map { actionHelp($0) }
            .filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ForEach(actionIDs, id: \.self) { actionID in
                    if let action = model.workbenchContract?.actions.first(where: { $0.id == actionID }) {
                        Button {
                            Task { await model.submitWorkbenchAction(actionID) }
                        } label: {
                            Label(action.label, systemImage: actionSymbol(actionID))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!canRun(action))
                        .help(actionHelp(action))
                    }
                }
                Spacer(minLength: 0)
            }
            if let reason = disabledReasons.first {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(Color.orcaAmber)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var operationList: some View {
        List(selection: operationSelection) {
            ForEach(filteredOperations) { operation in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: actionSymbol(operation.actionID))
                        .foregroundStyle(statusColor(operation.status))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(actionLabel(operation.actionID))
                            .font(.body.weight(.medium))
                        Text("\(operation.rootID)  \(operation.relativePath)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Text(operation.status.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(statusColor(operation.status))
                }
                .padding(.vertical, 3)
                .tag(operation.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if filteredOperations.isEmpty && !model.isLoadingWorkbench {
                ContentUnavailableView(
                    "No \(model.selectedWorkbenchPane.title) Operations",
                    systemImage: model.selectedWorkbenchPane.symbol
                )
            }
        }
    }

    private var filteredOperations: [OrcaEngineeringOperation] {
        let operations = model.workbenchSession?.operations ?? []
        switch model.selectedWorkbenchPane {
        case .workspace:
            return operations.filter { ["workspace.snapshot", "git.status"].contains($0.actionID) }
        case .files:
            return operations.filter { $0.actionID == "file.read" }
        case .diff:
            return operations.filter { ["git.diff", "patch.draft", "patch.apply"].contains($0.actionID) }
        case .tests:
            return operations.filter { $0.actionKind == "test" }
        case .terminal:
            return operations.filter { $0.actionKind == "terminal" }
        case .workers:
            return operations.filter { $0.actionID != "patch.draft" }
        case .evidence:
            return operations.filter { $0.evidence != nil || $0.artifacts != nil }
        case .approvals:
            return operations.filter { $0.requiresApproval }
        }
    }

    private var agentSelection: Binding<String> {
        Binding(
            get: { model.selectedAgentID },
            set: { selection in
                if selection == "all_agents" {
                    model.selectWorkMode(.team)
                } else {
                    model.selectWorkbenchAgent(selection)
                }
            }
        )
    }

    private var operationSelection: Binding<String?> {
        Binding(
            get: { model.selectedWorkbenchOperationID },
            set: { model.selectWorkbenchOperation($0) }
        )
    }

    private var hostIndicator: some View {
        let host = model.workbenchContract?.host
        return HStack(spacing: 5) {
            Image(systemName: host?.ready == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(host?.ready == true ? "Host ready" : "Host staged")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(host?.ready == true ? Color.orcaGreen : Color.orcaAmber)
        .help(host?.reason ?? "Engineering host posture unavailable")
    }

    private func canRun(_ action: OrcaEngineeringAction) -> Bool {
        guard action.available,
              action.allowedRootIDs.contains(model.workbenchRootID),
              !model.isSubmittingWorkbench else { return false }
        return action.id == "patch.draft" || model.workbenchContract?.host.ready == true
    }

    private func actionHelp(_ action: OrcaEngineeringAction) -> String {
        if !action.available { return action.blockedReasons.joined(separator: " ") }
        if !action.allowedRootIDs.contains(model.workbenchRootID) {
            return "Unavailable for the selected workspace root."
        }
        if action.id != "patch.draft", model.workbenchContract?.host.ready != true {
            return model.workbenchContract?.host.reason ?? "Engineering host is not attested."
        }
        return action.label
    }

    private func actionLabel(_ id: String) -> String {
        model.workbenchContract?.actions.first(where: { $0.id == id })?.label ?? id
    }

    private func actionSymbol(_ id: String) -> String {
        switch id {
        case "workspace.snapshot": return "folder.badge.gearshape"
        case "file.read": return "doc.text"
        case "git.status": return "point.3.connected.trianglepath.dotted"
        case "git.diff": return "arrow.left.arrow.right"
        case "search.rg": return "magnifyingglass"
        case "patch.draft": return "doc.badge.plus"
        case "patch.apply": return "square.and.arrow.down"
        default: return id.hasPrefix("test.") ? "checkmark.circle" : "gearshape.2"
        }
    }
}
