import Foundation

enum OrcaConsoleServiceError: Error, LocalizedError {
    case missingCredential
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingCredential: return "ORCA access is not configured."
        case .invalidResponse: return "ORCA returned an unreadable response."
        case let .httpStatus(code): return "ORCA returned HTTP \(code)."
        }
    }
}

actor OrcaConsoleService {
    private let serverURL: URL
    private let tokenStore: any RuntimeTokenStoring
    private let authService: OrcaNativeAuthService?
    private let deviceID: String
    private let session: URLSession

    init(
        serverURL: URL,
        tokenStore: any RuntimeTokenStoring,
        authService: OrcaNativeAuthService? = nil,
        deviceID: String = OrcaDeviceIdentity.current(),
        session: URLSession = .shared
    ) {
        self.serverURL = serverURL
        self.tokenStore = tokenStore
        self.authService = authService
        self.deviceID = deviceID
        self.session = session
    }

    func snapshot(for section: ConsoleSection) async throws -> ConsoleSectionSnapshot {
        switch section {
        case .overview: return try await overviewSnapshot()
        case .conversations: return .empty(.conversations)
        case .work: return try await workSnapshot()
        case .fund: return try await fundSnapshot()
        case .crew: return try await crewSnapshot()
        case .knowledge: return try await knowledgeSnapshot()
        case .lab: return try await labSnapshot()
        case .runtime: return try await runtimeSnapshot()
        case .maker: return try await makerSnapshot()
        }
    }

    func agentProfiles() async throws -> [AgentProfile] {
        let value = try await get("/api/v1/management/agents")
        return collection(value, keys: ["agents"]).compactMap { object in
            guard let id = field(object, keys: ["agent_name", "slug"])?.lowercased(),
                  !id.isEmpty else { return nil }
            return AgentProfile.fromRuntime(
                id: id,
                name: field(object, keys: ["display_name", "agent_name"]),
                role: field(object, keys: ["title"])
            )
        }
    }

    private func overviewSnapshot() async throws -> ConsoleSectionSnapshot {
        async let inbox = get("/api/v1/control-room/captain-inbox")
        async let health = get("/api/v1/control-room/central-agent-health")
        async let boards = get("/api/v1/boards")
        async let tickets = get("/api/v1/tickets")
        async let agents = get("/api/v1/agents")
        async let startup = get("/api/v1/startup/status")
        let values = try await (inbox, health, boards, tickets, agents, startup)

        let metrics = [
            metric("attention", "Attention", integer(values.0, key: "count")),
            metric("boards", "Boards", integer(values.2, key: "total")),
            metric("tickets", "Loaded Tickets", rootCount(values.3)),
            metric("agents", "Agents", integer(values.4, key: "total")),
            ConsoleMetric(
                id: "agent-health",
                label: "Agent Health",
                value: text(values.1, key: "status") ?? "Unknown",
                status: text(values.1, key: "status")
            ),
            ConsoleMetric(
                id: "startup",
                label: "Platform",
                value: bool(values.5, key: "ok") == true ? "Ready" : "Attention",
                status: bool(values.5, key: "ok") == true ? "ok" : "attention"
            ),
        ]
        return ConsoleSectionSnapshot(
            section: .overview,
            metrics: metrics,
            records: records(
                from: values.0,
                collectionKeys: ["items"],
                group: "Attention",
                titleKeys: ["title", "summary"],
                subtitleKeys: ["summary", "source"],
                statusKeys: ["severity", "status"],
                limit: 40
            ),
            sources: [
                "/api/v1/control-room/captain-inbox",
                "/api/v1/control-room/central-agent-health",
                "/api/v1/startup/status",
            ],
            updatedAt: Date()
        )
    }

    private func workSnapshot() async throws -> ConsoleSectionSnapshot {
        async let boards = get("/api/v1/boards")
        async let projects = get("/api/v1/projects/")
        async let tickets = get("/api/v1/tickets")
        async let inbox = get("/api/v1/control-room/captain-inbox")
        let values = try await (boards, projects, tickets, inbox)
        let approvals = collection(values.3, keys: ["items"]).filter {
            field($0, keys: ["kind"])?.lowercased() == "approval"
        }

        var output = records(
            from: values.0,
            collectionKeys: ["items"],
            group: "Boards",
            titleKeys: ["name", "slug"],
            subtitleKeys: ["objective", "description"],
            statusKeys: ["status", "priority"],
            limit: 100
        )
        output += records(
            from: values.1,
            collectionKeys: ["items", "projects"],
            group: "Projects",
            titleKeys: ["name", "title"],
            subtitleKeys: ["objective", "description"],
            statusKeys: ["status", "state"],
            limit: 80
        )
        output += recordObjects(
            approvals,
            group: "Approvals",
            titleKeys: ["title", "summary"],
            subtitleKeys: ["summary", "agent_slug"],
            statusKeys: ["severity", "status"],
            limit: 40
        )
        output += records(
            from: values.2,
            collectionKeys: [],
            group: "Tickets",
            titleKeys: ["title"],
            subtitleKeys: ["next_action", "blocked_on", "desired_outcome"],
            statusKeys: ["flow_state", "status", "priority"],
            limit: 100
        )

        return ConsoleSectionSnapshot(
            section: .work,
            metrics: [
                metric("boards", "Boards", integer(values.0, key: "total")),
                metric("projects", "Projects", rootCount(values.1, collectionKeys: ["items", "projects"])),
                metric("tickets", "Loaded Tickets", rootCount(values.2)),
                ConsoleMetric(id: "approvals", label: "Approvals", value: "\(approvals.count)", status: approvals.isEmpty ? "ok" : "attention"),
            ],
            records: output,
            sources: ["/api/v1/boards", "/api/v1/projects/", "/api/v1/tickets", "/api/v1/control-room/captain-inbox"],
            updatedAt: Date()
        )
    }

    private func crewSnapshot() async throws -> ConsoleSectionSnapshot {
        async let management = get("/api/v1/management/agents")
        async let planning = get("/api/v1/planning/fleet")
        let values = try await (management, planning)
        let agents = records(
            from: values.0,
            collectionKeys: ["agents"],
            group: "Crew",
            titleKeys: ["display_name", "agent_name"],
            subtitleKeys: ["focus", "plan", "title"],
            statusKeys: ["lifecycle_status", "wake_status"],
            limit: 30
        )
        return ConsoleSectionSnapshot(
            section: .crew,
            metrics: [
                metric("complete", "Complete Profiles", integer(values.0, key: "complete_count")),
                metric("unknown", "Needs Attention", integer(values.0, key: "unknown_count"), status: "attention"),
                metric("planning", "Planning Lanes", rootCount(values.1, collectionKeys: ["agents"])),
            ],
            records: agents,
            sources: ["/api/v1/management/agents", "/api/v1/planning/fleet"],
            updatedAt: Date()
        )
    }

    private func knowledgeSnapshot() async throws -> ConsoleSectionSnapshot {
        async let packets = get("/api/v1/knowledge/packets")
        async let research = get("/api/v1/research/requests")
        let values = try await (packets, research)
        var output = records(
            from: values.0,
            collectionKeys: [],
            group: "Knowledge",
            titleKeys: ["title"],
            subtitleKeys: ["source_ref", "evidence_ref", "source_type"],
            statusKeys: ["access_lane"],
            limit: 100
        )
        output += records(
            from: values.1,
            collectionKeys: ["items", "requests"],
            group: "Research",
            titleKeys: ["title", "question", "topic"],
            subtitleKeys: ["objective", "requester", "owner_agent"],
            statusKeys: ["status", "state"],
            limit: 100
        )
        return ConsoleSectionSnapshot(
            section: .knowledge,
            metrics: [
                metric("packets", "Knowledge Packets", rootCount(values.0)),
                metric("research", "Research Requests", rootCount(values.1, collectionKeys: ["items", "requests"])),
            ],
            records: output,
            sources: ["/api/v1/knowledge/packets", "/api/v1/research/requests"],
            updatedAt: Date()
        )
    }

    private func labSnapshot() async throws -> ConsoleSectionSnapshot {
        let value = try await get("/api/v1/lab/sections")
        return ConsoleSectionSnapshot(
            section: .lab,
            metrics: [metric("sections", "System Layers", rootCount(value, collectionKeys: ["sections"]))],
            records: records(
                from: value,
                collectionKeys: ["sections"],
                group: "Lab",
                titleKeys: ["layer", "title", "name"],
                subtitleKeys: ["projects", "summary"],
                statusKeys: ["status"],
                limit: 50
            ),
            sources: ["/api/v1/lab/sections"],
            updatedAt: Date()
        )
    }

    private func runtimeSnapshot() async throws -> ConsoleSectionSnapshot {
        async let startup = get("/api/v1/startup/status")
        async let nats = get("/api/v1/nats/health")
        async let registry = get("/api/v1/runtime-registry")
        let values = try await (startup, nats, registry)
        let summary = values.2.objectValue?["summary"]?.objectValue
        let runtimeTotal = summary?["total"]?.displayValue
        return ConsoleSectionSnapshot(
            section: .runtime,
            metrics: [
                ConsoleMetric(id: "platform", label: "Platform", value: bool(values.0, key: "ok") == true ? "Ready" : "Attention", status: bool(values.0, key: "ok") == true ? "ok" : "attention"),
                ConsoleMetric(id: "nats", label: "NATS", value: text(values.1, key: "status") ?? "Unknown", status: text(values.1, key: "status")),
                ConsoleMetric(id: "registry", label: "Registered Runtimes", value: runtimeTotal ?? "-", status: nil),
            ],
            records: records(
                from: values.2,
                collectionKeys: ["items"],
                group: "Runtime Registry",
                titleKeys: ["name"],
                subtitleKeys: ["kind", "owner", "script_path"],
                statusKeys: ["status", "classification"],
                limit: 160
            ),
            sources: ["/api/v1/startup/status", "/api/v1/nats/health", "/api/v1/runtime-registry"],
            updatedAt: Date()
        )
    }

    private func makerSnapshot() async throws -> ConsoleSectionSnapshot {
        let value = try await get("/api/v1/skill-lab")
        let counts = value.objectValue?["counts"]?.objectValue
        return ConsoleSectionSnapshot(
            section: .maker,
            metrics: [
                ConsoleMetric(id: "skills", label: "Skills", value: counts?["skills"]?.displayValue ?? "-", status: nil),
                ConsoleMetric(id: "evals", label: "Evaluation Cases", value: counts?["eval_cases"]?.displayValue ?? "-", status: nil),
                ConsoleMetric(id: "promotions", label: "Pending Promotions", value: counts?["pending_promotions"]?.displayValue ?? "-", status: nil),
            ],
            records: records(
                from: value,
                collectionKeys: ["skills"],
                group: "Skills",
                titleKeys: ["title", "slug"],
                subtitleKeys: ["purpose", "domain", "owner_agent"],
                statusKeys: ["status"],
                limit: 100
            ),
            sources: ["/api/v1/skill-lab"],
            updatedAt: Date()
        )
    }

    private func fundSnapshot() async throws -> ConsoleSectionSnapshot {
        let value = try await get("/api/v1/fund/landing")
        let fields = value.objectValue?.keys.sorted().compactMap { key -> ConsoleField? in
            guard let display = value.objectValue?[key]?.displayValue else { return nil }
            return ConsoleField(label: key.replacingOccurrences(of: "_", with: " ").capitalized, value: display)
        } ?? []
        return ConsoleSectionSnapshot(
            section: .fund,
            metrics: [],
            records: [ConsoleRecord(id: "fund-landing", title: "Fund Operating View", subtitle: "ORCA protected read model", status: "protected", group: "Fund", fields: fields)],
            sources: ["/api/v1/fund/landing"],
            updatedAt: Date()
        )
    }

    private func get(_ path: String) async throws -> ConsoleJSON {
        guard OrcaServerOrigin.isApproved(serverURL),
              let serverOrigin = OrcaServerOrigin.normalized(serverURL) else {
            throw OrcaNativeAuthError.unapprovedOrigin
        }
        let token: String?
        if let authService {
            token = try await authService.validAccessToken()
        } else {
            token = try await tokenStore.loadToken(for: serverOrigin)
        }
        guard let token, !token.isEmpty else {
            throw OrcaConsoleServiceError.missingCredential
        }
        guard let url = URL(string: path, relativeTo: serverURL)?.absoluteURL,
              OrcaServerOrigin.normalized(url) == serverOrigin else {
            throw OrcaConsoleServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-ORCA-Device-ID")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrcaConsoleServiceError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw OrcaConsoleServiceError.httpStatus(http.statusCode)
        }
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try ConsoleJSON(foundationValue: value)
    }

    private func metric(
        _ id: String,
        _ label: String,
        _ value: Int?,
        status: String? = nil
    ) -> ConsoleMetric {
        ConsoleMetric(id: id, label: label, value: value.map(String.init) ?? "-", status: status)
    }

    private func integer(_ value: ConsoleJSON, key: String) -> Int? {
        guard let raw = value.objectValue?[key] else { return nil }
        if case let .number(number) = raw { return Int(number) }
        return Int(raw.displayValue ?? "")
    }

    private func bool(_ value: ConsoleJSON, key: String) -> Bool? {
        guard case let .bool(result) = value.objectValue?[key] else { return nil }
        return result
    }

    private func text(_ value: ConsoleJSON, key: String) -> String? {
        value.objectValue?[key]?.displayValue
    }

    private func rootCount(_ value: ConsoleJSON, collectionKeys: [String] = []) -> Int {
        collection(value, keys: collectionKeys).count
    }

    private func collection(_ value: ConsoleJSON, keys: [String]) -> [[String: ConsoleJSON]] {
        if let array = value.arrayValue {
            return array.compactMap(\.objectValue)
        }
        guard let object = value.objectValue else { return [] }
        for key in keys {
            if let array = object[key]?.arrayValue {
                return array.compactMap(\.objectValue)
            }
        }
        return []
    }

    private func records(
        from value: ConsoleJSON,
        collectionKeys: [String],
        group: String,
        titleKeys: [String],
        subtitleKeys: [String],
        statusKeys: [String],
        limit: Int
    ) -> [ConsoleRecord] {
        recordObjects(
            collection(value, keys: collectionKeys),
            group: group,
            titleKeys: titleKeys,
            subtitleKeys: subtitleKeys,
            statusKeys: statusKeys,
            limit: limit
        )
    }

    private func recordObjects(
        _ objects: [[String: ConsoleJSON]],
        group: String,
        titleKeys: [String],
        subtitleKeys: [String],
        statusKeys: [String],
        limit: Int
    ) -> [ConsoleRecord] {
        Array(objects.prefix(limit).enumerated()).map { index, object in
            let title = field(object, keys: titleKeys) ?? "Untitled"
            let subtitle = field(object, keys: subtitleKeys)
            let status = field(object, keys: statusKeys)
            let id = field(object, keys: ["id", "slug", "key", "agent_id", "agent_name"])
                ?? "\(group.lowercased())-\(index)"
            let detailKeys = [
                "priority", "status", "flow_state", "owner_agent", "assignee_agent_id",
                "runtime_host", "provider", "focus", "load", "plan", "dispatch",
                "source_ref", "evidence_ref", "created_at", "updated_at",
            ]
            let fields = detailKeys.compactMap { key -> ConsoleField? in
                guard let value = object[key]?.displayValue, !value.isEmpty else { return nil }
                return ConsoleField(
                    label: key.replacingOccurrences(of: "_", with: " ").capitalized,
                    value: value
                )
            }
            return ConsoleRecord(
                id: id,
                title: title,
                subtitle: subtitle == title ? nil : subtitle,
                status: status,
                group: group,
                fields: fields
            )
        }
    }

    private func field(_ object: [String: ConsoleJSON], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.displayValue, !value.isEmpty { return value }
        }
        return nil
    }
}
