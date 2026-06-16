import SwiftUI
import PhotosUI

// MARK: - Mode

private enum MakerMode: String, CaseIterable {
    case idea     = "Idea"
    case pipeline = "Pipeline"
    case image    = "Image"
}

// MARK: - Pipeline Models

struct ReadyIdea: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String?
    let discovery: [String: String?]?
    let assessment: [String: String?]?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, summary, discovery, assessment
        case createdAt = "created_at"
    }

    var scope: String? { discovery?["scope"] ?? nil }
    var effortEstimate: String? { discovery?["effort_estimate"] ?? nil }
    var rationale: String? { assessment?["rationale"] ?? nil }
}

struct PromoteResponse: Decodable {
    let id: String
    let status: String
    let convertedTo: [String: String]?
    enum CodingKeys: String, CodingKey {
        case id, status
        case convertedTo = "converted_to"
    }
}

// MARK: - Image Models

private struct MakerTransformRequest: Encodable {
    let imageB64: String
    let instruction: String
    let width: Int
    let height: Int

    enum CodingKeys: String, CodingKey {
        case imageB64 = "image_b64"
        case instruction
        case width
        case height
    }
}

private struct MakerTransformResponse: Decodable {
    let resultImageB64: String
    let promptUsed: String
    let generationTimeMs: Int

    enum CodingKeys: String, CodingKey {
        case resultImageB64 = "result_image_b64"
        case promptUsed = "prompt_used"
        case generationTimeMs = "generation_time_ms"
    }
}

// MARK: - Idea Models

private struct IdeaIntakeRequest: Encodable {
    let kind: String
    let title: String
    let summary: String?
    let source: String
    let ownerLane: String
    let riskLevel: String
    let provenance: [String: String]

    enum CodingKeys: String, CodingKey {
        case kind, title, summary, source, provenance
        case ownerLane  = "owner_lane"
        case riskLevel  = "risk_level"
    }
}

private struct IdeaIntakeResponse: Decodable {
    let id: String
    let kind: String
    let status: String
}

// MARK: - ViewModel

@Observable
@MainActor
final class MakerViewModel {
    // Image mode
    var pickerItem: PhotosPickerItem?
    var sourceImage: UIImage?
    var resultImage: UIImage?
    var instruction: String = ""
    var isTransforming = false
    var imageError: String?
    var promptUsed: String?
    var generationTimeMs: Int?

    var canTransform: Bool {
        sourceImage != nil && !instruction.trimmingCharacters(in: .whitespaces).isEmpty && !isTransforming
    }

    // Idea mode
    var ideaTitle: String = ""
    var ideaNote: String = ""
    var ideaHint: String = ""
    var isSubmittingIdea = false
    var ideaSubmitMessage: String?
    var ideaError: String?

    var canSubmitIdea: Bool {
        !ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmittingIdea
    }

    // Pipeline mode
    var readyIdeas: [ReadyIdea] = []
    var isLoadingPipeline = false
    var pipelineError: String?
    var promotingIds: Set<String> = []
    var promoteResults: [String: String] = [:]   // id → success message
    var promoteErrors: [String: String] = [:]    // id → error message

    // MARK: Image

