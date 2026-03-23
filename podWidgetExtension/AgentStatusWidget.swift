import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct AgentStatusEntry: TimelineEntry {
    let date: Date
    let agents: [AgentWidgetData]
}

// MARK: - Timeline Provider

struct AgentStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgentStatusEntry {
        AgentStatusEntry(date: Date(), agents: Self.placeholderAgents)
    }

    func getSnapshot(in context: Context, completion: @escaping (AgentStatusEntry) -> Void) {
        Task {
            let agents = await WidgetDataProvider.fetchAgentData()
            completion(AgentStatusEntry(date: Date(), agents: agents))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgentStatusEntry>) -> Void) {
        Task {
            let agents = await WidgetDataProvider.fetchAgentData()
            let entry = AgentStatusEntry(date: Date(), agents: agents)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private static var placeholderAgents: [AgentWidgetData] {
        [
            AgentWidgetData(name: "Maui", status: "online", color: "#34C759"),
            AgentWidgetData(name: "Kai", status: "idle", color: "#FF9500"),
            AgentWidgetData(name: "Luna", status: "offline", color: "#8E8E93"),
            AgentWidgetData(name: "Atlas", status: "busy", color: "#FF3B30"),
        ]
    }
}

// MARK: - Status Dot View

struct StatusDot: View {
    let status: AgentStatus

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch status {
        case .online:  return Color(hex: "#34C759")
        case .idle:    return Color(hex: "#FF9500")
        case .busy:    return Color(hex: "#FF3B30")
        case .offline: return Color(hex: "#8E8E93")
        }
    }
}

// MARK: - Agent Row View

struct AgentRowView: View {
    let agent: AgentWidgetData

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: agent.statusColor)
                .frame(width: 8, height: 8)

            Text(agent.name)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Text(agent.status.capitalized)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Widget View

struct AgentStatusWidgetView: View {
    var entry: AgentStatusEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("Agents")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Text("\(onlineCount) online")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(Color(hex: "#34C759"))
            }

            Divider()

            // Agent List
            VStack(alignment: .leading, spacing: 5) {
                ForEach(displayedAgents) { agent in
                    AgentRowView(agent: agent)
                }
            }

            if entry.agents.count > 4 {
                Spacer()
                Text("+\(entry.agents.count - 4) more")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .widgetURL(WidgetDataProvider.deepLinkURL(to: .agents))
    }

    private var onlineCount: Int {
        entry.agents.filter { $0.statusColor == .online }.count
    }

    private var displayedAgents: [AgentWidgetData] {
        Array(entry.agents.prefix(4))
    }
}

// MARK: - Widget Configuration

struct AgentStatusWidget: Widget {
    let kind: String = "AgentStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentStatusProvider()) { entry in
            AgentStatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Agent Status")
        .description("See who's online and their current status.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    AgentStatusWidget()
} timeline: {
    AgentStatusEntry(date: Date(), agents: [
        AgentWidgetData(name: "Maui", status: "online", color: "#34C759"),
        AgentWidgetData(name: "Kai", status: "idle", color: "#FF9500"),
        AgentWidgetData(name: "Luna", status: "offline", color: "#8E8E93"),
        AgentWidgetData(name: "Atlas", status: "busy", color: "#FF3B30"),
    ])
}
