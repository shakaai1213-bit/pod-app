import OrcaDesign
import SwiftUI

struct AgentSidebarView: View {
    @Environment(OrcaMacModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.orcaCyan)
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
                Section("ORCA") {
                    ForEach(ConsoleSection.allCases.filter { $0 != .conversations }) { section in
                        Button {
                            model.selectSection(section)
                        } label: {
                            ConsoleNavigationRow(section: section)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            model.selectedSection == section
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                    }
                }

                Section("Conversations") {
                    ForEach(model.agents) { agent in
                        Button {
                            model.selectAgent(agent.id)
                        } label: {
                            AgentRow(agent: agent)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            model.selectedSection == .conversations && model.selectedAgentID == agent.id
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                    }
                }
            }
            .listStyle(.sidebar)

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
        .background(Color(nsColor: .windowBackgroundColor))
    }

}

private struct ConsoleNavigationRow: View {
    let section: ConsoleSection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(section == .fund ? Color.orcaGreen : Color.orcaCyan)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(section.title)
                        .font(.body.weight(.medium))
                    if section.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 36)
        .contentShape(Rectangle())
    }
}

private struct AgentRow: View {
    let agent: AgentProfile

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
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
                    if agent.lane == .protected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(agent.role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 38)
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
