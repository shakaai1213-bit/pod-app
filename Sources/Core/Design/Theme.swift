import SwiftUI

// MARK: - Theme

/// Design system spacing, radii, animation, and shadow tokens
struct Theme {
    // MARK: Spacing (8pt grid)
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    // MARK: Corner Radii
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusPill: CGFloat = 999

    // MARK: Animation
    static let springBounce: CGFloat = 0.3
    static let springResponse: Double = 0.4
    static let durationDefault: Double = 0.2
    static let durationFast: Double = 0.15
    static let durationSlow: Double = 0.3

    // MARK: Shadows
    struct ShadowConfig {
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        let opacity: CGFloat

        static let small = ShadowConfig(radius: 4, x: 0, y: 2, opacity: 0.1)
        static let medium = ShadowConfig(radius: 8, x: 0, y: 4, opacity: 0.15)
        static let large = ShadowConfig(radius: 16, x: 0, y: 8, opacity: 0.2)
        static let glow = ShadowConfig(radius: 12, x: 0, y: 0, opacity: 0.3)
    }

    // MARK: - Surface & Text (back-compat for podApp.swift)

    static let surface: Color = AppColors.backgroundSecondary
    static let primaryText: Color = AppColors.textPrimary
    static let inverseText: Color = AppColors.textPrimary
    static let errorColor: Color = AppColors.accentDanger
    static let glow: Color = AppColors.accentElectric.opacity(0.4)
}

// MARK: - View Helpers

extension View {
    func podCard(padding: CGFloat = Theme.md) -> some View {
        self
            .padding(padding)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .shadow(
                color: .black.opacity(Theme.ShadowConfig.small.opacity),
                radius: Theme.ShadowConfig.small.radius,
                x: Theme.ShadowConfig.small.x,
                y: Theme.ShadowConfig.small.y
            )
    }

    func podGlow(color: Color = AppColors.accentElectric) -> some View {
        self.shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 0)
    }

    func podShadow(_ config: Theme.ShadowConfig) -> some View {
        self.shadow(
            color: .black.opacity(config.opacity),
            radius: config.radius,
            x: config.x,
            y: config.y
        )
    }
}

// MARK: - Shared Review Cards

enum PodReviewActionStyle: Sendable, Hashable {
    case primary
    case success
    case warning
    case destructive
    case neutral

    var color: Color {
        switch self {
        case .primary: return AppColors.accentElectric
        case .success: return AppColors.accentSuccess
        case .warning: return AppColors.accentWarning
        case .destructive: return AppColors.accentDanger
        case .neutral: return AppColors.textSecondary
        }
    }
}

struct PodReviewAction: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let style: PodReviewActionStyle
    let isDisabled: Bool

    init(
        id: String,
        title: String,
        systemImage: String,
        style: PodReviewActionStyle = .primary,
        isDisabled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isDisabled = isDisabled
    }
}

struct PodReviewItem: Identifiable {
    let id: String
    let eyebrow: String
    let title: String
    let detail: String?
    let status: String
    let statusColor: Color
    let provenance: [String]
    let traceId: String?
    let artifactHash: String?
    let actions: [PodReviewAction]

    init(
        id: String,
        eyebrow: String,
        title: String,
        detail: String? = nil,
        status: String,
        statusColor: Color = AppColors.accentElectric,
        provenance: [String] = [],
        traceId: String? = nil,
        artifactHash: String? = nil,
        actions: [PodReviewAction] = []
    ) {
        self.id = id
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.status = status
        self.statusColor = statusColor
        self.provenance = provenance
        self.traceId = traceId
        self.artifactHash = artifactHash
        self.actions = actions
    }
}

struct PodReviewCard: View {
    let item: PodReviewItem
    var isBusy: Bool = false
    var onAction: (PodReviewAction) -> Void = { _ in }
    var onOpenTrace: ((String) -> Void)?
    @State private var presentedTrace: PodTraceSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(item.statusColor)

