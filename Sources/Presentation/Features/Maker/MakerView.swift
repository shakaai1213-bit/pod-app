import SwiftUI
import PhotosUI

// MARK: - Models

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

// MARK: - ViewModel

@Observable
@MainActor
final class MakerViewModel {
    var pickerItem: PhotosPickerItem?
    var sourceImage: UIImage?
    var resultImage: UIImage?
    var instruction: String = ""
    var isTransforming = false
    var errorMessage: String?
    var promptUsed: String?
    var generationTimeMs: Int?

    var canTransform: Bool {
        sourceImage != nil && !instruction.trimmingCharacters(in: .whitespaces).isEmpty && !isTransforming
    }

    func loadPickedItem() async {
        guard let item = pickerItem else { return }
        resultImage = nil
        errorMessage = nil
        promptUsed = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Couldn't load image."
            return
        }
        sourceImage = image
    }

    func transform() async {
        guard let source = sourceImage, !isTransforming else { return }
        let text = instruction.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        isTransforming = true
        errorMessage = nil
        resultImage = nil
        promptUsed = nil
        generationTimeMs = nil
        defer { isTransforming = false }

        // Encode image as JPEG (smaller than PNG for photos)
        guard let jpeg = source.jpegData(compressionQuality: 0.82) else {
            errorMessage = "Couldn't encode image."
            return
        }
        let b64 = jpeg.base64EncodedString()

        let body = MakerTransformRequest(imageB64: b64, instruction: text, width: 512, height: 512)

        do {
            let response: MakerTransformResponse = try await makerPost(body: body)
            guard let resultData = Data(base64Encoded: response.resultImageB64),
                  let img = UIImage(data: resultData) else {
                errorMessage = "Backend returned unreadable image."
                return
            }
            resultImage = img
            promptUsed = response.promptUsed
            generationTimeMs = response.generationTimeMs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        pickerItem = nil
        sourceImage = nil
        resultImage = nil
        instruction = ""
        errorMessage = nil
        promptUsed = nil
        generationTimeMs = nil
    }

    // MARK: - Private: direct URLRequest with 100s timeout

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
        let encoder = JSONEncoder()
        req.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? "no body"
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - View

struct MakerView: View {
    @State private var model = MakerViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    header
                    imageSection
                    if model.sourceImage != nil {
                        instructionSection
                        transformButton
                    }
                    if let error = model.errorMessage {
                        errorBanner(error)
                    }
                    if model.resultImage != nil {
                        resultSection
                    }
                }
                .padding(.horizontal, Theme.md)
                .padding(.top, Theme.lg)
                .padding(.bottom, Theme.xxl)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Maker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.sourceImage != nil || model.resultImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Reset") { model.reset() }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .onChange(of: model.pickerItem) { _, _ in
            Task { await model.loadPickedItem() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Maker")
                .podTextStyle(.title1, color: AppColors.textPrimary)
            Text("Pick an image, give an instruction, transform it locally via SDXL Turbo.")
                .podTextStyle(.body, color: AppColors.textSecondary)
        }
    }

    // MARK: - Image Section

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

    // MARK: - Instruction Section

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

    // MARK: - Transform Button

    private var transformButton: some View {
        Button {
            Task { await model.transform() }
        } label: {
            HStack(spacing: Theme.sm) {
                if model.isTransforming {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.85)
                    Text("Transforming…")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Transform")
                        .font(.body.bold())
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

    // MARK: - Error Banner

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

    // MARK: - Result Section

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Text("RESULT")
                    .podTextStyle(.label, color: AppColors.textTertiary)
                Spacer()
                if let ms = model.generationTimeMs {
                    Text("\(ms)ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppColors.textTertiary)
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
                    Text("PROMPT USED")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                    Text(prompt)
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                }
                .padding(Theme.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    // MARK: - Style

    private var makerPurple: Color { Color(red: 0.55, green: 0.35, blue: 0.95) }
}

#Preview {
    MakerView()
        .environmentObject(AppState())
}
