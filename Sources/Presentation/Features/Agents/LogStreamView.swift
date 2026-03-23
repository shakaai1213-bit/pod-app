import SwiftUI

// MARK: - Log Stream View

struct LogStreamView: View {

    let agent: Agent

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: LogStreamViewModel

    @State private var autoScrollEnabled: Bool = true
    @State private var selectedFilter: LogFilter = .all
    @State private var showingCopyConfirmation = false

    init(agent: Agent) {
        self.agent = agent
        _viewModel = State(initialValue: LogStreamViewModel(agentId: agent.id))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                logList
                statusBar
            }
            .background(logBackground)
            .navigationTitle("Logs — \(agent.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .alert("Copied to Clipboard", isPresented: $showingCopyConfirmation) {
                Button("OK", role: .cancel) {}
            }
            .task {
                await viewModel.connect()
            }
            .onDisappear {
                viewModel.disconnect()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") { dismiss() }
                .foregroundStyle(AppColors.textSecondary)
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: Theme.sm) {
                // Pause/Resume auto-scroll
                Button {
                    autoScrollEnabled.toggle()
                } label: {
                    Image(systemName: autoScrollEnabled ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(autoScrollEnabled ? AppColors.accentWarning : AppColors.textSecondary)
                }

                // Copy all
                Button {
                    viewModel.copyAllLogs()
                    showingCopyConfirmation = true
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }

                // Clear
                Button {
                    viewModel.clearLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accentDanger)
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: Theme.xs) {
            ForEach(LogFilter.allCases, id: \.self) { filter in
                filterButton(filter)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.xs)
        .background(logBackground)
    }

    private func filterButton(_ filter: LogFilter) -> some View {
        let isSelected = selectedFilter == filter

        return Button {
            selectedFilter = filter
        } label: {
            Text(filter.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? filter.textColor : AppColors.textTertiary)
                .padding(.horizontal, Theme.sm)
                .padding(.vertical, Theme.xxs)
                .background(isSelected ? filter.textColor.opacity(0.15) : Color.clear)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? filter.textColor.opacity(0.3) : AppColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log List

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.filteredLogs(for: selectedFilter)) { entry in
                        logEntryRow(entry)
                    }
                }
                .padding(.horizontal, Theme.sm)
                .padding(.vertical, Theme.xs)
            }
            .background(logBackground)
            .onChange(of: viewModel.entries.count) { _, _ in
                if autoScrollEnabled, let last = viewModel.entries.last {
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logEntryRow(_ entry: LogEntry) -> some View {
        Text(entry.formatted)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(entry.level.textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(entry.id)
            .textSelection(.enabled)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(viewModel.isConnected ? AppColors.accentSuccess : AppColors.accentDanger)
                .frame(width: 8, height: 8)

            Text(viewModel.isConnected ? "Connected" : "Disconnected")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)

            Spacer()

            Text("\(viewModel.entries.count) entries")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)

            Text("·")
                .foregroundStyle(AppColors.textMuted)

            Text("\(viewModel.errorCount) errors")
                .font(.system(size: 12))
                .foregroundStyle(viewModel.errorCount > 0 ? AppColors.accentDanger : AppColors.textTertiary)
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.xs)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Theme

    private var logBackground: Color {
        Color(hexString: "0A0A0F")
    }
}

// MARK: - Log Filter

enum LogFilter: CaseIterable {
    case all
    case errors
    case warnings

    var label: String {
        switch self {
        case .all:      return "ALL"
        case .errors:  return "ERROR"
        case .warnings: return "WARN"
        }
    }

    var textColor: Color {
        switch self {
        case .all:      return AppColors.textSecondary
        case .errors:  return AppColors.accentDanger
        case .warnings: return AppColors.accentWarning
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
    let source: String?

    var formatted: String {
        let ts = timestamp.logTimestamp
        let lvl = level.label.padding(toLength: 5, withPad: " ", startingAt: 0)
        let src = source.map { "[\($0)] " } ?? ""
        return "\(ts) \(lvl) \(src)\(message)"
    }
}

// MARK: - Log Level

enum LogLevel: String {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"

    var label: String { rawValue }

    var textColor: Color {
        switch self {
        case .debug: return AppColors.textTertiary
        case .info:  return .white
        case .warn:  return AppColors.accentWarning
        case .error:  return AppColors.accentDanger
        }
    }
}

// MARK: - Date Log Timestamp

extension Date {
    var logTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: self)
    }
}

// MARK: - Log Stream ViewModel

@Observable
final class LogStreamViewModel {

    var entries: [LogEntry] = []
    var isConnected: Bool = false
    var errorCount: Int = 0

    private let agentId: UUID
    private var eventSource: URLSessionDataTask?
    private var buffer = ""

