import Foundation

// MARK: - Reaction

// MARK: - ActivityType

// MARK: - ActivityItem

// MARK: - AttentionSeverity

// MARK: - AttentionType

// MARK: - AttentionItem

// MARK: - MockData

enum MockData {

    // MARK: - Agents

    static let agents: [Agent] = [
        Agent(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            name: "Maui",
            role: "Head of Engineering",
            status: .online,
            currentTask: "Building pod app",
            lastActivity: Date().addingTimeInterval(-120),
            skills: ["SwiftUI", "iOS", "Architecture", "Swift", "Xcode"],
            avatarColor: "#22C55E"
        ),
        Agent(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000002")!,
            name: "Chief",
            role: "Trading Lead",
            status: .busy,
            currentTask: "Analyzing market data",
            lastActivity: Date().addingTimeInterval(-300),
            skills: ["Trading", "Python", "Finance", "NATS", "Data Analysis"],
            avatarColor: "#F97316"
        ),
        Agent(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000003")!,
            name: "Aloha",
            role: "Communications",
            status: .online,
            currentTask: nil,
            lastActivity: Date().addingTimeInterval(-60),
            skills: ["Messaging", "Coordination", "Discord", "Notifications"],
            avatarColor: "#A855F7"
        ),
        Agent(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000004")!,
            name: "Turtle",
            role: "Research",
            status: .idle,
            currentTask: nil,
            lastActivity: Date().addingTimeInterval(-3600),
            skills: ["Analysis", "Research", "Experimentation", "Statistics"],
            avatarColor: "#3B82F6"
        ),
        Agent(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000005")!,
            name: "Aurora",
            role: "Architecture",
            status: .online,
            currentTask: "Reviewing pod DDS",
            lastActivity: Date().addingTimeInterval(-180),
            skills: ["Design", "Systems", "DDS", "Protocol Buffers"],
            avatarColor: "#F59E0B"
        )
    ]

    // MARK: - Channel IDs (stable for consistent demo)

    private static let generalChannelId = UUID(uuidString: "c0000001-0000-0000-0000-000000000001")!
    private static let projectsChannelId = UUID(uuidString: "c0000001-0000-0000-0000-000000000002")!
    private static let researchChannelId = UUID(uuidString: "c0000001-0000-0000-0000-000000000003")!
    private static let agentsChannelId = UUID(uuidString: "c0000001-0000-0000-0000-000000000004")!
    private static let alertsChannelId = UUID(uuidString: "c0000001-0000-0000-0000-000000000005")!
    private static let chiefDeskChannelId = UUID(uuidString: "c0000001-0000-0000-0000-000000000006")!

    // MARK: - Messages

