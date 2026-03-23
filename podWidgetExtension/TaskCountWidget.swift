import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct TaskCountEntry: TimelineEntry {
    let date: Date
    let taskData: TaskWidgetData
}

// MARK: - Timeline Provider

struct TaskCountProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskCountEntry {
        TaskCountEntry(date: Date(), taskData: TaskWidgetData(total: 12, completed: 7))
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskCountEntry) -> Void) {
        Task {
            let taskData = await WidgetDataProvider.fetchTaskData()
            completion(TaskCountEntry(date: Date(), taskData: taskData))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskCountEntry>) -> Void) {
        Task {
            let taskData = await WidgetDataProvider.fetchTaskData()
            let entry = TaskCountEntry(date: Date(), taskData: taskData)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }
}

// MARK: - Progress Ring View

struct ProgressRingView: View {
    let progress: Double
    let lineWidth: CGFloat
    let size: CGFloat

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    Color.secondary.opacity(0.2),
                    lineWidth: lineWidth
                )

            // Progress ring
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
        }
        .frame(width: size, height: size)
    }

    private var progressColor: Color {
        switch progress {
        case 0.75...1.0:
            return Color(hex: "#34C759")
        case 0.4..<0.75:
            return Color(hex: "#FF9500")
        default:
            return Color(hex: "#FF3B30")
        }
    }
}

// MARK: - Widget View

struct TaskCountWidgetView: View {
    var entry: TaskCountEntry

    var body: some View {
        VStack(spacing: 8) {
            // Ring + count
            ZStack(spacing: 0) {
                ProgressRingView(progress: entry.taskData.progress, lineWidth: 7, size: 76)

                VStack(spacing: 1) {
                    Text("\(entry.taskData.completed)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("of \(entry.taskData.total)")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundColor(.secondary)
                }
            }

            // Labels
            VStack(spacing: 2) {
                Text("tasks")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundColor(.primary)

                Text("\(entry.taskData.remaining) remaining")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            // Progress bar (compact)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressColor)
                        .frame(width: geo.size.width * CGFloat(entry.taskData.progress))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .widgetURL(WidgetDataProvider.deepLinkURL(to: .projects))
    }

    private var progressColor: Color {
        switch entry.taskData.progress {
        case 0.75...1.0: return Color(hex: "#34C759")
        case 0.4..<0.75: return Color(hex: "#FF9500")
        default:         return Color(hex: "#FF3B30")
        }
    }
}

// MARK: - Widget Configuration

struct TaskCountWidget: Widget {
    let kind: String = "TaskCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskCountProvider()) { entry in
            TaskCountWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Task Count")
        .description("Track your project task completion at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    TaskCountWidget()
} timeline: {
    TaskCountEntry(date: Date(), taskData: TaskWidgetData(total: 12, completed: 7))
    TaskCountEntry(date: Date(), taskData: TaskWidgetData(total: 5, completed: 5))
    TaskCountEntry(date: Date(), taskData: TaskWidgetData(total: 10, completed: 3))
}
