import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct TeamActivityEntry: TimelineEntry {
    let date: Date
    let teamData: TeamActivityData
}

// MARK: - Timeline Provider

struct TeamActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> TeamActivityEntry {
        TeamActivityEntry(date: Date(), teamData: Self.placeholderData)
    }

    func getSnapshot(in context: Context, completion: @escaping (TeamActivityEntry) -> Void) {
        Task {
            let teamData = await WidgetDataProvider.fetchTeamActivityData()
            completion(TeamActivityEntry(date: Date(), teamData: teamData))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TeamActivityEntry>) -> Void) {
        Task {
            let teamData = await WidgetDataProvider.fetchTeamActivityData()
            let entry = TeamActivityEntry(date: Date(), teamData: teamData)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private static var placeholderData: TeamActivityData {
        let now = Date()
        return TeamActivityData(
            agents: [
                AgentWidgetData(name: "Maui", status: "online", color: "#34C759"),
                AgentWidgetData(name: "Kai", status: "online", color: "#34C759"),
                AgentWidgetData(name: "Luna", status: "idle", color: "#FF9500"),
                AgentWidgetData(name: "Atlas", status: "offline", color: "#8E8E93"),
            ],
            activities: [
                ActivityWidgetItem(
                    icon: "checkmark.circle.fill",
                    description: "Completed build pipeline",
                    timestamp: now.addingTimeInterval(-180),
                    agentName: "Maui"
                ),
                ActivityWidgetItem(
                    icon: "arrow.triangle.2.circlepath",
                    description: "Synced project files",
                    timestamp: now.addingTimeInterval(-600),
                    agentName: "Kai"
                ),
                ActivityWidgetItem(
                    icon: "doc.text.fill",
                    description: "Updated docs",
                    timestamp: now.addingTimeInterval(-1800),
                    agentName: "Luna"
                ),
            ]
        )
    }
}

// MARK: - Agent Status Strip View

struct AgentStatusStripView: View {
    let agents: [AgentWidgetData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEAM")
                .font(.system(size: 9, weight: .bold, design: .default))
                .foregroundColor(.secondary)
                .tracking(1)

            ForEach(displayedAgents) { agent in
                HStack(spacing: 6) {
                    Circle()
                        .fill(agentColor(for: agent))
                        .frame(width: 7, height: 7)

                    Text(agent.name)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text("\(onlineCount)/\(agents.count) online")
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundColor(Color(hex: "#34C759"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayedAgents: [AgentWidgetData] {
        Array(agents.prefix(4))
    }

    private var onlineCount: Int {
        agents.filter { $0.statusColor == .online }.count
    }

    private func agentColor(for agent: AgentWidgetData) -> Color {
        switch agent.statusColor {
        case .online:  return Color(hex: "#34C759")
        case .idle:    return Color(hex: "#FF9500")
        case .busy:    return Color(hex: "#FF3B30")
        case .offline: return Color(hex: "#8E8E93")
        }
    }
}

// MARK: - Activity Item View

struct ActivityItemView: View {
    let item: ActivityWidgetItem

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 18)

            // Description + agent
            VStack(alignment: .leading, spacing: 1) {
                Text(item.description)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(item.agentName) · \(item.relativeTime)")
                    .font(.system(size: 9, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var iconColor: Color {
        switch item.icon {
        case "checkmark.circle.fill": return Color(hex: "#34C759")
        case "arrow.triangle.2.circlepath": return Color(hex: "#007AFF")
        case "doc.text.fill": return Color(hex: "#FF9500")
        case "exclamationmark.triangle.fill": return Color(hex: "#FF3B30")
        case "bolt.fill": return Color(hex: "#FFCC00")
        default: return Color(hex: "#8E8E93")
        }
    }
}

// MARK: - Activity Column View

struct ActivityColumnView: View {
    let activities: [ActivityWidgetItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIVITY")
                .font(.system(size: 9, weight: .bold, design: .default))
                .foregroundColor(.secondary)
                .tracking(1)

            ForEach(displayedActivities) { item in
                ActivityItemView(item: item)
            }

            if activities.isEmpty {
                Text("No recent activity")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayedActivities: [ActivityWidgetItem] {
        Array(activities.prefix(3))
    }
}

// MARK: - Widget View

struct TeamActivityWidgetView: View {
    var entry: TeamActivityEntry

    var body: some View {
        HStack(spacing: 12) {
            // Left: Agent status strip
            AgentStatusStripView(agents: entry.teamData.agents)
                .frame(width: 85)

            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 1)

            // Right: Activity feed
            ActivityColumnView(activities: entry.teamData.activities)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .widgetURL(WidgetDataProvider.deepLinkURL(to: .dashboard))
    }
}

// MARK: - Widget Configuration

struct TeamActivityWidget: Widget {
    let kind: String = "TeamActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TeamActivityProvider()) { entry in
            TeamActivityWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Team Activity")
        .description("See agent statuses and recent team activity.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemMedium) {
    TeamActivityWidget()
} timeline: {
    TeamActivityEntry(date: Date(), teamData: TeamActivityProvider.placeholderData)
}