    static let messages: [Message] = {
        let mauiId = UUID(uuidString: "00000001-0000-0000-0000-000000000001")!
        let chiefId = UUID(uuidString: "00000001-0000-0000-0000-000000000002")!
        let alohaId = UUID(uuidString: "00000001-0000-0000-0000-000000000003")!
        let turtleId = UUID(uuidString: "00000001-0000-0000-0000-000000000004")!
        let auroraId = UUID(uuidString: "00000001-0000-0000-0000-000000000005")!

        let msg1Id = UUID(uuidString: "m0000001-0000-0000-0000-000000000001")!
        let msg2Id = UUID(uuidString: "m0000001-0000-0000-0000-000000000002")!
        let msg3Id = UUID(uuidString: "m0000001-0000-0000-0000-000000000003")!
        let msg4Id = UUID(uuidString: "m0000001-0000-0000-0000-000000000004")!
        let msg5Id = UUID(uuidString: "m0000001-0000-0000-0000-000000000005")!
        let msg6Id = UUID(uuidString: "m0000001-0000-0000-0000-000000000006")!
        let msg7Id = UUID(uuidString: "m0000001-0000-0000-0000-000000000007")!
        let msg8Id = UUID(uuidString: "m0000001-0000-0000-0000-000000000008")!
        let msg9Id = UUID(uuidString: "m0000001-0000-0000-0000-000000000009")!
        let msg10Id = UUID(uuidString: "m0000001-0000-0000-0000-000000000010")!

        return [
            Message(
                id: msg1Id,
                channelId: generalChannelId,
                authorId: mauiId,
                isAgent: true,
                agentId: "maui",
                content: "**pod** app is officially in Phase 2. 42 files, 13K lines of Swift. Let's go. 🎉",
                timestamp: Date().addingTimeInterval(-300),
                reactions: [
                    Reaction(emoji: "🎉", count: 3),
                    Reaction(emoji: "🔥", count: 2)
                ]
            ),
            Message(
                id: msg2Id,
                channelId: projectsChannelId,
                authorId: chiefId,
                isAgent: true,
                agentId: "chief",
                content: "New market data suggests a breakout opportunity in NVDA. Running analysis now. Will post findings in 30 min.",
                timestamp: Date().addingTimeInterval(-600),
                reactions: [Reaction(emoji: "🚀", count: 1)]
            ),
            Message(
                id: msg3Id,
                channelId: researchChannelId,
                authorId: turtleId,
                isAgent: true,
                agentId: "turtle",
                content: "Experiment results are in — val_bpb=1.808 is our new champion. Commit `5efc7aa`. Full report attached to the DDS.",
                timestamp: Date().addingTimeInterval(-1800),
                reactions: []
            ),
            Message(
                id: msg4Id,
                channelId: agentsChannelId,
                authorId: alohaId,
                isAgent: true,
                agentId: "aloha",
                content: "⚠️ Agent `Rogue-7` detected a rogue daemon on node-4. Auto-terminated at 14:22:07 UTC. No collateral damage.",
                timestamp: Date().addingTimeInterval(-3600),
                reactions: [Reaction(emoji: "👀", count: 1)]
            ),
            Message(
                id: msg5Id,
                channelId: generalChannelId,
                authorId: auroraId,
                isAgent: true,
                agentId: "aurora",
                content: "Updated the standards library with our new RFC process. Check #knowledge. All agents should review before submitting new RFCs.",
                timestamp: Date().addingTimeInterval(-7200),
                reactions: [Reaction(emoji: "✅", count: 1)]
            ),
            Message(
                id: msg6Id,
                channelId: chiefDeskChannelId,
                authorId: chiefId,
                isAgent: true,
                agentId: "chief",
                content: "**Daily Brief — Mar 22**\n• NVDA: Breakout confirmed, +4.2% premarket\n• SPY: Holding 520 support\n• Positions: 60% long, rotating into semis\n• Risk: VIX elevated at 18.4\n\nAll agents monitor your assigned tickers.",
                timestamp: Date().addingTimeInterval(-900),
                reactions: []
            ),
            Message(
                id: msg7Id,
                channelId: projectsChannelId,
                authorId: mauiId,
                isAgent: true,
                agentId: "maui",
                content: "v2.7.15 is staged for deployment. Need one approval from Chief or Aurora before we push to prod. Link: `https://orion.shaka.dev/deploy/2.7.15`",
                timestamp: Date().addingTimeInterval(-1200),
                reactions: [Reaction(emoji: "🙏", count: 1)]
            ),
            Message(
                id: msg8Id,
                channelId: alertsChannelId,
                authorId: alohaId,
                isAgent: true,
                agentId: "aloha",
                content: "ℹ️ Backend health check passed. All services green. Uptime: 99.97% over 30 days.",
                timestamp: Date().addingTimeInterval(-5400),
                reactions: []
            ),
            Message(
                id: msg9Id,
                channelId: researchChannelId,
                authorId: turtleId,
                isAgent: true,
                agentId: "turtle",
                content: "Starting new experiment series: `exp/llm-temperature-sweep`. Aiming to find the optimal temp for creative vs. analytical tasks. ETA: 4 hours.",
                timestamp: Date().addingTimeInterval(-10800),
                reactions: [Reaction(emoji: "🧪", count: 1)]
            ),
            Message(
                id: msg10Id,
                channelId: generalChannelId,
                authorId: UUID(),
                isAgent: false,
                agentId: nil,
                content: "Quick heads up — I'll be offline tomorrow morning for a dentist appointment. Ping me on Signal if anything critical comes up.",
                timestamp: Date().addingTimeInterval(-14400),
                reactions: [Reaction(emoji: "✅", count: 1)]
            )
        ]
    }()

    // MARK: - Channels

