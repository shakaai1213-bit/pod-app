import SwiftUI

enum AvatarSize: String, CaseIterable {
    case xs, sm, md, lg, xl

    var diameter: CGFloat {
        switch self {
        case .xs:  return 20
        case .sm:  return 28
        case .md:  return 36
        case .lg:  return 48
        case .xl:  return 64
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .xs:  return 8
        case .sm:  return 11
        case .md:  return 14
        case .lg:  return 18
        case .xl:  return 24
        }
    }

    var statusDotSize: CGFloat {
        switch self {
        case .xs:  return 6
        case .sm:  return 8
        case .md:  return 10
        case .lg:  return 12
        case .xl:  return 14
        }
    }

    var ringWidth: CGFloat {
        switch self {
        case .xs:  return 1
        case .sm:  return 1.5
        case .md:  return 2
        case .lg:  return 2
        case .xl:  return 2.5
        }
    }
}

// MARK: - Avatar Image Cache

private final class AvatarImageCache {
    static let shared = AvatarImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: Int(image.jpegData(compressionQuality: 0.8)?.count ?? 0))
    }
}

// MARK: - DiceBear Avatar URL

/// Generate a DiceBear avatar URL for a given name.
/// Uses "thumbs" style — clean, consistent illustrations.
func diceBearAvatarURL(for name: String, size: AvatarSize) -> URL? {
    let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
    // Map avatar size to DiceBear pixel size (1x, 2x, 3x)
    let px = Int(size.diameter * 2) // @2x equivalent
    return URL(string: "https://api.dicebear.com/7.x/thumbs/svg?seed=\(encodedName)&size=\(px)&backgroundColor=0d1117")
}

// MARK: - Remote Image Loader

private struct RemoteAvatarImage: View {
    let name: String
    let size: AvatarSize
    let fallbackColor: Color

    @State private var loadedImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                // Shimmer placeholder while loading
                Circle()
                    .fill(fallbackColor.opacity(0.3))
                    .overlay {
                        ProgressView()
                            .tint(.white.opacity(0.6))
                            .scaleEffect(0.5)
                    }
            } else {
                // Fallback to initials on error
                initialsView
            }
        }
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }

    private var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    init(name: String, size: AvatarSize, fallbackColor: Color) {
        self.name = name
        self.size = size
        self.fallbackColor = fallbackColor
    }

    private func loadImage() async {
        guard let url = diceBearAvatarURL(for: name, size: size) else {
            await MainActor.run { isLoading = false }
            return
        }

        // Check cache first
        if let cached = AvatarImageCache.shared.image(for: name) {
            await MainActor.run {
                loadedImage = cached
                isLoading = false
            }
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                await MainActor.run { isLoading = false }
                return
            }
            if let image = UIImage(data: data) {
                AvatarImageCache.shared.setImage(image, for: name)
                await MainActor.run {
                    loadedImage = image
                    isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - AvatarView

struct AvatarView: View {
    let name: String
    var status: Status? = nil
    var size: AvatarSize = .md
    var showRing: Bool = false
    var image: UIImage? = nil
    /// Remote avatar URL (optional). Falls back to DiceBear if nil.
    var remoteURL: String? = nil
    /// Show DiceBear avatar when no remoteURL or image is provided.
    var useDiceBear: Bool = true

    private var backgroundColor: Color {
        Color(AvatarView.colorForName(name))
    }

    private var ringColor: Color {
        status?.color ?? .green
    }

    public static func colorForName(_ name: String) -> Color {
        let palette: [Color] = [
            .red, .orange, .yellow, .green,
            .teal, .blue, .indigo, .purple, .pink,
        ]
        let hash = abs(name.hashValue)
        return palette[hash % palette.count]
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
                .frame(width: size.diameter, height: size.diameter)
                .clipShape(Circle())
                .overlay {
                    if showRing, status != nil {
                        Circle()
                            .stroke(ringColor, lineWidth: size.ringWidth)
                    }
                }

            // Status dot
            if let status = status {
                StatusBadge.dot(status, size: .small)
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityLabel("\(name) avatar")
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let image = image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let remoteURL = remoteURL, let url = URL(string: remoteURL) {
            RemoteURLImageView(url: url, name: name, size: size, fallbackColor: backgroundColor)
        } else if useDiceBear {
            RemoteAvatarImage(name: name, size: size, fallbackColor: backgroundColor)
                .task {
                    // Trigger DiceBear load
                }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColor)
    }

    private var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}

// MARK: - Remote URL Image (for arbitrary URLs, not DiceBear)

private struct RemoteURLImageView: View {
    let url: URL
    let name: String
    let size: AvatarSize
    let fallbackColor: Color

    @State private var loadedImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                Circle()
                    .fill(fallbackColor.opacity(0.3))
                    .overlay {
                        ProgressView()
                            .tint(.white.opacity(0.6))
                            .scaleEffect(0.5)
                    }
            } else {
                initialsView
            }
        }
        .task {
            await loadImage()
        }
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fallbackColor)
    }

    private var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    private func loadImage() async {
        if let cached = AvatarImageCache.shared.image(for: url.absoluteString) {
            await MainActor.run {
                loadedImage = cached
                isLoading = false
            }
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                await MainActor.run { isLoading = false }
                return
            }
            AvatarImageCache.shared.setImage(image, for: url.absoluteString)
            await MainActor.run {
                loadedImage = image
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - System Avatar (for agents, bots, etc.)

struct SystemAvatarView: View {
    let systemImage: String
    var status: Status? = nil
    var size: AvatarSize = .md
    var color: Color = .accentColor

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: size.fontSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size.diameter, height: size.diameter)
                .background(color.gradient)
                .clipShape(Circle())
                .overlay {
                    if status != nil {
                        Circle()
                            .stroke(statusColor, lineWidth: size.ringWidth)
                    }
                }

            if let status = status {
                StatusBadge.dot(status, size: .small)
                    .offset(x: 2, y: 2)
            }
        }
    }

    private var statusColor: Color {
        status?.color ?? .clear
    }
}

#Preview {
    VStack(spacing: 24) {
        // Name-based avatars with DiceBear
        HStack(spacing: 16) {
            ForEach(AvatarSize.allCases, id: \.self) { size in
                AvatarView(name: "Maui", size: size)
            }
        }

        // With status
        HStack(spacing: 24) {
            AvatarView(name: "Maui", status: .online, size: .lg, showRing: true)
            AvatarView(name: "Researcher", status: .busy, size: .lg, showRing: true)
            AvatarView(name: "Builder", status: .away, size: .lg, showRing: true)
            AvatarView(name: "Analyst", status: .offline, size: .lg, showRing: true)
        }

        // System avatars
        HStack(spacing: 24) {
            SystemAvatarView(systemImage: "cpu", size: .lg, color: .purple)
            SystemAvatarView(systemImage: "brain", size: .lg, color: .blue)
            SystemAvatarView(systemImage: "hammer", size: .lg, color: .orange)
            SystemAvatarView(systemImage: "chart.bar", size: .lg, color: .green)
        }
    }
    .padding()
    .background(Color.black)
}
