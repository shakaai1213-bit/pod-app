import SwiftUI

struct ArmsTabView: View {
    @State private var viewModel = ArmsViewModel()
    @State private var wakeTarget: ArmTag?

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
                        .padding(.bottom, 90)
                }
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable { await viewModel.loadArms() }
            .task { await viewModel.startPolling() }
            .sheet(item: $wakeTarget) { arm in
                wakeConfirmationSheet(arm)
                    .presentationDetents([.medium])
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
                Text("Arms")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("Codex arm dispatch from live Jarvis tags.")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Button {
                Task { await viewModel.loadArms() }
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
        VStack(spacing: 10) {
            ForEach(viewModel.arms) { arm in
                armCard(arm)
            }
        }
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
                if let directive = arm.directive, !directive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    directiveRow(directive)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField(arm.isFund ? "Manual only" : "Post directive…", text: viewModel.draftBinding(for: arm), axis: .vertical)
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
                    .disabled(arm.isFund)

                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.postDirective(for: arm) }
                    } label: {
                        actionLabel(title: arm.isFund ? "Manual only" : "Post", systemImage: "paperplane.fill", isBusy: viewModel.isBusy(arm))
                    }
                    .buttonStyle(.plain)
                    .disabled(arm.isFund || viewModel.isBusy(arm) || (viewModel.directiveDrafts[arm.name.lowercased()] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        wakeTarget = arm
                    } label: {
                        actionLabel(title: arm.isFund ? "Manual only" : "Wake", systemImage: "bell.badge.fill", isBusy: viewModel.isBusy(arm))
                    }
                    .buttonStyle(.plain)
                    .disabled(arm.isFund || viewModel.isBusy(arm))
                }
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

    private func directiveRow(_ directive: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.accentElectric)
                .frame(width: 58, alignment: .leading)
            Text(directive)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.accentElectric.opacity(0.08))
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

    private func wakeConfirmationSheet(_ arm: ArmTag) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                stateChip(arm)
                Text("Wake \(arm.displayName)?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("It will receive the current Jarvis tag context, including current work, ticket reference, blockers, evidence, quality, and directive.")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    wakeTarget = nil
                    Task { await viewModel.wake(arm) }
                } label: {
                    Label("Dispatch Wake", systemImage: "bell.badge.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(AppColors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    wakeTarget = nil
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(AppColors.backgroundPrimary)
        }
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
                Task { await viewModel.loadArms() }
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