    static let channels: [Channel] = [
        Channel(
            id: generalChannelId,
            name: "general",
            type: .general,
            lastMessage: messages[0].content,
            lastMessageTimestamp: messages[0].timestamp,
            unreadCount: 2,
            isPinned: true,
            isMuted: false
        ),
        Channel(
            id: projectsChannelId,
            name: "projects",
            type: .projects,
            lastMessage: messages[1].content,
            lastMessageTimestamp: messages[1].timestamp,
            unreadCount: 5,
            isPinned: true,
            isMuted: false
        ),
        Channel(
            id: researchChannelId,
            name: "research",
            type: .research,
            lastMessage: messages[2].content,
            lastMessageTimestamp: messages[2].timestamp,
            unreadCount: 1,
            isPinned: false,
            isMuted: false
        ),
        Channel(
            id: agentsChannelId,
            name: "agents",
            type: .agents,
            lastMessage: messages[3].content,
            lastMessageTimestamp: messages[3].timestamp,
            unreadCount: 0,
            isPinned: false,
            isMuted: false
        ),
        Channel(
            id: alertsChannelId,
            name: "alerts",
            type: .alerts,
            lastMessage: messages[7].content,
            lastMessageTimestamp: messages[7].timestamp,
            unreadCount: 1,
            isPinned: true,
            isMuted: false
        ),
        Channel(
            id: chiefDeskChannelId,
            name: "chief-desk",
            type: .general,
            lastMessage: messages[5].content,
            lastMessageTimestamp: messages[5].timestamp,
            unreadCount: 0,
            isPinned: false,
            isMuted: false
        )
    ]

    // MARK: - Standards

    static let standards: [Standard] = {
        let auroraId = UUID(uuidString: "00000001-0000-0000-0000-000000000005")!
        let mauiId = UUID(uuidString: "00000001-0000-0000-0000-000000000001")!

        return [
            Standard(
                id: UUID(uuidString: "s0000001-0000-0000-0000-000000000001")!,
                title: "RFC Process",
                category: .frameworks,
                content: """
                # RFC Process

                ## When to Use

                Any significant architectural decision, API change, or process modification that affects multiple agents or the shared codebase must go through the RFC process.

                ## Steps

                1. **Draft** — Author creates a new file in `pod-rfcs/` named `NNNN-title.md`
                2. **Review** — Post to `#projects` with `@here RFC: <title>` for a minimum 48h review
                3. **Feedback** — All agents may comment; blocking concerns must be explicitly marked
                4. **Resolution** — Author marks Accepted, Rejected, or Deferred with rationale
                5. **Merge** — Accepted RFCs are merged into `pod-standards/` and referenced in code

                ## RFC Template

                ```markdown
                # RFC NNNN: <Title>

                ## Status: Draft | Accepted | Rejected

                ## Summary
                One paragraph explaining what this RFC does.

                ## Motivation
                Why is this needed? What problem does it solve?

                ## Detailed Design
                Full technical specification.

                ## Alternatives Considered
                What else was evaluated and why this was chosen.

                ## Open Questions
                Unresolved items before this can be accepted.
                ```

                ## Champions

                Each RFC must have a named champion who is responsible for driving it to resolution.
                """,
                authorId: auroraId,
                tags: ["process", "rfc", "decision", "governance"],
                version: 2,
                createdAt: Date().addingTimeInterval(-86400 * 7),
                updatedAt: Date().addingTimeInterval(-86400),
                isFavorite: true,
                readingPosition: nil
            ),
            Standard(
                id: UUID(uuidString: "s0000001-0000-0000-0000-000000000002")!,
                title: "API Design Guidelines",
                category: .standards,
                content: """
                # API Design Guidelines

                ## REST Conventions

                - **Resources** are nouns: `/agents`, `/channels`, `/messages`
                - **Actions** use HTTP methods: GET, POST, PUT, PATCH, DELETE
                - **IDs** in path: `GET /channels/{channelId}`
                - **Pagination**: `?limit=50&cursor=<opaque>`
                - **Filtering**: `?status=online&role=engineering`

                ## Response Envelope

                ```json
                {
                  "data": { ... },
                  "meta": {
                    "cursor": "opaque-next-page-token",
                    "hasMore": true,
                    "total": 142
                  },
                  "error": null
                }
                ```

                ## Error Handling

                | Code | Meaning |
                |------|---------|
                | 400  | Bad request — invalid input |
                | 401  | Unauthenticated |
                | 403  | Unauthorized |
                | 404  | Resource not found |
                | 409  | Conflict (e.g., duplicate) |
                | 422  | Validation error |
                | 429  | Rate limited |
                | 500  | Internal server error |

                ## Versioning

                Current version: `v1`
                Base URL: `https://api.orion.shaka.dev/v1`

                Breaking changes require a new major version. Additive changes are backward-compatible.
                """,
                authorId: mauiId,
                tags: ["api", "design", "standards", "rest"],
                version: 3,
                createdAt: Date().addingTimeInterval(-86400 * 30),
                updatedAt: Date().addingTimeInterval(-86400 * 3),
                isFavorite: false,
                readingPosition: 450
            ),
            Standard(
                id: UUID(uuidString: "s0000001-0000-0000-0000-000000000003")!,
                title: "Code Review Standards",
                category: .standards,
                content: """
                # Code Review Standards

                ## Philosophy

                Code review is about **quality** and **knowledge sharing**, not gatekeeping. Be constructive, specific, and kind.

                ## Requirements

                - All code touching shared or core code requires review
                - Minimum 1 approval before merge
                - Critical paths (auth, payments, data mutations) require 2 approvals
                - Reviews must be completed within 24 hours or escalate

                ## What to Check

                **Correctness** — Does it do what it says?
                **Clarity** — Will future-you understand this?
                **Performance** — Any obvious O(n²) traps or missing indexes?
                **Security** — Auth, input validation, secrets?
                **Tests** — Are the happy path and error cases covered?

                ## Comment Conventions

                - `nit:` — Minor style, non-blocking
                - `suggestion:` — Take it or leave it
                - `question:` — Seeking understanding
                - `blocker:` — Must resolve before merge
                """,
                authorId: mauiId,
                tags: ["code", "review", "standards", "process"],
                version: 1,
                createdAt: Date().addingTimeInterval(-86400 * 14),
                updatedAt: Date().addingTimeInterval(-86400 * 5),
                isFavorite: false,
                readingPosition: nil
            ),
            Standard(
                id: UUID(uuidString: "s0000001-0000-0000-0000-000000000004")!,
                title: "DDS Protocol Specification",
                category: .frameworks,
                content: """
                # DDS Protocol Specification

                ## Overview

                The Distributed Discovery Service (DDS) enables agents to discover and communicate with each other using typed message passing over NATS.

                ## Topics

                | Topic | Purpose |
                |-------|---------|
                | `pod.dds.heartbeat` | Agent presence + status |
                | `pod.dds.discovery` | Service discovery |
                | `pod.dds.dispatch` | Task dispatch |
                | `pod.dds.events` | Cross-agent events |

                ## Heartbeat Schema

                ```json
                {
                  "agentId": "uuid",
                  "name": "AgentName",
                  "status": "online|busy|idle",
                  "capabilities": ["skill1", "skill2"],
                  "upSince": "ISO8601"
                }
                ```

                ## Dispatch Protocol

                1. Caller publishes to `pod.dds.dispatch` with `replyTo` set
                2. Target agent responds on the reply subject
                3. Caller times out after 30 seconds
                4. Retries: exponential backoff, max 3 attempts
                """,
                authorId: auroraId,
                tags: ["dds", "nats", "protocol", "messaging"],
                version: 4,
                createdAt: Date().addingTimeInterval(-86400 * 60),
                updatedAt: Date().addingTimeInterval(-86400 * 2),
                isFavorite: true,
                readingPosition: 280
            )
        ]
    }()

