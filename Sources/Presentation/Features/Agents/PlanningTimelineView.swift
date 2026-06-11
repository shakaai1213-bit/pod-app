import Foundation
import SwiftUI

// MARK: - Fleet Planner Timeline (Tony 2026-06-10: "visually see how agents are using planner")
//
// Renders /api/v1/planning/fleet/timeline — one row per agent, a now-centered
// 24h axis, colored capsules per planner block, and a now-line. Read-only.

// MARK: DTOs

struct FleetTimelineSnapshot: Decodable {
    let asOf: String
    let dayStart: String
    let dayEnd: String
    let agents: [FleetTimelineAgent]

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case dayStart = "day_start"
        case dayEnd = "day_end"
        case agents
    }
}

struct FleetTimelineAgent: Decodable, Identifiable {
    let agent: String
    let blocks: [FleetTimelineBlock]
    let currentTitle: String?
    let counts: [String: Int]

    var id: String { agent }

    enum CodingKeys: String, CodingKey {
        case agent
        case blocks
        case currentTitle = "current_title"
        case counts
    }
}

struct FleetTimelineBlock: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String?
    let status: String?
    let start: String
    let end: String
    let isCurrent: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, kind, status, start, end
        case isCurrent = "is_current"
    }
}

// MARK: - Timeline View

struct PlanningTimelineView: View {
    let snapshot: FleetTimelineSnapshot

    @State private var selectedBlock: FleetTimelineBlock?

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parse(_ value: String) -> Date? {
        isoParser.date(from: value) ?? isoParserNoFraction.date(from: value)
    }

    private var windowStart: Date { Self.parse(snapshot.dayStart) ?? Date().addingTimeInterval(-12 * 3600) }
    private var windowEnd: Date { Self.parse(snapshot.dayEnd) ?? Date().addingTimeInterval(12 * 3600) }
    private var asOf: Date { Self.parse(snapshot.asOf) ?? Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            legend

            VStack(spacing: 10) {
                hourAxis
                ForEach(snapshot.agents) { agent in
                    agentRow(agent)
                }
            }
            .padding(14)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let block = selectedBlock {
                blockDetailCard(block)
            }

            footnote
        }
    }

    // MARK: Rows

    private func agentRow(_ agent: FleetTimelineAgent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(agent.agent.capitalized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .frame(width: 64, alignment: .leading)

                if let current = agent.currentTitle {
                    Text("▶ \(current)")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.accentElectric)
                        .lineLimit(1)
                } else if agent.blocks.isEmpty {
                    Text("no planner blocks in window")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary.opacity(0.6))
                }
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(AppColors.backgroundPrimary.opacity(0.6))
                        .frame(height: 22)

                    ForEach(agent.blocks) { block in
                        if let frame = blockFrame(block, width: geo.size.width) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(color(for: block).opacity(block.isCurrent ? 1.0 : 0.55))
                                .frame(width: max(frame.width, 6), height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(
                                            block.isCurrent ? AppColors.accentElectric : .clear,
                                            lineWidth: 1.5
                                        )
                                )
                                .offset(x: frame.minX)
                                .onTapGesture { selectedBlock = block }
                        }
                    }

                    nowLine(width: geo.size.width)
                }
            }
            .frame(height: 22)
        }
    }

    private var hourAxis: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                ForEach(axisMarks(), id: \.self) { mark in
                    let x = xPosition(for: mark, width: geo.size.width)
                    VStack(spacing: 2) {
                        Text(Self.hourLabel(mark))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .offset(x: x - 12)
                }
                nowLine(width: geo.size.width)
            }
        }
        .frame(height: 14)
        .padding(.leading, 0)
    }

    private func nowLine(width: CGFloat) -> some View {
        Rectangle()
            .fill(AppColors.accentElectric)
            .frame(width: 1.5)
            .offset(x: xPosition(for: asOf, width: width))
    }

    // MARK: Geometry helpers

    private func xPosition(for date: Date, width: CGFloat) -> CGFloat {
        let total = windowEnd.timeIntervalSince(windowStart)
        guard total > 0 else { return 0 }
        let fraction = date.timeIntervalSince(windowStart) / total
        return CGFloat(min(max(fraction, 0), 1)) * width
    }

    private func blockFrame(_ block: FleetTimelineBlock, width: CGFloat) -> (minX: CGFloat, width: CGFloat)? {
        guard let start = Self.parse(block.start), let end = Self.parse(block.end) else { return nil }
        guard end > windowStart, start < windowEnd else { return nil }
        let minX = xPosition(for: start, width: width)
        let maxX = xPosition(for: end, width: width)
        return (minX, maxX - minX)
    }

    private func axisMarks() -> [Date] {
        var marks: [Date] = []
        var cursor = windowStart
        let calendar = Calendar.current
        // round up to next whole 4-hour boundary
        if let next = calendar.nextDate(
            after: cursor,
            matching: DateComponents(minute: 0),
            matchingPolicy: .nextTime
        ) {
            cursor = next
        }
        while cursor < windowEnd {
            if calendar.component(.hour, from: cursor) % 4 == 0 {
                marks.append(cursor)
            }
            cursor = cursor.addingTimeInterval(3600)
        }
        return marks
    }

    private static func hourLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "ha"
        return f.string(from: date).lowercased()
    }

    // MARK: Colors / legend / detail

    private func color(for block: FleetTimelineBlock) -> Color {
        switch (block.status ?? "planned").lowercased() {
        case "active": return AppColors.accentElectric
        case "done": return .green
        case "overdue": return .red
        case "cancelled": return AppColors.textSecondary.opacity(0.3)
        default: return .blue // planned
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(.blue, "Planned")
            legendDot(AppColors.accentElectric, "Active")
            legendDot(.green, "Done")
            legendDot(.red, "Overdue")
            Spacer()
        }
        .font(.system(size: 11))
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundColor(AppColors.textSecondary)
        }
    }

    private func blockDetailCard(_ block: FleetTimelineBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(block.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Button {
                    selectedBlock = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Text((block.status ?? "planned").capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color(for: block).opacity(0.2))
                    .foregroundColor(color(for: block))
                    .clipShape(Capsule())
                Text(Self.timeRange(block))
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
                if let kind = block.kind {
                    Text(kind)
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary.opacity(0.7))
                }
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private static func timeRange(_ block: FleetTimelineBlock) -> String {
        guard let s = parse(block.start), let e = parse(block.end) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        return "\(f.string(from: s))–\(f.string(from: e))".lowercased()
    }

    private var footnote: some View {
        Text("Blocks come from each agent's ORCA planner (plate-sync + self-scheduled). Window: now ±12h, device-local clock markers.")
            .font(.system(size: 11))
            .foregroundColor(AppColors.textSecondary.opacity(0.7))
    }
}
