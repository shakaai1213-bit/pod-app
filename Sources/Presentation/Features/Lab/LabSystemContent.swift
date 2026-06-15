import SwiftUI

// System surface — moved from LabView per SPEC-POD-INFORMATION-ARCHITECTURE-2026-06-14 reorg.
// Stack, Architecture, and Retired sections embedded in RuntimeView's "System" segment.
struct LabSystemContent: View {

    @State private var catalogModel = LabCatalogModel()
    @State private var architectureModel = ArchitectureDiagramModel()
    @State private var natsHealthModel = LabNATSHealthModel()
    @State private var stackExpanded = true
    @State private var retiredExpanded = false
    @State private var showingArchitectureSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stackSection
            architectureRegistrySection
            architectureSection
            retiredSection
        }
        .task {
            await catalogModel.load()
            await architectureModel.load()
            await natsHealthModel.load()
        }
        .refreshable {
            await catalogModel.load(force: true)
            await architectureModel.load(force: true)
            await natsHealthModel.load()
        }
        .fullScreenCover(isPresented: $showingArchitectureSheet) {
            ArchitectureDiagramSheet(markdown: architectureModel.markdown)
        }
    }

    // MARK: - Architecture sections

    private var architectureRegistrySection: some View {
        sectionCard {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ARCHITECTURE REGISTRY")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Subsystem truth contracts")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.textTertiary)
                }
                Spacer()
                Text("STAGED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
            }
        } body: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                        .frame(width: 28, height: 28)
                        .background(AppColors.accentElectric.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Boards show where work belongs. The registry will show how each subsystem works.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Source: ORCA-ARCHITECTURE-OWNERSHIP-REGISTRY-2026-05-26.md. Read-only until ORCA exposes a doc-registry/wiki mirror suitable for structured rows.")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var architectureSection: some View {
        sectionCard {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ARCHITECTURE")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Canonical stack map")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.textTertiary)
                }
                Spacer()
                if architectureModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                } else {
                    HStack(spacing: 8) {
                        Text(architectureModel.sourceLabel)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.accentElectric)
                    }
                }
            }
        } body: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                        .frame(width: 28, height: 28)
                        .background(AppColors.accentElectric.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open full architecture map")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)
                        Text("Mermaid source · zoom and scroll")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(10)
                .background(AppColors.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border, lineWidth: 0.5)
                )

                if let error = architectureModel.error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                showingArchitectureSheet = true
            }
        }
    }

    // MARK: - Stack section

    private var stackSection: some View {
        let stack = catalogModel.stack
        return sectionCard {
            sectionHeader(title: "STACK", count: stack.count, expanded: stackExpanded, rightLabel: natsHealthModel.badgeLabel) {
                Task { await natsHealthModel.load() }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { stackExpanded.toggle() }
            }
        } body: {
            if stackExpanded {
                VStack(spacing: 0) {
                    catalogSourceRow
                    ForEach(stack) { layer in
                        stackRow(layer)
                        if layer.id != stack.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
    }

    private var catalogSourceRow: some View {
        HStack(spacing: 6) {
            Text(catalogModel.sourceLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(catalogModel.sourceLabel == "ORCA" ? AppColors.accentSuccess : AppColors.accentWarning)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.backgroundTertiary.opacity(0.75))
                .clipShape(Capsule())
            if catalogModel.isLoading {
                ProgressView()
                    .scaleEffect(0.65)
            }
            if let error = catalogModel.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stackRow(_ layer: LabStackLayer) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(layer.tint.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: layer.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(layer.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(layer.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(layer.oneLine)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if layer.id == "nats" {
                    natsStatusPill
                } else {
                    statusPill(layer.status)
                }
                ownerChip(layer.owner)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var natsStatusPill: some View {
        Text(natsHealthModel.displayStatus)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(natsHealthModel.statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(natsHealthModel.statusColor.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("NATS \(natsHealthModel.displayStatus)")
    }

    // MARK: - Retired section

    private var retiredSection: some View {
        let retired = catalogModel.retiredItems
        return sectionCard {
            sectionHeader(title: "RETIRED", count: retired.count, expanded: retiredExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { retiredExpanded.toggle() }
                }
        } body: {
            if retiredExpanded {
                VStack(spacing: 0) {
                    ForEach(retired) { item in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppColors.textSecondary)
                                Text(item.reason)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.textTertiary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 6)
                            Text("⚫")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        if item.id != retired.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared helpers (mirrored from LabView for section rendering)

    @ViewBuilder
    private func sectionCard<Header: View, Body: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder body: () -> Body
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            body()
        }
        .background(AppColors.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func sectionHeader(title: String, count: Int? = nil, expanded: Bool, rightLabel: String? = nil, rightAction: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppColors.textSecondary)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            if let count = count {
                Text("· \(count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
            if let label = rightLabel {
                Button {
                    rightAction?()
                } label: {
                    HStack(spacing: 2) {
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.accentElectric)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppColors.accentElectric)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
    }

    private func statusPill(_ status: LabStatus) -> some View {
        HStack(spacing: 3) {
            Text(status.emoji).font(.system(size: 8))
            Text(status.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(status.color)
                .tracking(0.4)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func ownerChip(_ owner: String) -> some View {
        Text(owner)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(AppColors.textSecondary)
            .tracking(0.5)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }
}

// MARK: - NATS health model (used by stack section)

@MainActor
@Observable
final class LabNATSHealthModel {
    private(set) var status: String?
    private(set) var isLoading = false

    var displayStatus: String {
        if isLoading && status == nil { return "CHECKING" }
        return (status ?? "UNKNOWN").uppercased()
    }

    var badgeLabel: String {
        "NATS \(displayStatus)"
    }

    var statusColor: Color {
        switch (status ?? "").lowercased() {
        case "ok", "healthy", "live", "green":
            return AppColors.accentSuccess
        case "degraded", "warn", "warning", "yellow":
            return AppColors.accentWarning
        case "down", "failed", "error", "red":
            return AppColors.accentDanger
        default:
            return AppColors.textTertiary
        }
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: LabNATSHealthResponse = try await APIClient.shared.get(path: "/api/v1/nats/health")
            status = response.status ?? response.health ?? response.state ?? "unknown"
        } catch {
            status = "unknown"
        }
    }
}

private struct LabNATSHealthResponse: Decodable {
    let status: String?
    let health: String?
    let state: String?
    let message: String?
    let summary: String?
}
