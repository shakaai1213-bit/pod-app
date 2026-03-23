import Foundation
import UIKit

// MARK: - Wall Display ViewModel

@Observable
final class WallDisplayViewModel {

    // MARK: - State

    var agents: [Agent] = []
    var activities: [ActivityItem] = []
    var attentionCount: Int = 0
    var isDimmed: Bool = false
    var brightness: Double = 1.0
    var currentTime: Date = Date()

    // MARK: - Private

    private var timeTimer: Timer?
    private var refreshTimer: Timer?
    private var dimTimer: Timer?
    private var lastActivityTime: Date = Date()
    private var originalBrightness: CGFloat = 1.0

    private let dimDelaySeconds: TimeInterval = 300 // 5 minutes
    private let refreshIntervalSeconds: TimeInterval = 60

    // MARK: - Init

    init() {
        startClock()
    }

    deinit {
        timeTimer?.invalidate()
        refreshTimer?.invalidate()
        dimTimer?.invalidate()
        restoreBrightness()
    }

    // MARK: - Load

    @MainActor
    func loadAll() async {
        await fetchAgents()
        await fetchActivities()
        await fetchAttentionCount()
        resetDimTimer()
    }

    // MARK: - Refresh

    @MainActor
    func refresh() async {
        await fetchActivities()
        await fetchAttentionCount()
        await fetchAgents()
    }

    // MARK: - Dim / Wake

    func dim() {
        guard !isDimmed else { return }
        originalBrightness = UIScreen.main.brightness
        isDimmed = true
        brightness = 0.3
        UIScreen.main.brightness = CGFloat(brightness)
    }

    func wake() {
        guard isDimmed else { return }
        isDimmed = false
        brightness = 1.0
        UIScreen.main.brightness = CGFloat(brightness)
        resetDimTimer()
    }

    func recordActivity() {
        resetDimTimer()
        if isDimmed {
            wake()
        }
    }

    // MARK: - Private: Fetch

    @MainActor
    private func fetchAgents() async {
        agents = Self.mockAgents
    }

    @MainActor
    private func fetchActivities() async {
        activities = Self.mockActivities
    }

    @MainActor
    private func fetchAttentionCount() async {
        attentionCount = 2
    }

    // MARK: - Private: Clock

    private func startClock() {
        timeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = Date()
            }
        }
    }

    // MARK: - Private: Dim Timer

    private func resetDimTimer() {
        lastActivityTime = Date()
        dimTimer?.invalidate()
        guard !isDimmed else { return }
        dimTimer = Timer.scheduledTimer(withTimeInterval: dimDelaySeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dim()
            }
        }
    }

    // MARK: - Private: Restore Brightness

    private func restoreBrightness() {
        UIScreen.main.brightness = originalBrightness
    }

    // MARK: - Mock Data

    private static var mockAgents: [Agent] {
        [
            Agent(
                id: UUID(),
                name: "Maui",
                role: "Head of Engineering",
                status: .online,
                currentTask: "Reviewing PR #42",
                lastActivity: Date(),
                skills: ["Architecture", "iOS"],
                avatarColor: "#3B82F6"
            ),
            Agent(
                id: UUID(),
                name: "Researcher",
                role: "Research Agent",
                status: .busy,
                currentTask: "Analyzing market trends",
                lastActivity: Date().addingTimeInterval(-120),
                skills: ["Research", "Analysis"],
                avatarColor: "#A855F7"
            ),
            Agent(
                id: UUID(),
                name: "Builder",
                role: "Build Agent",
                status: .online,
                currentTask: "Deploying v2.1.0",
                lastActivity: Date().addingTimeInterval(-60),
                skills: ["CI/CD", "Infrastructure"],
                avatarColor: "#22C55E"
            ),
            Agent(
                id: UUID(),
                name: "Analyst",
                role: "Data Analyst",
                status: .idle,
                currentTask: nil,
                lastActivity: Date().addingTimeInterval(-300),
                skills: ["Data", "Analytics"],
                avatarColor: "#F59E0B"
            ),
            Agent(
                id: UUID(),
                name: "Sentinel",
                role: "Security Monitor",
                status: .online,
                currentTask: "Monitoring threats",
                lastActivity: Date().addingTimeInterval(-30),
                skills: ["Security", "Monitoring"],
                avatarColor: "#EF4444"
            ),
        ]
    }

    private static var mockActivities: [ActivityItem] {
        let now = Date()
        return [
            ActivityItem(
                id: UUID(),
                type: .taskCompleted,
                description: "PR #42 approved and merged to main",
                timestamp: now.addingTimeInterval(-45),
                actorName: "Builder",
                isActorAgent: true
            ),
            ActivityItem(
                id: UUID(),
                type: .messageSent,
                description: "New message in #projects channel",
                timestamp: now.addingTimeInterval(-180),
                actorName: "Maui",
                isActorAgent: false
            ),
            ActivityItem(
                id: UUID(),
                type: .agentMilestone,
                description: "Sentinel ran 1,000 security checks",
                timestamp: now.addingTimeInterval(-600),
                actorName: "Sentinel",
                isActorAgent: true
            ),
            ActivityItem(
                id: UUID(),
                type: .taskCreated,
                description: "Task created: Implement wall display mode",
                timestamp: now.addingTimeInterval(-1800),
                actorName: "Maui",
                isActorAgent: false
            ),
            ActivityItem(
                id: UUID(),
                type: .taskCompleted,
                description: "API rate limiting completed",
                timestamp: now.addingTimeInterval(-3600),
                actorName: "Researcher",
                isActorAgent: true
            ),
            ActivityItem(
                id: UUID(),
                type: .fileUploaded,
                description: "Architecture diagram updated",
                timestamp: now.addingTimeInterval(-7200),
                actorName: "Maui",
                isActorAgent: false
            ),
        ]
    }
}
