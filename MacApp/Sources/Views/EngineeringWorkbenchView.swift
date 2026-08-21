import OrcaAPI
import SwiftUI

struct EngineeringWorkbenchView: View {
    @Environment(OrcaMacModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            paneBar
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.orcaCyan)
                .frame(width: 34, height: 34)
                .background(Color.orcaCyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text("Workbench")
                    .font(.headline)
                Text(model.selectedWorkbenchTicket?.title ?? "Select an ORCA ticket")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Picker("Agent", selection: agentSelection) {
                ForEach(model.agents) { agent in
                    Text(agent.name).tag(agent.id)
                }
            }
            .labelsHidden()
            .frame(width: 105)
            .help("Named agent")

            Picker("Ticket", selection: ticketSelection) {
                Text("Select ticket").tag(String?.none)
                ForEach(model.workbenchTickets) { ticket in
                    Text(ticket.title).tag(Optional(ticket.id))
                }
            }
            .labelsHidden()
            .frame(minWidth: 190, idealWidth: 250, maxWidth: 320)
            .help("ORCA ticket")

            hostIndicator

            if model.isLoadingWorkbench || model.isSubmittingWorkbench {
                ProgressView()
                    .controlSize(.small)
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
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(Color(nsColor: .windowBackgroundColor))
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
                                    ? Color.orcaCyan
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
                Picker("Workspace", selection: $model.workbenchRootID) {
                    ForEach(model.workbenchContract?.roots ?? []) { root in
                        Text(root.label).tag(root.id)
                    }
                }
                .frame(width: 180)

                if [.workspace, .files, .diff, .terminal].contains(model.selectedWorkbenchPane) {
                    TextField("Relative path", text: $model.workbenchRelativePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(minWidth: 180)
                }

                Spacer()
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
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func actionRow(_ actionIDs: [String]) -> some View {
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
            set: { model.selectWorkbenchAgent($0) }
        )
    }

    private var ticketSelection: Binding<String?> {
        Binding(
            get: { model.selectedWorkbenchTicketID },
            set: { model.selectWorkbenchTicket($0) }
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
