import SwiftUI

struct ArmsTabView: View {
    @State private var viewModel = ArmsViewModel()
    @State private var selectedAgent: Agent?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 16)

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    armsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)

                    teamSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 90)
                }
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable { await viewModel.load() }
            .task { await viewModel.startPolling() }
            .sheet(item: $selectedAgent) { agent in
                AgentDetailSheet(agent: agent)
            }
            .overlay(alignment: .bottom) {
                if let toast = viewModel.toast {
                    toastView(toast)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast.message) {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if viewModel.toast == toast {
                                    viewModel.toast = nil
                                }
                            }
                        }
                }
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Arms + Team")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("Codex arm dispatch and live crew focus.")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Button {
                Task { await viewModel.load() }
            } label: {
                Image(systemName: viewModel.isLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                    .frame(width: 36, height: 36)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Refresh Arms")
        }
    }

    private var armsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("ARMS", count: viewModel.arms.count)

            VStack(spacing: 10) {
                ForEach(viewModel.arms) { arm in
                    armCard(arm)
                }
            }
        }
    }

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("TEAM", count: viewModel.agents.count, suffix: "active")

            VStack(spacing: 0) {
                if viewModel.agents.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.sequence")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary)
                        Text("No active team agents available.")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textTertiary)
                        Spacer()
                    }
                    .padding(14)
                } else {
                    ForEach(Array(viewModel.agents.enumerated()), id: \.element.id) { idx, agent in
                        VStack(spacing: 0) {
                            if idx > 0 {
                                Divider()
                                    .background(AppColors.border)
                                    .padding(.leading, 56)
                            }
                            agentRow(agent)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedAgent = agent.agent
                                }
                        }
                    }
                }
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
        }
    }

    private func sectionHeader(_ title: String, count: Int, suffix: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .kerning(0.5)
            Text("·")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
            Text(suffix.map { "\(count) \($0)" } ?? "\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.accentElectric)
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func armCard(_ arm: ArmTag) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon(for: arm))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(arm.qualityColor)
                    .frame(width: 34, height: 34)
                    .background(arm.qualityColor.opacity(0.13))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(arm.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(arm.owner.map { "Owner: \($0)" } ?? "Owner: maui")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer(minLength: 6)

                stateChip(arm)
            }

            VStack(alignment: .leading, spacing: 8) {
                valueRow(label: "Current", value: arm.currentWork)
                valueRow(label: "Ticket", value: arm.ticketRef ?? "—")
                valueRow(label: "Blocked", value: arm.blockedOn ?? "—")
                valueRow(label: "Evidence", value: arm.evidenceRef ?? "—")
                valueRow(label: "Fresh", value: arm.freshnessLabel)
                valueRow(label: "Route", value: arm.routeSummary)
                valueRow(label: "Wake", value: arm.wakeSummary)
                valueRow(label: "Source", value: arm.sourceSummary)
                if arm.directive != nil || arm.directiveStatus != nil {
                    valueRow(label: "Directive", value: arm.directiveStatusLabel)
                }
                if arm.protected, let reason = arm.protectionReason, !reason.isEmpty {
                    protectedRow(reason)
                }
                if let directive = arm.directive, !directive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    directiveRow(directive, arm: arm)
                }
                lastShipRow(arm)
                if viewModel.isShipsExpanded(arm) {
                    shipHistoryRows(for: arm)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField(arm.directivePlaceholder, text: viewModel.draftBinding(for: arm), axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(10)
                    .background(AppColors.backgroundPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(AppColors.border, lineWidth: 0.5)
                    )
                    .disabled(!arm.canPostDirective)

                Button {
                    Task { await viewModel.postDirective(for: arm) }
                } label: {
                    actionLabel(title: arm.canPostDirective ? "Post Directive" : "Manual only", systemImage: "paperplane.fill", isBusy: viewModel.isBusy(arm))
                }
                .buttonStyle(.plain)
                .disabled(!arm.canPostDirective || viewModel.isBusy(arm) || (viewModel.directiveDrafts[arm.name.lowercased()] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("No live wake is sent here. Arms read this tag on activation and report status back to ORCA.")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(arm.qualityColor.opacity(0.75), lineWidth: 1)
        )
    }

    private func stateChip(_ arm: ArmTag) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(arm.stateColor)
                .frame(width: 7, height: 7)
            Text(arm.stateLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(arm.stateColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(arm.stateColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private func valueRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func directiveRow(_ directive: String, arm: ArmTag) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: arm.directiveStatus?.lowercased() == "completed" ? "checkmark.seal.fill" : "text.badge.checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(arm.directiveStatusColor)
                Text("OPC DIRECTIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                Text(arm.directiveStatusLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(arm.directiveStatusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(arm.directiveStatusColor.opacity(0.12))
                    .clipShape(Capsule())
                Spacer(minLength: 0)
            }

            Text(directive)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                if let postedBy = arm.directivePostedBy, !postedBy.isEmpty {
                    directiveMetaPill("by \(postedBy)")
                }
                if let doneAt = arm.directiveDoneAt {
                    directiveMetaPill("done \(doneAt.formatted(date: .abbreviated, time: .shortened))")
                }
                if let traceId = arm.directiveTraceId, !traceId.isEmpty {
                    directiveMetaPill(String(traceId.prefix(16)))
                }
            }
        }
        .padding(10)
        .background(arm.directiveStatusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func directiveMetaPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(AppColors.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.backgroundTertiary.opacity(0.75))
            .clipShape(Capsule())
    }

    private func lastShipRow(_ arm: ArmTag) -> some View {
        Button {
            Task { await viewModel.toggleShips(for: arm) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(arm.lastShip?.reviewColor ?? AppColors.textTertiary)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                    .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Last shipped: \(arm.lastShipLabel)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let lastShip = arm.lastShip {
                        Text("\(lastShip.area) · \(lastShip.gate) · \(lastShip.sha) · \(lastShip.reviewLabel)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(lastShip.reviewColor)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: viewModel.isShipsExpanded(arm) ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.top, 3)
            }
            .padding(10)
            .background((arm.lastShip?.reviewColor ?? AppColors.textTertiary).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func shipHistoryRows(for arm: ArmTag) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.ships(for: arm)) { ship in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(ship.reviewColor)
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ship.subject)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(ship.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(ship.area) · \(ship.gate) · \(ship.sha) · \(ship.reviewLabel)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }

    private func protectedRow(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.accentWarning)
                .frame(width: 58, alignment: .leading)
            Text(reason)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.accentWarning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func actionLabel(title: String, systemImage: String, isBusy: Bool) -> some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(title == "Manual only" ? AppColors.textTertiary : Color.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(title == "Manual only" ? AppColors.backgroundTertiary : AppColors.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func agentRow(_ agent: AgentSummary) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hexString: agent.avatarColor).opacity(0.18))
                    .frame(width: 28, height: 28)
                Circle()
                    .strokeBorder(Color(hexString: agent.avatarColor).opacity(0.42), lineWidth: 0.75)
                    .frame(width: 28, height: 28)
                Text(agent.glyph)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    Circle()
                        .fill(agent.statusColor)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Status \(agent.status.displayName)")

                    if !agent.natsLaneOk {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppColors.accentWarning)
                    }
                }

                Text(agent.macLabel)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer(minLength: 6)

            Text(agent.currentFocus ?? "No focus set")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 150, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    private func toastView(_ toast: ArmsToast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(toast.isError ? .white : AppColors.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(toast.isError ? AppColors.accentDanger : AppColors.backgroundTertiary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppColors.border, lineWidth: 0.5))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentWarning)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Button("Retry") {
                Task { await viewModel.load() }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppColors.accentElectric)
        }
        .padding(12)
        .background(AppColors.accentWarning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppColors.accentWarning.opacity(0.24), lineWidth: 0.5)
        )
    }

    private func icon(for arm: ArmTag) -> String {
        switch arm.name.lowercased() {
        case "pod": return "iphone"
        case "orca": return "server.rack"
        case "compute": return "cpu"
        case "memory": return "brain.head.profile"
        case "schoolhouse": return "building.columns"
        case "jarvis": return "waveform.path.ecg"
        case "fund": return "lock.shield"
        case "nats": return "dot.radiowaves.left.and.right"
        default: return "person.crop.circle"
        }
    }
}
