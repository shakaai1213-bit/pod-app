import OrcaDesign
import SwiftUI

struct AgentSidebarView: View {
    @Environment(OrcaMacModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    // Keep the Captain's primary destinations in the same order as Pod.
    private let podSections: [ConsoleSection] = [
        .overview, .work, .fund, .crew, .knowledge, .lab, .runtime, .maker
    ]

    private var toolSections: [ConsoleSection] {
        ConsoleSection.allCases.filter {
            $0 != .waitingOnCaptain && $0 != .conversations && !podSections.contains($0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(OrcaPalette.accentElectric)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ORCA Console")
                        .font(.headline)
                    Text("Lab operating surface")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 58)

            Divider()

            List {
                Section("ATTENTION") {
                    navigationButton(for: .waitingOnCaptain)
                }

                Section("MAIN") {
                    ForEach(podSections) { section in
                        navigationButton(for: section)
                    }
                }

                Section("OPERATIONS") {
                    ForEach(toolSections) { section in
                        navigationButton(for: section)
                    }
                }

                Section("Conversations") {
                    ForEach(model.agents) { agent in
                        Button {
                            model.selectAgent(agent.id)
                        } label: {
                            AgentRow(
                                agent: agent,
                                isSelected: model.selectedSection == .conversations
                                    && model.selectedAgentID == agent.id
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .accessibilityAddTraits(
                            model.selectedSection == .conversations && model.selectedAgentID == agent.id
                                ? .isSelected : []
                        )
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            HStack(spacing: 8) {
                ConnectionDot(state: model.connectionState)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.connectionState.label)
                        .font(.caption.weight(.medium))
                    Text(URL(string: model.serverAddress)?.host ?? model.serverAddress)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Runtime settings")
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
        }
        .background(OrcaPalette.backgroundSecondary)
    }

    private func navigationButton(for section: ConsoleSection) -> some View {
        Button {
            model.selectSection(section)
        } label: {
            ConsoleNavigationRow(
                section: section,
                badgeCount: section == .waitingOnCaptain
                    ? model.sectionSnapshots[.waitingOnCaptain]?.badgeCount ?? 0
                    : 0,
                isSelected: isSelected(section)
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(isSelected(section) ? .isSelected : [])
    }

    private func isSelected(_ section: ConsoleSection) -> Bool {
        if section == .waitingOnCaptain {
            return model.selectedSection == .work && model.workMode == .captain
        }
        if section == .work {
            return model.selectedSection == .work && model.workMode != .captain
        }
        return model.selectedSection == section
    }
}

private struct ConsoleNavigationRow: View {
    let section: ConsoleSection
    let badgeCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? OrcaPalette.accentElectric : OrcaPalette.textSecondary)
                .frame(width: 24)

            HStack(spacing: 5) {
                Text(section.title)
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? OrcaPalette.textPrimary : OrcaPalette.textSecondary)
                if section.isProtected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(OrcaPalette.textSecondary)
                }
            }

            Spacer(minLength: 4)

            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orcaCoral, in: Capsule())
                    .accessibilityLabel("\(badgeCount) items waiting")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            isSelected ? OrcaPalette.accentElectric.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
    }
}

private struct AgentRow: View {
    let agent: AgentProfile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(agent.accent.color.opacity(0.16))
                Image(systemName: agent.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(agent.accent.color)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(agent.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(OrcaPalette.textPrimary)
                    if agent.lane == .protected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(agent.role)
                    .font(.caption)
                    .foregroundStyle(OrcaPalette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            isSelected ? OrcaPalette.accentElectric.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
    }
}

struct ConnectionDot: View {
    let state: RuntimeConnectionState

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 8))
            .foregroundStyle(color)
            .accessibilityLabel(state.label)
    }

    private var color: Color {
        switch state {
        case .ready: return .orcaGreen
        case .connecting: return .orcaAmber
        case .idle: return .secondary
        case .credentialsRequired, .runtimeUpgradeRequired, .incompatible, .unavailable: return .orcaCoral
        }
    }
}
