import SwiftUI

struct ArmsTabView: View {
    @State private var viewModel = ArmsViewModel()
    @State private var selectedFamily: ArmFamily = .maui

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

                    orcaMiniSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    armFamilyPicker
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    armsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 90)
                }
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable { await viewModel.load() }
            .task { await viewModel.startPolling() }
            .confirmationDialog(
                "Confirm arm dispatch",
                isPresented: Binding(
                    get: { viewModel.pendingWakeConfirmation != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.pendingWakeConfirmation = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let confirmation = viewModel.pendingWakeConfirmation {
                    Button(confirmation.action == .greenLight
                           ? "Green Light \(confirmation.arm.displayName)"
                           : "Wake \(confirmation.arm.displayName)") {
                        Task { await viewModel.confirmPendingWake() }
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.pendingWakeConfirmation = nil
                }
            } message: {
                Text(viewModel.pendingWakeConfirmation?.reason ?? "This arm requires confirmation before wake.")
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
                Text("Arms Dispatch")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("Directive, wake, and last-ship control. Agent presence lives on the Agents side of Crew.")
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
            sectionHeader(selectedFamily.title.uppercased(), count: selectedArms.count)
            shipSummaryBanner(viewModel.shipSummaryState(for: selectedFamily))

            VStack(spacing: 10) {
                ForEach(selectedArms) { arm in
                    armCard(arm)
                }
            }
        }
    }

    private var orcaMiniSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("INFRA", count: 1, suffix: "surface")
            orcaMiniCard(viewModel.orcaMiniStatus)
        }
    }

    private var selectedArms: [ArmTag] {
        selectedFamily == .maui ? viewModel.arms : viewModel.chiefArms
    }

    private var armFamilyPicker: some View {
        Picker("Arm family", selection: $selectedFamily) {
            Text("Maui Arms (\(viewModel.arms.count))").tag(ArmFamily.maui)
            Text("Chief Arms (\(viewModel.chiefArms.count))").tag(ArmFamily.chief)
        }
        .pickerStyle(.segmented)
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
                if arm.directive != nil || arm.reviewState != nil {
                    reviewRow(arm)
                }
                if arm.protected, let reason = arm.protectionReason, !reason.isEmpty {
                    protectedRow(reason)
                }
                if let directive = arm.directive, !directive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    directiveRow(directive, arm: arm)
                }
                if arm.needsEngagement {
                    needsEngagementRow(arm)
                }
                if let ops = viewModel.armOps(for: arm), ops.hasEvidence {
                    armOpsLifecycleStrip(ops)
                }
                lastShipRow(arm)
                if viewModel.isShipsExpanded(arm) {
                    shipHistoryRows(for: arm)
                }
                if let ops = viewModel.armOps(for: arm), ops.hasEvidence {
                    armOpsRow(arm, ops: ops)
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

                if arm.canGreenLight {
                    Button {
                        Task { await viewModel.greenLight(arm) }
                    } label: {
                        actionLabel(title: "Green Light", systemImage: "checkmark.seal.fill", isBusy: viewModel.isBusy(arm))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isBusy(arm))
                }

                if arm.canRequestReview {
                    Button {
                        Task { await viewModel.markReadyForReview(arm) }
                    } label: {
                        actionLabel(title: "Ready for \(arm.directiveActor.capitalized) Review", systemImage: "eyes", isBusy: viewModel.isBusy(arm))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isBusy(arm) || arm.reviewState == arm.reviewReadyState)
                }

                Text("Maui directs Maui arms. Chief directs Chief arms. Arms report progress and readiness here; approvals stay with the main agents.")
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

    private func orcaMiniCard(_ status: OrcaMiniStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(status.statusColor)
                    .frame(width: 34, height: 34)
                    .background(status.statusColor.opacity(0.13))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("ORCA Mini")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(status.tagId)
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer(minLength: 6)

                miniStatusChip(status)
            }

            if !status.badges.isEmpty {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(status.badges, id: \.label) { badge in
                        miniBadge(badge)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                miniMetricRow(label: "Disk", value: status.disk)
                miniMetricRow(label: "Containers", value: status.containers)
                miniMetricRow(label: "NFS", value: status.nfs)
                miniMetricRow(label: "NATS", value: status.nats)
                miniMetricRow(label: "Backup", value: status.lastBackup)
                miniMetricRow(label: "Fresh", value: status.freshnessLabel)
                if let source = status.source, !source.isEmpty {
                    miniMetricRow(label: "Source", value: source)
                }
            }
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(status.statusColor.opacity(0.75), lineWidth: 1)
        )
    }

    private func miniStatusChip(_ status: OrcaMiniStatus) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.statusColor)
                .frame(width: 7, height: 7)
            Text(status.statusLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(status.statusColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(status.statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private func miniBadge(_ badge: OrcaMiniBadge) -> some View {
        Text(badge.label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(badge.color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(badge.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func miniMetricRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func shipSummaryBanner(_ state: ArmShipSummaryState) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if state.status == .loading {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(state.color)
                    .frame(width: 18, height: 18)
            } else {
                Circle()
                    .fill(state.color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Ship summary")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(state.color)
                    Text(state.label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(state.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(state.color.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(state.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let source = state.source {
                    Text(source)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(state.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                if arm.proposedByArm {
                    directiveMetaPill("proposed by arm")
                }
                if let intentState = arm.intentState, !intentState.isEmpty {
                    directiveMetaPill(intentState.replacingOccurrences(of: "_", with: " "))
                }
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

    private func needsEngagementRow(_ arm: ArmTag) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.accentWarning)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text("Need engagement")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppColors.accentWarning)
                if let reason = arm.needsEngagementReason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.accentWarning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func reviewRow(_ arm: ArmTag) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "eyes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(arm.reviewStatusColor)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Review")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(arm.reviewStatusColor)
                    Text(arm.reviewStatusLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(arm.reviewStatusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(arm.reviewStatusColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                if let reviewNote = arm.reviewNote, !reviewNote.isEmpty {
                    Text(reviewNote)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let reviewer = arm.reviewReportedBy, !reviewer.isEmpty {
                    Text("by \(reviewer)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(arm.reviewStatusColor.opacity(0.08))
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
            switch viewModel.shipHistoryState(for: arm) {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(AppColors.accentElectric)
                    Text("Loading ship history")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                    Spacer(minLength: 0)
                }
            case .empty:
                shipHistoryMessage("No ship history recorded for this arm.", color: AppColors.textTertiary, isWarning: false)
            case .error(let message):
                shipHistoryMessage(message, color: AppColors.accentWarning, isWarning: true)
                ForEach(viewModel.ships(for: arm)) { ship in
                    shipHistoryItem(ship)
                }
            case .loaded(let ships):
                ForEach(ships) { ship in
                    shipHistoryItem(ship)
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

    private func shipHistoryItem(_ ship: ArmShip) -> some View {
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

    private func shipHistoryMessage(_ message: String, color: Color, isWarning: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "tray")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func armOpsRow(_ arm: ArmTag, ops: ArmOpsSnapshot) -> some View {
        Button {
            viewModel.toggleEvidence(for: arm)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ops.statusColor)
                        .frame(width: 58, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Run evidence")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(ops.statusColor)
                            Text(ops.stateLabel)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(ops.statusColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ops.statusColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Text(ops.latestRun.map { "\($0.compactId) · \($0.statusLabel)" } ?? "Directive state only")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: viewModel.isEvidenceExpanded(arm) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.top, 3)
                }

                if viewModel.isEvidenceExpanded(arm) {
                    armOpsEvidenceDetails(ops)
                }
            }
            .padding(10)
            .background(ops.statusColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func armOpsLifecycleStrip(_ ops: ArmOpsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ops.statusColor)
                    .frame(width: 58, alignment: .leading)
                Text("Hand lifecycle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(ops.statusColor)
                Text(ops.stateLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ops.statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ops.statusColor.opacity(0.12))
                    .clipShape(Capsule())
                Spacer(minLength: 0)
            }

            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                lifecyclePill("parked directive", isActive: ops.directiveStatus != nil || ops.intentState != nil, color: AppColors.accentElectric)
                lifecyclePill("in progress", isActive: ["received", "in_progress", "running", "dispatching"].contains(ops.stateLabelKey), color: AppColors.accentWarning)
                lifecyclePill("blocked / failed", isActive: ["blocked", "failed", "error"].contains(ops.stateLabelKey), color: AppColors.accentDanger)
                lifecyclePill("review ready", isActive: ["review_ready", "ready_for_maui", "ready_for_chief"].contains(ops.stateLabelKey) || ops.reviewState != nil, color: AppColors.accentElectric)
                lifecyclePill("owner reviewed", isActive: ["completed", "done", "reviewed", "owner_reviewed"].contains(ops.stateLabelKey), color: AppColors.accentSuccess)
            }

            Text("Hands report progress here. Maui/Chief review and complete the work.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(ops.statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func lifecyclePill(_ text: String, isActive: Bool, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(isActive ? color : AppColors.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isActive ? color.opacity(0.12) : AppColors.backgroundTertiary.opacity(0.75))
            .clipShape(Capsule())
    }

    private func armOpsEvidenceDetails(_ ops: ArmOpsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let latestRun = ops.latestRun {
                evidenceSubhead("Activation context")
                evidenceMetric(label: "Run", value: latestRun.runId ?? "—")
                evidenceMetric(label: "Arm", value: latestRun.arm ?? ops.name)
                if let owner = latestRun.activationOwner {
                    evidenceMetric(label: "Owner", value: owner)
                }
                if let family = latestRun.activationFamily {
                    evidenceMetric(label: "Family", value: family)
                }
                if let directive = latestRun.directiveSummary {
                    evidenceMetric(label: "Directive", value: directive)
                }
                if let activationPath = latestRun.activationContextPath {
                    evidenceMetric(label: "Context", value: activationPath)
                }
                if let permissions = latestRun.permissionsSummary {
                    evidenceMetric(label: "Perms", value: permissions)
                }

                evidenceSubhead("Run status")
                if let runStatus = latestRun.runStatusStatus {
                    evidenceMetric(label: "Status", value: runStatus.replacingOccurrences(of: "_", with: " "))
                }
                if let runStatusPath = latestRun.runStatusPath {
                    evidenceMetric(label: "Status file", value: runStatusPath)
                }
                evidenceMetric(label: "Thread", value: latestRun.codexThreadId ?? "—")
                evidenceMetric(label: "Events", value: "\(latestRun.eventCount) events · \(latestRun.fileChangeCount) file changes")
                if let completedAt = latestRun.completedAt {
                    evidenceMetric(label: "Done", value: completedAt.formatted(date: .abbreviated, time: .shortened))
                } else if let startedAt = latestRun.startedAt {
                    evidenceMetric(label: "Started", value: startedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let summary = latestRun.summary {
                    evidenceMetric(label: "Summary", value: summary)
                }

                evidenceSubhead("Evidence & report")
                if let evidencePath = latestRun.evidencePath {
                    evidenceMetric(label: "Evidence", value: evidencePath)
                }
                if let reportSummary = latestRun.reportSummary {
                    evidenceMetric(label: "Report", value: reportSummary)
                }
                evidenceList(label: "Findings", values: latestRun.reportFindings)
                evidenceList(label: "Deliver", values: latestRun.reportDeliverables)
                evidenceList(label: "Blocked", values: latestRun.reportBlockedOn)
                if let reportPath = latestRun.reportPath {
                    evidenceMetric(label: "Report file", value: reportPath)
                }
                if let eventsPath = latestRun.eventsPath {
                    evidenceMetric(label: "Events", value: eventsPath)
                }
            } else {
                evidenceMetric(label: "Run", value: "No hand run indexed yet")
            }

            if let reviewState = ops.reviewState, !reviewState.isEmpty {
                evidenceMetric(label: "Review", value: reviewState.replacingOccurrences(of: "_", with: " "))
            }
            if let reviewer = ops.reviewReportedBy, !reviewer.isEmpty {
                evidenceMetric(label: "By", value: reviewer)
            }
            if let generatedAt = ops.generatedAt {
                evidenceMetric(label: "Read", value: generatedAt.formatted(date: .omitted, time: .shortened))
            }
        }
        .padding(.top, 2)
    }

    private func evidenceSubhead(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(AppColors.textTertiary)
            .padding(.top, 4)
    }

    private func evidenceMetric(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func evidenceList(label: String, values: [String]) -> some View {
        if !values.isEmpty {
            evidenceMetric(label: label, value: values.prefix(4).joined(separator: "\n"))
        }
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
        case "architecture": return "map"
        case "pod": return "iphone"
        case "orca": return "server.rack"
        case "compute": return "cpu"
        case "memory": return "brain.head.profile"
        case "schoolhouse": return "building.columns"
        case "jarvis": return "waveform.path.ecg"
        case "fund": return "lock.shield"
        case "nats": return "dot.radiowaves.left.and.right"
        case "fish": return "fish"
        case "chief-trading": return "chart.line.uptrend.xyaxis"
        case "chief-fund": return "lock.shield"
        case "chief-mac-infra": return "desktopcomputer"
        case "chief-data": return "externaldrive.connected.to.line.below"
        case "chief-predictions": return "waveform.path.ecg.rectangle"
        case "chief-research": return "magnifyingglass"
        case "chief-ml": return "point.3.connected.trianglepath.dotted"
        case "chief-algos": return "curlybraces.square"
        default: return "person.crop.circle"
        }
    }
}