    init(agentId: UUID) {
        self.agentId = agentId
    }

    // MARK: - Connect

    @MainActor
    func connect() async {
        let urlString = "http://192.168.4.243:8000/api/v1/agents/\(agentId.uuidString)/logs/stream"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = .infinity

        let session = URLSession(configuration: .default)
        eventSource = session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                Task { @MainActor in
                    self.isConnected = false
                }
                return
            }

            guard let data = data, let chunk = String(data: data, encoding: .utf8) else { return }

            Task { @MainActor in
                self.processChunk(chunk)
            }
        }

        await MainActor.run { self.isConnected = true }
        eventSource?.resume()

        // Load mock logs for demo
        await loadMockLogs()
    }

    func disconnect() {
        eventSource?.cancel()
        eventSource = nil
        isConnected = false
    }

    // MARK: - Filter

    func filteredLogs(for filter: LogFilter) -> [LogEntry] {
        switch filter {
        case .all:      return entries
        case .errors:   return entries.filter { $0.level == .error }
        case .warnings: return entries.filter { $0.level == .warn || $0.level == .error }
        }
    }

    // MARK: - Clear / Copy

    func clearLogs() {
        entries = []
        errorCount = 0
    }

    func copyAllLogs() {
        let text = entries.map(\.formatted).joined(separator: "\n")
        UIPasteboard.general.string = text
    }

    // MARK: - Private

    private func processChunk(_ chunk: String) {
        buffer += chunk
        let events = buffer.components(separatedBy: "\n\n")
        for event in events.dropLast() {
            parseEvent(event)
        }
        buffer = events.last ?? ""
    }

    private func parseEvent(_ raw: String) {
        var dataJson: String?

        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("data:") {
                dataJson = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }

        guard let json = dataJson,
              let jsonData = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let levelStr = dict["level"] as? String,
              let message = dict["message"] as? String
        else { return }

        let level = LogLevel(rawValue: levelStr.uppercased()) ?? .info
        let source = dict["source"] as? String

        // Parse ISO8601 timestamp or use now
        var timestamp = Date()
        if let tsString = dict["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: tsString) ?? Date()
        }

        let entry = LogEntry(timestamp: timestamp, level: level, message: message, source: source)
        entries.append(entry)

        if level == .error {
            errorCount += 1
        }

        // Keep last 500 entries
        if entries.count > 500 {
            let removed = Array(entries.prefix(entries.count - 500))
            entries.removeFirst(entries.count - 500)
            if removed.contains(where: { $0.level == .error }) {
                errorCount = entries.filter { $0.level == .error }.count
            }
        }
    }

    // MARK: - Mock Logs

    @MainActor
    private func loadMockLogs() async {
        let now = Date()
        let mockEntries: [LogEntry] = [
            LogEntry(timestamp: now.addingTimeInterval(-30), level: .info, message: "Agent session initialized", source: "core"),
            LogEntry(timestamp: now.addingTimeInterval(-28), level: .info, message: "Loading system prompt from config", source: "config"),
            LogEntry(timestamp: now.addingTimeInterval(-25), level: .debug, message: "Model: gpt-4o | Temperature: 0.7", source: "llm"),
            LogEntry(timestamp: now.addingTimeInterval(-22), level: .info, message: "Connected to message broker", source: "broker"),
            LogEntry(timestamp: now.addingTimeInterval(-20), level: .info, message: "Subscribed to channels: projects, general, alerts", source: "broker"),
            LogEntry(timestamp: now.addingTimeInterval(-18), level: .info, message: "Starting task: PR #42 review", source: "task"),
            LogEntry(timestamp: now.addingTimeInterval(-15), level: .debug, message: "Fetching diff for branch feature/auth-refresh", source: "git"),
            LogEntry(timestamp: now.addingTimeInterval(-12), level: .info, message: "Analyzing 847 changed lines across 12 files", source: "review"),
            LogEntry(timestamp: now.addingTimeInterval(-10), level: .warn, message: "High cyclomatic complexity detected in auth/middleware.swift (score: 18)", source: "review"),
            LogEntry(timestamp: now.addingTimeInterval(-8), level: .info, message: "3 inline comments posted to PR #42", source: "github"),
            LogEntry(timestamp: now.addingTimeInterval(-5), level: .debug, message: "Token usage: 12,450 input / 340 output", source: "llm"),
            LogEntry(timestamp: now.addingTimeInterval(-3), level: .info, message: "Task completed — summary posted to #projects", source: "task"),
            LogEntry(timestamp: now.addingTimeInterval(-1), level: .info, message: "Idle — waiting for next assignment", source: "core"),
        ]

        for entry in mockEntries {
            entries.append(entry)
        }
    }
}
