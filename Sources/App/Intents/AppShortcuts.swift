import AppIntents

struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Check Agent Status
        AppShortcut(
            intent: CheckAgentStatusIntent(),
            phrases: [
                "Check \(\.$agentName) status in \(.applicationName)",
                "How is \(\.$agentName) doing in \(.applicationName)",
                "Is \(\.$agentName) online in \(.applicationName)",
                "Check \(\.$agentName) in \(.applicationName)",
                "What's \(\.$agentName) doing in \(.applicationName)"
            ],
            shortTitle: "Check Agent",
            systemImageName: "cpu"
        )

        // Get Team Status
        AppShortcut(
            intent: GetTeamStatusIntent(),
            phrases: [
                "Get team status in \(.applicationName)",
                "How is the team doing in \(.applicationName)",
                "\(.applicationName) team status",
                "How many agents are online in \(.applicationName)",
                "Check team in \(.applicationName)"
            ],
            shortTitle: "Team Status",
            systemImageName: "person.3"
        )

        // Send Message
        AppShortcut(
            intent: SendMessageIntent(),
            phrases: [
                "Send \(\.$message) to \(\.$channel) in \(.applicationName)",
                "Message \(\.$channel) in \(.applicationName)",
                "Post \(\.$message) to \(\.$channel) with \(.applicationName)"
            ],
            shortTitle: "Send Message",
            systemImageName: "bubble.left"
        )

        // Get Attention Items
        AppShortcut(
            intent: GetAttentionItemsIntent(),
            phrases: [
                "Get attention items in \(.applicationName)",
                "What needs my attention in \(.applicationName)",
                "Show me alerts in \(.applicationName)",
                "Check pending items in \(.applicationName)"
            ],
            shortTitle: "Attention Items",
            systemImageName: "exclamationmark.triangle"
        )

        // Approve Request
        AppShortcut(
            intent: ApproveRequestIntent(),
            phrases: [
                "Approve \(\.$requestId) in \(.applicationName)",
                "Approve request \(\.$requestId) with \(.applicationName)",
                "Confirm \(\.$requestId) in \(.applicationName)"
            ],
            shortTitle: "Approve Request",
            systemImageName: "checkmark.circle"
        )

        // Start Focus Mode
        AppShortcut(
            intent: StartFocusModeIntent(),
            phrases: [
                "Start focus mode in \(.applicationName)",
                "Enable do not disturb in \(.applicationName)",
                "Turn on focus mode with \(.applicationName)"
            ],
            shortTitle: "Start Focus",
            systemImageName: "moon.fill"
        )

        // Stop Focus Mode
        AppShortcut(
            intent: StopFocusModeIntent(),
            phrases: [
                "Stop focus mode in \(.applicationName)",
                "Disable focus mode with \(.applicationName)",
                "Turn off focus mode in \(.applicationName)"
            ],
            shortTitle: "Stop Focus",
            systemImageName: "sun.max"
        )
    }
}