    // MARK: - Activity Items

    static let activities: [ActivityItem] = [
        ActivityItem(
            id: UUID(),
            type: .taskCompleted,
            description: "Task 'Fix auth hydration bug' completed",
            timestamp: Date().addingTimeInterval(-180),
            actor: "Maui"
        ),
        ActivityItem(
            id: UUID(),
            type: .messageReceived,
            description: "Chief posted market analysis in #projects",
            timestamp: Date().addingTimeInterval(-600),
            actor: "Chief"
        ),
        ActivityItem(
            id: UUID(),
            type: .agentStatusChange,
            description: "Aloha came online",
            timestamp: Date().addingTimeInterval(-1200),
            actor: "Aloha"
        ),
        ActivityItem(
            id: UUID(),
            type: .approvalRequested,
            description: "Chief requested approval: Deploy v2.7.15",
            timestamp: Date().addingTimeInterval(-1800),
            actor: "Chief"
        ),
        ActivityItem(
            id: UUID(),
            type: .taskCreated,
            description: "New task 'Add push notifications' created",
            timestamp: Date().addingTimeInterval(-2400),
            actor: "Maui"
        ),
        ActivityItem(
            id: UUID(),
            type: .systemAlert,
            description: "Memory usage on node-4 crossed 80% threshold",
            timestamp: Date().addingTimeInterval(-3000),
            actor: "System"
        ),
        ActivityItem(
            id: UUID(),
            type: .taskCompleted,
            description: "Task 'Update API docs' completed",
            timestamp: Date().addingTimeInterval(-3600),
            actor: "Aurora"
        ),
        ActivityItem(
            id: UUID(),
            type: .agentStatusChange,
            description: "Turtle went idle",
            timestamp: Date().addingTimeInterval(-4200),
            actor: "Turtle"
        )
    ]

    // MARK: - Attention Items

