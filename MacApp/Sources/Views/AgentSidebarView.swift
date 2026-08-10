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
                    Text("ORCA")
                        .font(.headline)
                    Text("Captain Console")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 58)

            Divider()

            List(selection: agentSelection) {
                Section("Team") {
                    ForEach(model.agents) { agent in
                        AgentRow(agent: agent)
                            .tag(agent.id)
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

    private var agentSelection: Binding<String?> {
        Binding(
            get: { model.selectedAgentID },
            set: { if let id = $0 { model.selectAgent(id) } }
        )
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
        case .credentialsRequired, .incompatible, .unavailable: return .orcaCoral
        }
    }
}

extension AgentProfile.Accent {
    var color: Color {
        switch self {
        case .pink: return Color(red: 0.86, green: 0.25, blue: 0.52)
        case .orange: return Color(red: 0.91, green: 0.42, blue: 0.13)
        case .violet: return Color(red: 0.46, green: 0.34, blue: 0.78)
        case .green: return .orcaGreen
        case .red: return Color(red: 0.84, green: 0.24, blue: 0.22)
        case .cyan: return .orcaCyan
        case .teal: return Color(red: 0.10, green: 0.58, blue: 0.52)
        }
    }
}

extension Color {
    static let orcaCyan = Color(red: 0.08, green: 0.63, blue: 0.67)
    static let orcaGreen = Color(red: 0.16, green: 0.62, blue: 0.37)
    static let orcaAmber = Color(red: 0.88, green: 0.58, blue: 0.14)
    static let orcaCoral = Color(red: 0.88, green: 0.32, blue: 0.25)
}