    func loadPickedItem() async {
        guard let item = pickerItem else { return }
        resultImage = nil
        imageError = nil
        promptUsed = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            imageError = "Couldn't load image."
            return
        }
        sourceImage = image
    }

    func transform() async {
        guard let source = sourceImage, !isTransforming else { return }
        let text = instruction.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        isTransforming = true
        imageError = nil
        resultImage = nil
        promptUsed = nil
        generationTimeMs = nil
        defer { isTransforming = false }

        guard let jpeg = source.jpegData(compressionQuality: 0.82) else {
            imageError = "Couldn't encode image."
            return
        }
        let b64 = jpeg.base64EncodedString()
        let body = MakerTransformRequest(imageB64: b64, instruction: text, width: 512, height: 512)

        do {
            let response: MakerTransformResponse = try await makerPost(body: body)
            guard let resultData = Data(base64Encoded: response.resultImageB64),
                  let img = UIImage(data: resultData) else {
                imageError = "Backend returned unreadable image."
                return
            }
            resultImage = img
            promptUsed = response.promptUsed
            generationTimeMs = response.generationTimeMs
        } catch {
            imageError = error.localizedDescription
        }
    }

    func resetImage() {
        pickerItem = nil
        sourceImage = nil
        resultImage = nil
        instruction = ""
        imageError = nil
        promptUsed = nil
        generationTimeMs = nil
    }

    // MARK: Idea

    func submitIdea() async {
        let title = ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isSubmittingIdea = true
        ideaError = nil
        ideaSubmitMessage = nil
        defer { isSubmittingIdea = false }

        var provenance: [String: String] = ["submitted_via": "pod.maker.idea"]
        let hint = ideaHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hint.isEmpty { provenance["hint"] = hint }

        let note = ideaNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = note.isEmpty ? nil : note

        let body = IdeaIntakeRequest(
            kind: "idea_intake",
            title: title,
            summary: summary,
            source: "pod.maker.idea",
            ownerLane: "backbone",
            riskLevel: "low",
            provenance: provenance
        )

        do {
            let response: IdeaIntakeResponse = try await APIClient.shared.post(
                path: "/api/v1/schoolhouse/suggestions",
                body: body
            )
            ideaSubmitMessage = "Idea queued — ID \(String(response.id.prefix(8))). Team picks it up next cycle."
            ideaTitle = ""
            ideaNote = ""
            ideaHint = ""
        } catch {
            ideaError = error.localizedDescription
        }
    }

    func resetIdea() {
        ideaTitle = ""
        ideaNote = ""
        ideaHint = ""
        ideaError = nil
        ideaSubmitMessage = nil
    }

    // MARK: Pipeline

    func loadReadyIdeas() async {
        guard !isLoadingPipeline else { return }
        isLoadingPipeline = true
        pipelineError = nil
        defer { isLoadingPipeline = false }
        do {
            let ideas: [ReadyIdea] = try await APIClient.shared.get(
                path: "/api/v1/schoolhouse/ideas/ready"
            )
            readyIdeas = ideas
        } catch {
            pipelineError = error.localizedDescription
        }
    }

    private struct EmptyBody: Encodable {}

    func promoteIdea(id: String) async {
        guard !promotingIds.contains(id) else { return }
        promotingIds.insert(id)
        promoteErrors[id] = nil
        defer { promotingIds.remove(id) }
        do {
            let result: PromoteResponse = try await APIClient.shared.post(
                path: "/api/v1/schoolhouse/ideas/\(id)/promote",
                body: EmptyBody()
            )
            let ticketId = result.convertedTo?["id"] ?? "?"
            promoteResults[id] = "Promoted → ticket \(String(ticketId.prefix(8)))"
            readyIdeas.removeAll { $0.id == id }
        } catch {
            promoteErrors[id] = error.localizedDescription
        }
    }

    // MARK: Private

    private func makerPost<T: Decodable>(body: some Encodable) async throws -> T {
        let token = await APIClient.shared.currentToken()
        guard let url = URL(string: "\(AppState.backendURL)/api/v1/maker/transform") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 100
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? "no body"
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - View

struct MakerView: View {
    @State private var model = MakerViewModel()
    @State private var mode: MakerMode = .idea

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    modePicker
                    switch mode {
                    case .image:    imageContent
                    case .idea:     ideaContent
                    case .pipeline: pipelineContent
                    }
                }
                .padding(.horizontal, Theme.md)
                .padding(.top, Theme.lg)
                .padding(.bottom, Theme.xxl)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Maker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .onChange(of: model.pickerItem) { _, _ in
            Task { await model.loadPickedItem() }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .pipeline && model.readyIdeas.isEmpty && !model.isLoadingPipeline {
                Task { await model.loadReadyIdeas() }
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(MakerMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if mode == .image && (model.sourceImage != nil || model.resultImage != nil) {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reset") { model.resetImage() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Image Mode

    private var imageContent: some View {
        VStack(alignment: .leading, spacing: Theme.lg) {
            imageHeader
            imageSection
            if model.sourceImage != nil {
                instructionSection
                transformButton
            }
            if let error = model.imageError {
                errorBanner(error)
            }
            if model.resultImage != nil {
                resultSection
            }
        }
    }

    private var imageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Image Maker")
                .podTextStyle(.title1, color: AppColors.textPrimary)
            Text("Pick an image, give an instruction, transform it via SDXL Turbo.")
                .podTextStyle(.body, color: AppColors.textSecondary)
        }
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("SOURCE IMAGE")
                .podTextStyle(.label, color: AppColors.textTertiary)

            if let image = model.sourceImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))

                    PhotosPicker(selection: $model.pickerItem, matching: .images) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
            } else {
                PhotosPicker(selection: $model.pickerItem, matching: .images) {
                    imagePlaceholder
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var imagePlaceholder: some View {
        VStack(spacing: Theme.sm) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(makerPurple)

            Text("Tap to pick a photo")
                .podTextStyle(.body, color: AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(makerPurple.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("INSTRUCTION")
                .podTextStyle(.label, color: AppColors.textTertiary)

            TextField("e.g. make it look like a watercolor painting", text: $model.instruction, axis: .vertical)
                .lineLimit(3...5)
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(model.instruction.isEmpty ? AppColors.border : makerPurple.opacity(0.5), lineWidth: 1)
                )
                .foregroundStyle(AppColors.textPrimary)
                .font(.body)
        }
    }

    private var transformButton: some View {
        Button {
            Task { await model.transform() }
        } label: {
            HStack(spacing: Theme.sm) {
                if model.isTransforming {
                    ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(0.85)
                    Text("Transforming…").font(.body.bold()).foregroundStyle(.white)
                } else {
                    Image(systemName: "wand.and.sparkles").font(.system(size: 16, weight: .semibold))
                    Text("Transform").font(.body.bold())
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.sm + 2)
            .background(model.canTransform ? makerPurple : AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        }
        .buttonStyle(.plain)
        .disabled(!model.canTransform)
        .animation(.easeInOut(duration: 0.2), value: model.isTransforming)
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Text("RESULT").podTextStyle(.label, color: AppColors.textTertiary)
                Spacer()
                if let ms = model.generationTimeMs {
                    Text("\(ms)ms").font(.caption2.monospacedDigit()).foregroundStyle(AppColors.textTertiary)
                }
            }

            if let result = model.resultImage {
                Image(uiImage: result)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .strokeBorder(makerPurple.opacity(0.3), lineWidth: 1)
                    )
                    .contextMenu {
                        Button {
                            UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
                        } label: {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                    }
            }

            if let prompt = model.promptUsed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROMPT USED").podTextStyle(.label, color: AppColors.textTertiary)
                    Text(prompt).podTextStyle(.caption, color: AppColors.textSecondary)
                }
                .padding(Theme.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    // MARK: - Idea Mode

    private var ideaContent: some View {
        VStack(alignment: .leading, spacing: Theme.lg) {
            ideaHeader
            ideaTitleSection
            ideaNoteSection
            ideaHintSection
            ideaSubmitButton
            if let msg = model.ideaSubmitMessage {
                successBanner(msg)
            }
            if let err = model.ideaError {
                errorBanner(err)
            }
            ideaFooter
        }
    }

    private var ideaHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Idea Maker")
                .podTextStyle(.title1, color: AppColors.textPrimary)
            Text("Type a raw idea. The team pulls it apart — assessment, discovery, then a project and DDS draft if it's real.")
                .podTextStyle(.body, color: AppColors.textSecondary)
        }
    }

    private var ideaTitleSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("IDEA")
                .podTextStyle(.label, color: AppColors.textTertiary)

            TextField("One-line: what's the idea?", text: $model.ideaTitle)
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(model.ideaTitle.isEmpty ? AppColors.border : makerPurple.opacity(0.5), lineWidth: 1)
                )
                .foregroundStyle(AppColors.textPrimary)
                .font(.body)
        }
    }

    private var ideaNoteSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("NOTES (optional)")
                .podTextStyle(.label, color: AppColors.textTertiary)

            TextField(
                "Context, motivation, rough shape — anything that helps the team assess it.",
                text: $model.ideaNote,
                axis: .vertical
            )
            .lineLimit(4...8)
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(model.ideaNote.isEmpty ? AppColors.border : makerPurple.opacity(0.3), lineWidth: 1)
            )
            .foregroundStyle(AppColors.textPrimary)
            .font(.body)
        }
    }

    private var ideaHintSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("AREA HINT (optional)")
                .podTextStyle(.label, color: AppColors.textTertiary)

            TextField("e.g. pod, infrastructure, trading", text: $model.ideaHint)
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
                .foregroundStyle(AppColors.textPrimary)
                .font(.body)
        }
    }

    private var ideaSubmitButton: some View {
        Button {
            Task { await model.submitIdea() }
        } label: {
            HStack(spacing: Theme.sm) {
                if model.isSubmittingIdea {
                    ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(0.85)
                    Text("Queuing…").font(.body.bold()).foregroundStyle(.white)
                } else {
                    Image(systemName: "lightbulb.fill").font(.system(size: 16, weight: .semibold))
                    Text("Queue Idea").font(.body.bold())
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.sm + 2)
            .background(model.canSubmitIdea ? makerPurple : AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        }
        .buttonStyle(.plain)
        .disabled(!model.canSubmitIdea)
        .animation(.easeInOut(duration: 0.2), value: model.isSubmittingIdea)
    }

    private var ideaFooter: some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2)
                .foregroundStyle(AppColors.textMuted)
            Text("Ideas land in the Work tab → Schoolhouse queue. The team assesses, develops scope, and builds a project if it's real.")
                .podTextStyle(.label, color: AppColors.textMuted)
        }
    }

    // MARK: - Pipeline Mode

    private var pipelineContent: some View {
        VStack(alignment: .leading, spacing: Theme.lg) {
            pipelineHeader
            if model.isLoadingPipeline {
                HStack {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                }
                .padding(.vertical, Theme.xxl)
            } else if let err = model.pipelineError {
                errorBanner(err)
            } else if model.readyIdeas.isEmpty {
                emptyPipelineView
            } else {
                ForEach(model.readyIdeas) { idea in
                    readyIdeaCard(idea)
                }
                Button {
                    Task { await model.loadReadyIdeas() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.sm)
            }
        }
    }

    private var pipelineHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pipeline")
                .podTextStyle(.title1, color: AppColors.textPrimary)
            Text("Ideas that cleared assessment + discovery. Promote one to kick off a build ticket.")
                .podTextStyle(.body, color: AppColors.textSecondary)
        }
    }

    private var emptyPipelineView: some View {
        VStack(spacing: Theme.sm) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppColors.textMuted)
            Text("No ideas in pipeline yet.")
                .podTextStyle(.body, color: AppColors.textSecondary)
            Text("Submit ideas in the Idea tab — they'll appear here after Schoolhouse assessment + discovery.")
                .podTextStyle(.caption, color: AppColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.xxl)
    }

    private func readyIdeaCard(_ idea: ReadyIdea) -> some View {
        let isPromoting = model.promotingIds.contains(idea.id)
        let promoteResult = model.promoteResults[idea.id]
        let promoteError = model.promoteErrors[idea.id]
        return VStack(alignment: .leading, spacing: Theme.sm) {
            Text(idea.title)
                .podTextStyle(.headline, color: AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = idea.summary {
                Text(summary)
                    .podTextStyle(.body, color: AppColors.textSecondary)
                    .lineLimit(3)
            }

            if let scope = idea.scope {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SCOPE")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                    Text(scope)
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                        .lineLimit(4)
                }
                .padding(Theme.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            if let effort = idea.effortEstimate {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textMuted)
                    Text(effort)
                        .podTextStyle(.caption, color: AppColors.textMuted)
                }
            }

            if let result = promoteResult {
                successBanner(result)
            } else if let err = promoteError {
                errorBanner(err)
            } else {
                Button {
                    Task { await model.promoteIdea(id: idea.id) }
                } label: {
                    HStack(spacing: Theme.xs) {
                        if isPromoting {
                            ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(isPromoting ? "Promoting…" : "Promote to Ticket")
                            .font(.subheadline.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.sm)
                    .background(makerPurple)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .buttonStyle(.plain)
                .disabled(isPromoting)
            }
        }
        .padding(Theme.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Shared Banners

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.accentDanger)
                .padding(.top, 1)
            Text(message)
                .podTextStyle(.caption, color: AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.sm)
        .background(AppColors.accentDanger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.accentDanger.opacity(0.25), lineWidth: 1)
        )
    }

    private func successBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.accentSuccess)
                .padding(.top, 1)
            Text(message)
                .podTextStyle(.caption, color: AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.sm)
        .background(AppColors.accentSuccess.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.accentSuccess.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Style

    private var makerPurple: Color { Color(red: 0.55, green: 0.35, blue: 0.95) }
}

#Preview {
    MakerView()
        .environmentObject(AppState())
}