                Spacer(minLength: 8)
            }

            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = item.detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.provenance.isEmpty || item.artifactHash != nil || item.traceId != nil {
                FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                    ForEach(item.provenance, id: \.self) { value in
                        reviewPill(value)
                    }
                    if let artifactHash = item.artifactHash, !artifactHash.isEmpty {
                        reviewPill("sha \(String(artifactHash.prefix(12)))")
                    }
                    if let traceId = item.traceId, !traceId.isEmpty {
                        Button {
                            if let onOpenTrace {
                                onOpenTrace(traceId)
                            } else {
                                presentedTrace = PodTraceSelection(traceId: traceId)
                            }
                        } label: {
                            Label(String(traceId.prefix(12)), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColors.accentElectric)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppColors.accentElectric.opacity(0.10))
                        .clipShape(Capsule())
                    }
                }
            }

            HStack(alignment: .center, spacing: 8) {
                Label(item.status, systemImage: isBusy ? "clock.arrow.circlepath" : "checkmark.seal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.statusColor)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(item.statusColor.opacity(0.10))
                    .clipShape(Capsule())

                Spacer(minLength: 8)

                if !item.actions.isEmpty {
                    ForEach(visibleActions) { action in
                        compactActionButton(action)
                    }

                    if !overflowActions.isEmpty {
                        Menu {
                            ForEach(overflowActions) { action in
                                Button {
                                    onAction(action)
                                } label: {
                                    Label(action.title, systemImage: action.systemImage)
                                }
                                .disabled(action.isDisabled || isBusy)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 26, height: 24)
                                .background(AppColors.backgroundTertiary.opacity(0.75))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.statusColor.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.eyebrow), \(item.title), \(item.status)")
        .sheet(item: $presentedTrace) { selection in
            PodTraceEvidenceSheet(traceId: selection.traceId, artifactHash: item.artifactHash)
                .presentationDetents([.medium, .large])
        }
    }

    private func reviewPill(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }

    private var visibleActions: [PodReviewAction] {
        item.actions.count <= 2 ? item.actions : Array(item.actions.prefix(2))
    }

    private var overflowActions: [PodReviewAction] {
        item.actions.count <= 2 ? [] : Array(item.actions.dropFirst(2))
    }

    private func compactActionButton(_ action: PodReviewAction) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(action.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(action.style.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(action.style.color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(action.style.color.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(action.isDisabled || isBusy)
        .opacity(action.isDisabled || isBusy ? 0.45 : 1)
    }
}

private struct PodTraceSelection: Identifiable {
    let traceId: String
    var id: String { traceId }
}

private struct PodTraceEvidenceSheet: View {
    let traceId: String
    let artifactHash: String?
    @State private var model = PodTraceEvidenceModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    header

                    if model.isLoading && model.trace == nil {
                        loadingState
                    } else if let error = model.errorMessage {
                        errorState(error)
                    } else if let trace = model.trace {
                        traceSummary(trace)
                        if !trace.agentRuns.isEmpty {
                            section("Agent Runs", count: trace.agentRuns.count) {
                                ForEach(trace.agentRuns) { run in
                                    agentRunRow(run)
                                }
                            }
                        }
                        if !trace.computeRuns.isEmpty {
                            section("Compute Runs", count: trace.computeRuns.count) {
                                ForEach(trace.computeRuns) { run in
                                    computeRunRow(run)
                                }
                            }
                        }
                        if !trace.events.isEmpty {
                            section("Events", count: trace.events.count) {
                                ForEach(trace.events) { event in
                                    eventRow(event)
                                }
                            }
                        }
                        if !trace.chatMessages.isEmpty {
                            section("Chat", count: trace.chatMessages.count) {
                                ForEach(trace.chatMessages) { message in
                                    messageRow(message)
                                }
                            }
                        }
                        if !trace.notes.isEmpty {
                            section("Notes", count: trace.notes.count) {
                                ForEach(trace.notes) { note in
                                    noteRow(note)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.md)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Trace Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.load(traceId: traceId) }
                    } label: {
                        Image(systemName: model.isLoading ? "hourglass" : "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
            .task(id: traceId) {
                await model.load(traceId: traceId)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Label(String(traceId.prefix(20)), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                evidencePill("trace", color: AppColors.accentElectric)
                if let artifactHash, !artifactHash.isEmpty {
                    evidencePill("sha \(String(artifactHash.prefix(12)))", color: AppColors.accentSuccess)
                }
                if let trace = model.trace {
                    evidencePill("\(trace.agentRuns.count) runs", color: AppColors.accentAgent)
                    evidencePill("\(trace.computeRuns.count) compute", color: AppColors.accentWarning)
                    evidencePill("\(trace.events.count) events", color: AppColors.textSecondary)
                }
            }
        }
        .padding(Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private var loadingState: some View {
        HStack(spacing: Theme.xs) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading ORCA trace evidence...")
                .font(.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Label("Trace unavailable", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.accentWarning)
            Text(message)
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
            Button {
                Task { await model.load(traceId: traceId) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }

    private func traceSummary(_ trace: AgentRunTrace) -> some View {
        HStack(spacing: Theme.sm) {
            traceMetric("Runs", trace.agentRuns.count, AppColors.accentAgent)
            traceMetric("Compute", trace.computeRuns.count, AppColors.accentWarning)
            traceMetric("Events", trace.events.count, AppColors.accentElectric)
            traceMetric("Notes", trace.notes.count, AppColors.textSecondary)
        }
    }

    private func traceMetric(_ title: String, _ count: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppColors.textTertiary)
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.xs)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.textTertiary)
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentElectric)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.accentElectric.opacity(0.12))
                    .clipShape(Capsule())
                Spacer(minLength: 0)
            }
            content()
        }
    }

    private func agentRunRow(_ run: AgentRun) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.xs) {
                Text(run.runType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 8)
                evidencePill(run.status.rawValue, color: color(for: run.status.rawValue))
            }

            detailText(run.outcome ?? run.evidence ?? run.error ?? run.inputSummary)

            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                evidencePill(String(run.id.prefix(8)), color: AppColors.textSecondary)
                if let lane = run.workerLane ?? run.lane { evidencePill(lane, color: AppColors.accentAgent) }
                if let model = run.model { evidencePill(model, color: AppColors.accentElectric) }
                if let latency = run.latencyMs { evidencePill("\(latency)ms", color: AppColors.textSecondary) }
                evidencePill(run.updatedAt.formatted(date: .abbreviated, time: .shortened), color: AppColors.textSecondary)
            }

            if let artifacts = run.artifacts, !artifacts.isEmpty {
                artifactRows(artifacts)
            }

            if let summaries = model.artifactSummariesByRunId[run.id], !summaries.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(summaries.prefix(6)) { summary in
                        artifactSummaryRow(summary)
                    }
                }
            }
        }
        .padding(Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func computeRunRow(_ run: ComputeRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(run.taskHint.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 8)
                evidencePill(run.status, color: color(for: run.status))
            }
            detailText(run.outputPreview ?? run.error)
            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                evidencePill(run.route, color: AppColors.accentElectric)
                if let backend = run.backend ?? run.actualBackend { evidencePill(backend, color: AppColors.accentAgent) }
                if let model = run.model { evidencePill(model, color: AppColors.textSecondary) }
                if run.fallbackUsed { evidencePill("fallback", color: AppColors.accentWarning) }
                if let latency = run.latencyMs { evidencePill("\(latency)ms", color: AppColors.textSecondary) }
            }
        }
        .padding(Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func eventRow(_ event: AgentRunTraceEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(event.eventType.replacingOccurrences(of: "_", with: " "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
            detailText(event.message)
            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                if let source = event.source { evidencePill(source, color: AppColors.accentElectric) }
                if let lane = event.lane { evidencePill(lane, color: AppColors.accentAgent) }
                evidencePill(event.createdAt.formatted(date: .abbreviated, time: .shortened), color: AppColors.textSecondary)
            }
        }
        .padding(Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func messageRow(_ message: AgentRunTraceChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.content)
                .font(.caption)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(4)
            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                evidencePill(message.messageType, color: AppColors.accentElectric)
                if let source = message.source { evidencePill(source, color: AppColors.accentAgent) }
                if let state = message.responseState { evidencePill(state, color: AppColors.textSecondary) }
            }
        }
        .padding(Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func noteRow(_ note: TicketNoteRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
            detailText(note.body)
            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                evidencePill(note.noteType, color: AppColors.accentElectric)
                if let owner = note.owner { evidencePill(owner, color: AppColors.accentAgent) }
                if let signState = note.signState { evidencePill(signState, color: AppColors.textSecondary) }
            }
        }
        .padding(Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func artifactRows(_ artifacts: [String: AgentRunJSONValue]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(artifacts.keys.sorted().prefix(6), id: \.self) { key in
                HStack(alignment: .top, spacing: Theme.xs) {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(AppColors.accentSuccess)
                    Text(key)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer(minLength: 8)
                    Text(artifacts[key]?.displayValue ?? "")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 2)
    }

    private func artifactSummaryRow(_ summary: AgentRunArtifactSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.xs) {
                Image(systemName: summary.safeToPreview ? "doc.text.magnifyingglass" : "lock.doc")
                    .font(.caption2)
                    .foregroundStyle(summary.safeToPreview ? AppColors.accentSuccess : AppColors.accentWarning)
                Text(summary.key)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let size = summary.sizeBytes {
                    Text("\(size) bytes")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            detailText(summary.preview ?? summary.reason ?? summary.value)
        }
    }

    @ViewBuilder
    private func detailText(_ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(value)
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func evidencePill(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func color(for status: String) -> Color {
        switch status.lowercased() {
        case "completed", "accepted", "done", "success", "succeeded":
            return AppColors.accentSuccess
        case "failed", "error", "rejected":
            return AppColors.accentDanger
        case "running", "queued", "waiting_for_human", "needs_changes":
            return AppColors.accentWarning
        default:
            return AppColors.textSecondary
        }
    }
}

@Observable
private final class PodTraceEvidenceModel {
    var trace: AgentRunTrace?
    var artifactSummariesByRunId: [String: [AgentRunArtifactSummary]] = [:]
    var isLoading = false
    var errorMessage: String?

    @MainActor
    func load(traceId: String) async {
        let cleanTraceId = traceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTraceId.isEmpty else {
            errorMessage = "Trace id is empty."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let encodedTraceId = cleanTraceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            errorMessage = "Trace id could not be encoded."
            return
        }

        do {
            let dto: AgentRunTraceDTO = try await APIClient.shared.get(path: "/api/v1/agent-runs/traces/\(encodedTraceId)")
            let loadedTrace = dto.toDomain()
            trace = loadedTrace
            await loadArtifactSummaries(for: loadedTrace.agentRuns)
        } catch let apiError as APIError {
            errorMessage = apiError.message
        } catch {
            errorMessage = "Couldn't load ORCA trace evidence."
        }
    }

    @MainActor
    private func loadArtifactSummaries(for runs: [AgentRun]) async {
        artifactSummariesByRunId = [:]
        for run in runs {
            do {
                let dtos: [AgentRunArtifactSummaryDTO] = try await APIClient.shared.get(path: "/api/v1/agent-runs/\(run.id)/artifacts")
                artifactSummariesByRunId[run.id] = dtos.map { $0.toDomain() }
            } catch {
                artifactSummariesByRunId[run.id] = []
            }
        }
    }
}