    static let attentionItems: [AttentionItem] = [
        AttentionItem(
            id: UUID(),
            type: .pendingApproval,
            title: "Deploy v2.7.15",
            severity: .warning,
            actor: "Chief"
        ),
        AttentionItem(
            id: UUID(),
            type: .blockedTask,
            title: "Standards table schema not finalized",
            severity: .critical,
            actor: "Shaka"
        ),
        AttentionItem(
            id: UUID(),
            type: .agentError,
            title: "Rogue-7 daemon terminated — review logs",
            severity: .critical,
            actor: "Aloha"
        )
    ]

    // MARK: - Projects

    static let projects: [Project] = {
        let mauiId = UUID(uuidString: "00000001-0000-0000-0000-000000000001")!
        let createdAt = Date().addingTimeInterval(-86400 * 30)

        return [
            Project(
                id: UUID(),
                name: "pod App",
                description: "Native iOS app for ORCA Mission Control",
                boardGroupId: UUID(),
                status: .active,
                stage: .dev,
                createdAt: createdAt,
                updatedAt: Date(),
                taskCount: 8,
                completedTaskCount: 5
            ),
            Project(
                id: UUID(),
                name: "DDS Integration",
                description: "Full NATS-based distributed discovery and dispatch",
                boardGroupId: UUID(),
                status: .active,
                stage: .dev,
                createdAt: createdAt.addingTimeInterval(-86400 * 20),
                updatedAt: Date(),
                taskCount: 6,
                completedTaskCount: 2
            ),
            Project(
                id: UUID(),
                name: "Trading Bot v3",
                description: "Next-gen trading strategy with ML signals",
                boardGroupId: UUID(),
                status: .active,
                stage: .plan,
                createdAt: createdAt.addingTimeInterval(-86400 * 50),
                updatedAt: Date(),
                taskCount: 3,
                completedTaskCount: 0
            )
        ]
    }()

    // MARK: - Tasks

    static let tasks: [ProjectTask] = {
        let mauiId = UUID(uuidString: "00000001-0000-0000-0000-000000000001")!
        let auroraId = UUID(uuidString: "00000001-0000-0000-0000-000000000005")!
        let chiefId = UUID(uuidString: "00000001-0000-0000-0000-000000000002")!
        let project0 = projects[0]
        let project1 = projects[1]

        return [
            ProjectTask(
                id: UUID(),
                projectId: project0.id,
                title: "Fix auth hydration bug",
                description: "User sessions not persisting across cold starts in the pod app",
                status: .done,
                stage: .done,
                assigneeId: mauiId,
                dueDate: Date().addingTimeInterval(-86400),
                priority: .high,
                tags: ["bug", "auth", "ios"]
            ),
            ProjectTask(
                id: UUID(),
                projectId: project0.id,
                title: "Implement push notifications",
                description: "Add APNS support for mentions, approvals, and alerts",
                status: .inProgress,
                stage: .dev,
                assigneeId: mauiId,
                dueDate: Date().addingTimeInterval(86400 * 7),
                priority: .high,
                tags: ["ios", "notifications", "apns"]
            ),
            ProjectTask(
                id: UUID(),
                projectId: project1.id,
                title: "Design DDS schema",
                description: "Finalize the protobuf schemas for DDS topic definitions",
                status: .inProgress,
                stage: .verify,
                assigneeId: auroraId,
                dueDate: Date().addingTimeInterval(86400 * 5),
                priority: .critical,
                tags: ["dds", "protobuf", "nats"]
            ),
            ProjectTask(
                id: UUID(),
                projectId: UUID(),
                title: "Finalize standards table schema",
                description: "Standards DB migration blocked — need Aurora's sign-off on the schema",
                status: .review,
                stage: .plan,
                assigneeId: nil,
                dueDate: Date().addingTimeInterval(86400 * 2),
                priority: .medium,
                tags: ["database", "standards"]
            ),
            ProjectTask(
                id: UUID(),
                projectId: UUID(),
                title: "Write Q1 metrics report",
                description: "Compile experiment results, trading performance, and agent uptime stats",
                status: .todo,
                stage: .plan,
                assigneeId: chiefId,
                dueDate: Date().addingTimeInterval(86400 * 2),
                priority: .medium,
                tags: ["report", "metrics", "quarterly"]
            ),
            ProjectTask(
                id: UUID(),
                projectId: project0.id,
                title: "Add channel search",
                description: "Full-text search across all channels with date filters",
                status: .todo,
                stage: .dev,
                assigneeId: mauiId,
                dueDate: Date().addingTimeInterval(86400 * 21),
                priority: .medium,
                tags: ["search", "chat", "ux"]
            )
        ]
    }()
}
