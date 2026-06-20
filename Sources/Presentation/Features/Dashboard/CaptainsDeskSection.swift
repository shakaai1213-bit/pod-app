import SwiftUI

// MARK: - Captain's Desk

struct CaptainsDeskSection: View {
    @State private var model = CaptainsDeskModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            VStack(spacing: 10) {
                CaptainsDeskCard(
                    title: "Current Topics",
                    icon: "pin.fill",
                    tint: AppColors.accentElectric,
                    subtitle: "Tony's active focus",
                    state: model.currentTopics
                )

                CaptainsDeskCard(
                    title: "Parking Lot",
                    icon: "parkingsign.circle.fill",
                    tint: AppColors.accentWarning,
                    subtitle: "Append-only capture; no auto-dispatch",
                    state: model.parkingLot
                )
            }
        }
        .task { await model.load() }
        .refreshable { await model.load(force: true) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "command.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.accentElectric)

            Text("CAPTAIN'S DESK")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .tracking(0.5)

            Spacer()

            if model.isLoading {
                ProgressView()
                    .scaleEffect(0.65)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }
}

private struct CaptainsDeskCard: View {
    let title: String
    let icon: String
    let tint: Color
    let subtitle: String
    let state: CaptainsDeskCardState

    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.14))
                            .frame(width: 34, height: 34)

                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(tint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppColors.textPrimary)

                        Text(subtitleText)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.top, 4)
                }

                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppColors.backgroundTertiary)
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppColors.backgroundTertiary)
                    .frame(width: 180, height: 10)
            }
            .padding(.leading, 44)

        case .loaded(let ticket):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(renderedLines(from: ticket.description), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .unavailable(let debugMessage):
            VStack(alignment: .leading, spacing: 5) {
                Text("\(title) unavailable")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)

                #if DEBUG
                if let debugMessage {
                    Text(debugMessage)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var subtitleText: String {
        switch state {
        case .loaded(let ticket):
            return "updated \(RelativeTimeFormatter.shared.string(from: ticket.updatedAt)) · \(subtitle)"
        case .loading:
            return "\(subtitle) · loading"
        case .unavailable:
            return "\(subtitle) · unavailable"
        }
    }

    private func renderedLines(from description: String?) -> [String] {
        let body = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return ["No description yet."] }

        let lines = body
            .split(whereSeparator: \.isNewline)
            .map { cleanMarkdownLine(String($0)) }
            .filter { !$0.isEmpty }

        if isExpanded {
            return lines.isEmpty ? ["No description yet."] : lines
        }
        return Array((lines.isEmpty ? ["No description yet."] : lines).prefix(6))
    }

    private func cleanMarkdownLine(_ line: String) -> String {
        var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix("#") {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        }
        if cleaned.hasPrefix("- [ ] ") || cleaned.hasPrefix("- [x] ") || cleaned.hasPrefix("- [X] ") {
            cleaned = "• " + String(cleaned.dropFirst(6))
        } else if cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") {
            cleaned = "• " + String(cleaned.dropFirst(2))
        }
        return cleaned
    }
}

@Observable
final class CaptainsDeskModel {
    var currentTopics: CaptainsDeskCardState = .loading
    var parkingLot: CaptainsDeskCardState = .loading
    var isLoading = false

    private let apiClient: APIClient
    private var hasLoaded = false

    private enum TicketID {
        static let currentTopics = "71a5f76b-87f4-4020-baa5-065e3107ad7e"
        static let parkingLot = "167fa4b7-1b4c-43ce-ba22-a4fc48abf4a8"
    }

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    @MainActor
    func load(force: Bool = false) async {
        guard force || !hasLoaded else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        async let topics = loadTicket(id: TicketID.currentTopics)
        async let parking = loadTicket(id: TicketID.parkingLot)
        let (topicsState, parkingState) = await (topics, parking)

        currentTopics = topicsState
        parkingLot = parkingState
    }

    private func loadTicket(id: String) async -> CaptainsDeskCardState {
        do {
            let ticket: TicketDTO = try await apiClient.get(path: Endpoint.ticket(id: id).path)
            return .loaded(CaptainsDeskTicket(ticket))
        } catch {
            #if DEBUG
            return .unavailable(Self.describeLoadError(error))
            #else
            return .unavailable(nil)
            #endif
        }
    }

    private static func describeLoadError(_ error: Error) -> String {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            return "DecodingError.keyNotFound(\(key.stringValue)) at \(codingPathDescription(context.codingPath + [key])): \(context.debugDescription)"
        case let DecodingError.typeMismatch(type, context):
            return "DecodingError.typeMismatch(\(type)) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case let DecodingError.valueNotFound(type, context):
            return "DecodingError.valueNotFound(\(type)) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case let DecodingError.dataCorrupted(context):
            return "DecodingError.dataCorrupted at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case let apiError as APIError:
            return "APIError(\(apiError.code)): \(apiError.message)"
        default:
            return error.localizedDescription
        }
    }

    private static func codingPathDescription(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "<root>" }
        return path.map(\.stringValue).joined(separator: ".")
    }
}

enum CaptainsDeskCardState: Equatable {
    case loading
    case loaded(CaptainsDeskTicket)
    case unavailable(String?)
}

struct CaptainsDeskTicket: Equatable {
    let id: String
    let title: String
    let description: String?
    let updatedAt: Date

    init(_ dto: TicketDTO) {
        self.id = dto.id
        self.title = dto.title
        self.description = dto.description
        self.updatedAt = dto.updatedAt
    }
}
