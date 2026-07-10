import Foundation

struct FundRouteFeedDTO: Decodable {
    let status: String?
    let quality: String?
    let stale: Bool?
    let asOf: String?
    let stalenessSeconds: Int?
    let degradedReason: String?
    let data: FundRoutesTradesDTO?

    private enum CodingKeys: String, CodingKey {
        case status
        case quality
        case stale
        case asOf = "as_of"
        case stalenessSeconds = "staleness_seconds"
        case degradedReason = "degraded_reason"
        case data
    }

    init(
        status: String?,
        quality: String?,
        stale: Bool?,
        asOf: String?,
        stalenessSeconds: Int?,
        degradedReason: String?,
        data: FundRoutesTradesDTO?
    ) {
        self.status = status
        self.quality = quality
        self.stale = stale
        self.asOf = asOf
        self.stalenessSeconds = stalenessSeconds
        self.degradedReason = degradedReason
        self.data = data
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init(
                status: "degraded",
                quality: "malformed",
                stale: nil,
                asOf: nil,
                stalenessSeconds: nil,
                degradedReason: "Malformed ORCA trade feed envelope.",
                data: nil
            )
            return
        }

        self.init(
            status: container.fundString(forKey: .status),
            quality: container.fundString(forKey: .quality),
            stale: container.fundBool(forKey: .stale),
            asOf: container.fundString(forKey: .asOf),
            stalenessSeconds: container.fundInt(forKey: .stalenessSeconds),
            degradedReason: container.fundString(forKey: .degradedReason),
            data: (try? container.decodeIfPresent(FundRoutesTradesDTO.self, forKey: .data)) ?? nil
        )
    }

    static func degraded(reason: String, quality: String = "unavailable") -> FundRouteFeedDTO {
        FundRouteFeedDTO(
            status: "degraded",
            quality: quality,
            stale: nil,
            asOf: nil,
            stalenessSeconds: nil,
            degradedReason: reason,
            data: nil
        )
    }

    var normalizedStatus: String {
        (status ?? "degraded").lowercased()
    }

    var normalizedQuality: String {
        (quality ?? (data == nil ? "unavailable" : "available")).lowercased()
    }

    var isStale: Bool {
        stale == true || normalizedQuality == "stale"
    }

    var hasPayloadData: Bool {
        data?.payload != nil
    }

    var displayAsOf: String? {
        data?.payload?.asOf ?? asOf ?? data?.generatedAt
    }

    var displayStaleness: String? {
        guard let stalenessSeconds else { return nil }
        return FundTradesFormat.duration(seconds: stalenessSeconds)
    }

    var userFacingDegradedReason: String? {
        guard let degradedReason, !degradedReason.isEmpty else { return nil }
        let normalized = degradedReason.lowercased()
        if normalized.contains("filenotfounderror") || normalized.contains("artifact unavailable") {
            return "Trade feed is awaiting delivery to ORCA Mini."
        }
        if normalized.contains("malformed") || normalized.contains("decoding") {
            return "ORCA received a trade feed it could not read."
        }
        return degradedReason
    }

    var stage: FundTradesStage {
        data?.stage ?? .paper
    }
}

struct FundRoutesTradesDTO: Decodable {
    let schemaVersion: String?
    let route: String?
    let generatedAt: String?
    let liveTradingRaw: String?
    let liveTrading: Bool?
    let runtimeIntegration: String?
    let tradingActionable: Bool?
    let status: String?
    let sourceArtifact: FundTradesSourceArtifactDTO?
    let blockedControls: [String]
    let payload: FundTradesPayloadDTO?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case route
        case generatedAt = "generated_at"
        case liveTrading = "live_trading"
        case runtimeIntegration = "runtime_integration"
        case tradingActionable = "trading_actionable"
        case status
        case sourceArtifact = "source_artifact"
        case blockedControls = "blocked_controls"
        case payload
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            schemaVersion = nil
            route = nil
            generatedAt = nil
            liveTradingRaw = nil
            liveTrading = nil
            runtimeIntegration = nil
            tradingActionable = nil
            status = nil
            sourceArtifact = nil
            blockedControls = []
            payload = nil
            return
        }

        schemaVersion = container.fundString(forKey: .schemaVersion)
        route = container.fundString(forKey: .route)
        generatedAt = container.fundString(forKey: .generatedAt)
        liveTradingRaw = container.fundString(forKey: .liveTrading)
        liveTrading = container.fundBool(forKey: .liveTrading)
        runtimeIntegration = container.fundString(forKey: .runtimeIntegration)
        tradingActionable = container.fundBool(forKey: .tradingActionable)
        status = container.fundString(forKey: .status)
        sourceArtifact = (try? container.decodeIfPresent(FundTradesSourceArtifactDTO.self, forKey: .sourceArtifact)) ?? nil
        blockedControls = container.fundStringArray(forKey: .blockedControls) ?? []
        payload = (try? container.decodeIfPresent(FundTradesPayloadDTO.self, forKey: .payload)) ?? nil
    }

    var stage: FundTradesStage {
        FundTradesStage(liveTradingRaw: liveTradingRaw, liveTrading: liveTrading, tradingActionable: tradingActionable)
    }
}

struct FundTradesSourceArtifactDTO: Decodable {
    let stitch: String?
    let lilo: String?

    private enum CodingKeys: String, CodingKey {
        case stitch
        case lilo
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            stitch = nil
            lilo = nil
            return
        }
        stitch = container.fundString(forKey: .stitch)
        lilo = container.fundString(forKey: .lilo)
    }
}

struct FundTradesPayloadDTO: Decodable {
    let asOf: String?
    let desks: [FundTradesDeskDTO]
    let openPositions: [FundTradePositionDTO]
    let closedRecent: [FundClosedTradeDTO]

    private enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case desks
        case openPositions = "open_positions"
        case closedRecent = "closed_recent"
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            asOf = nil
            desks = []
            openPositions = []
            closedRecent = []
            return
        }

        asOf = container.fundString(forKey: .asOf)
        let decodedDesks = (try? container.decodeIfPresent([String: FundTradesDeskDTO].self, forKey: .desks)) ?? [:]
        desks = decodedDesks
            .map { $0.value.withDeskId($0.key) }
            .sorted { $0.sortKey < $1.sortKey }
        openPositions = (try? container.decodeIfPresent([FundTradePositionDTO].self, forKey: .openPositions)) ?? []
        closedRecent = (try? container.decodeIfPresent([FundClosedTradeDTO].self, forKey: .closedRecent)) ?? []
    }

    func openCount(for deskId: String) -> Int {
        let matches = openPositions.filter { $0.matchesDesk(deskId) }
        if !matches.isEmpty {
            return matches.count
        }
        return desks.first(where: { $0.matchesDesk(deskId) })?.openPositionCount ?? 0
    }

    var totalOpenCount: Int {
        if !openPositions.isEmpty {
            return openPositions.count
        }
        return desks.reduce(0) { $0 + ($1.openPositionCount ?? 0) }
    }

    var deskSections: [FundTradesDeskDTO] {
        var sections = desks
        for deskId in ["stitch", "lilo"] where !sections.contains(where: { $0.matchesDesk(deskId) }) {
            sections.append(FundTradesDeskDTO.placeholder(id: deskId))
        }
        return sections.sorted { $0.sortKey < $1.sortKey }
    }
}

struct FundTradesDeskDTO: Decodable, Identifiable {
    let id: String
    let name: String?
    let status: String?
    let mode: String?
    let raw: [String: FundJSONValue]

    init(id: String, name: String?, status: String?, mode: String?, raw: [String: FundJSONValue]) {
        self.id = id
        self.name = name
        self.status = status
        self.mode = mode
        self.raw = raw
    }

    init(from decoder: Decoder) throws {
        let raw = FundJSONValue.objectPayload(from: decoder)
        id = raw.fundString(["id", "desk", "name"]) ?? UUID().uuidString
        name = raw.fundString(["display_name", "name", "label"])
        status = raw.fundString(["status", "state", "health"])
        mode = raw.fundString(["mode", "stage", "trading_mode"])
        self.raw = raw
    }

    static func placeholder(id: String) -> FundTradesDeskDTO {
        FundTradesDeskDTO(id: id, name: id.capitalized, status: nil, mode: nil, raw: [:])
    }

    func withDeskId(_ id: String) -> FundTradesDeskDTO {
        FundTradesDeskDTO(id: id, name: name, status: status, mode: mode, raw: raw)
    }

    var sortKey: String {
        switch id.lowercased() {
        case "stitch": return "0-stitch"
        case "lilo": return "1-lilo"
        default: return "2-\(id.lowercased())"
        }
    }

    var displayName: String {
        name ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var openPositionCount: Int? {
        raw.fundInt(["open_position_count", "open_positions", "open_count", "positions_open", "open"])
    }

    var closedRecentCount: Int? {
        raw.fundInt(["closed_recent_count", "closed_count", "closed_trades", "closed"])
    }

    var pnl: Double? {
        raw.fundDouble(["pnl", "pnl_usd", "net_pnl", "realized_pnl", "total_pnl"])
    }

    var winRate: Double? {
        raw.fundDouble(["win_rate", "winrate"])
    }

    var strategyAggregates: [FundTradesStrategyAggregateDTO] {
        let value = raw.fundValue(["strategies", "strategy_aggregates", "aggregates"])
        switch value {
        case .object(let object):
            return object.map { key, value in
                FundTradesStrategyAggregateDTO(id: key, raw: value.objectValue ?? [:])
            }
            .sorted { $0.displayName < $1.displayName }
        case .array(let values):
            return values.enumerated().map { index, value in
                FundTradesStrategyAggregateDTO(id: "strategy-\(index)", raw: value.objectValue ?? [:])
            }
        default:
            return []
        }
    }

    func matchesDesk(_ deskId: String) -> Bool {
        id.lowercased() == deskId.lowercased()
    }
}

struct FundTradesStrategyAggregateDTO: Decodable, Identifiable {
    let id: String
    let name: String?
    let status: String?
    let raw: [String: FundJSONValue]

    init(id: String, raw: [String: FundJSONValue]) {
        self.id = raw.fundString(["id", "strategy_id"]) ?? id
        self.name = raw.fundString(["name", "strategy", "label"])
        self.status = raw.fundString(["status", "state"])
        self.raw = raw
    }

    init(from decoder: Decoder) throws {
        self.init(id: UUID().uuidString, raw: FundJSONValue.objectPayload(from: decoder))
    }

    var displayName: String {
        name ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var openCount: Int? {
        raw.fundInt(["open_count", "open_positions", "positions_open"])
    }

    var closedCount: Int? {
        raw.fundInt(["closed_count", "closed_recent", "closed_trades", "trades"])
    }

    var pnl: Double? {
        raw.fundDouble(["pnl", "pnl_usd", "realized_pnl", "total_pnl"])
    }

    var winRate: Double? {
        raw.fundDouble(["win_rate", "winrate", "win_rate_pct"])
    }
}

struct FundTradePositionDTO: Decodable, Identifiable {
    let id: String
    let desk: String?
    let symbol: String?
    let strategy: String?
    let side: String?
    let quantity: Double?
    let sizeDollars: Double?
    let entryPrice: Double?
    let currentPrice: Double?
    let stop: Double?
    let target: Double?
    let pnl: Double?
    let openedAt: String?
    let status: String?
    let raw: [String: FundJSONValue]

    init(from decoder: Decoder) throws {
        let raw = FundJSONValue.objectPayload(from: decoder)
        id = raw.fundString(["id", "position_id", "trade_id", "order_id"]) ?? UUID().uuidString
        desk = raw.fundString(["desk", "route", "owner"])
        symbol = raw.fundString(["symbol", "ticker", "instrument", "asset"])
        strategy = raw.fundString(["strategy", "strategy_id", "model", "setup", "algo"])
        side = raw.fundString(["side", "direction"])
        quantity = raw.fundDouble(["quantity", "qty", "size", "shares", "contracts"])
        sizeDollars = raw.fundDouble(["size_dollars", "notional_usd", "position_value_usd"])
        entryPrice = raw.fundDouble(["entry_price", "entry", "avg_entry_price", "average_entry"])
        currentPrice = raw.fundDouble(["current_price", "mark_price", "last_price", "price"])
        stop = raw.fundDouble(["stop", "stop_loss", "stop_price", "protective_stop"])
            ?? raw.fundNestedDouble(parentKeys: ["stops", "risk"], childKeys: ["stop", "stop_loss", "price"])
        target = raw.fundDouble(["target", "take_profit", "target_price"])
        pnl = raw.fundDouble(["pnl", "pnl_usd", "unrealized_pnl", "unrealized_pnl_usd"])
        openedAt = raw.fundString(["opened_at", "entry_at", "entry_time", "created_at"])
        status = raw.fundString(["status", "state"])
        self.raw = raw
    }

    func matchesDesk(_ deskId: String) -> Bool {
        (desk ?? "").lowercased() == deskId.lowercased()
    }
}

struct FundClosedTradeDTO: Decodable, Identifiable {
    let id: String
    let desk: String?
    let symbol: String?
    let strategy: String?
    let side: String?
    let quantity: Double?
    let entryPrice: Double?
    let exitPrice: Double?
    let stop: Double?
    let pnl: Double?
    let pnlPercent: Double?
    let openedAt: String?
    let closedAt: String?
    let reason: String?
    let raw: [String: FundJSONValue]

    init(from decoder: Decoder) throws {
        let raw = FundJSONValue.objectPayload(from: decoder)
        id = raw.fundString(["id", "trade_id", "position_id", "order_id"]) ?? UUID().uuidString
        desk = raw.fundString(["desk", "route", "owner"])
        symbol = raw.fundString(["symbol", "ticker", "instrument", "asset"])
        strategy = raw.fundString(["strategy", "strategy_id", "model", "setup", "algo"])
        side = raw.fundString(["side", "direction"])
        quantity = raw.fundDouble(["quantity", "qty", "size", "shares", "contracts"])
        entryPrice = raw.fundDouble(["entry_price", "entry", "avg_entry_price", "average_entry"])
        exitPrice = raw.fundDouble(["exit_price", "exit", "close_price", "closed_price"])
        stop = raw.fundDouble(["stop", "stop_loss", "stop_price", "protective_stop"])
        pnl = raw.fundDouble(["pnl", "pnl_usd", "realized_pnl", "realized_pnl_usd"])
        pnlPercent = raw.fundDouble(["pnl_pct", "pnl_percent", "return_pct"])
        openedAt = raw.fundString(["opened_at", "entry_at", "entry_time", "created_at"])
        closedAt = raw.fundString(["closed_at", "exit_at", "exit_time", "updated_at"])
        reason = raw.fundString(["reason", "exit_reason", "note", "status"])
        self.raw = raw
    }

    func matchesDesk(_ deskId: String) -> Bool {
        (desk ?? "").lowercased() == deskId.lowercased()
    }
}

enum FundTradesStage: String {
    case paper
    case trialLive
    case scaleLive

    init(liveTradingRaw: String?, liveTrading: Bool?, tradingActionable: Bool?) {
        let raw = (liveTradingRaw ?? "").lowercased().replacingOccurrences(of: "-", with: "_")
        if raw.contains("scale") || raw == "scale_live" {
            self = .scaleLive
        } else if raw.contains("trial") || (liveTrading == true && tradingActionable != true) {
            self = .trialLive
        } else if liveTrading == true && tradingActionable == true {
            self = .scaleLive
        } else {
            self = .paper
        }
    }

    var label: String {
        switch self {
        case .paper: return "Paper"
        case .trialLive: return "Trial-live"
        case .scaleLive: return "Scale-live"
        }
    }

    var icon: String {
        switch self {
        case .paper: return "doc.text"
        case .trialLive: return "waveform.path.ecg"
        case .scaleLive: return "arrow.up.forward.circle"
        }
    }
}

enum FundTradesFormat {
    static func duration(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s stale" }
        if seconds < 3_600 { return "\(seconds / 60)m stale" }
        if seconds < 86_400 { return "\(seconds / 3_600)h stale" }
        return "\(seconds / 86_400)d stale"
    }

    static func relativeTime(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "pending" }
        guard let date = parseDate(value) else { return value }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: value) {
            return date
        }

        let day = DateFormatter()
        day.calendar = Calendar(identifier: .iso8601)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: value)
    }

    static func compactNumber(_ value: Double?) -> String {
        guard let value else { return "-" }
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    static func money(_ value: Double?) -> String {
        guard let value else { return "-" }
        let sign = value > 0 ? "+" : ""
        return "\(sign)$\(String(format: "%.2f", value))"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "-" }
        let normalized = abs(value) <= 1 ? value * 100 : value
        return "\(String(format: "%.1f", normalized))%"
    }
}

indirect enum FundJSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: FundJSONValue])
    case array([FundJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: FundJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([FundJSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    static func objectPayload(from decoder: Decoder) -> [String: FundJSONValue] {
        guard let value = try? FundJSONValue(from: decoder) else { return [:] }
        return value.objectValue ?? [:]
    }

    var objectValue: [String: FundJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value.rounded() == value {
                return String(format: "%.0f", value)
            }
            return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value):
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        case .number(let value): return value != 0
        default: return nil
        }
    }
}

private extension KeyedDecodingContainer {
    func fundString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func fundInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func fundBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    func fundStringArray(forKey key: Key) -> [String]? {
        if let value = try? decodeIfPresent([String].self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return [value]
        }
        if let value = try? decodeIfPresent([FundJSONValue].self, forKey: key) {
            return value.compactMap { $0.stringValue }
        }
        return nil
    }
}

private extension Dictionary where Key == String, Value == FundJSONValue {
    func fundValue(_ keys: [String]) -> FundJSONValue? {
        for key in keys {
            if let exact = self[key] {
                return exact
            }
            if let match = first(where: { $0.key.lowercased() == key.lowercased() })?.value {
                return match
            }
        }
        return nil
    }

    func fundString(_ keys: [String]) -> String? {
        fundValue(keys)?.stringValue
    }

    func fundInt(_ keys: [String]) -> Int? {
        fundValue(keys)?.intValue
    }

    func fundDouble(_ keys: [String]) -> Double? {
        fundValue(keys)?.doubleValue
    }

    func fundNestedDouble(parentKeys: [String], childKeys: [String]) -> Double? {
        guard let object = fundValue(parentKeys)?.objectValue else { return nil }
        return object.fundDouble(childKeys)
    }
}

#if DEBUG
extension FundRouteFeedDTO {
    static func previewDecoded(from json: String, fallbackReason: String) -> FundRouteFeedDTO {
        guard let data = json.data(using: .utf8) else {
            return .degraded(reason: fallbackReason, quality: "malformed")
        }

        do {
            return try JSONDecoder().decode(FundRouteFeedDTO.self, from: data)
        } catch {
            return .degraded(reason: fallbackReason, quality: "malformed")
        }
    }

    static var synthAvailablePreview: FundRouteFeedDTO {
        previewDecoded(from: """
        {
          "status": "available",
          "quality": "stale",
          "stale": true,
          "as_of": "2026-07-09T21:30:00Z",
          "staleness_seconds": 742,
          "data": {
            "schema_version": "fund_routes_trades/v0",
            "route": "/api/v1/fund/routes/trades",
            "generated_at": "2026-07-09T21:30:00Z",
            "live_trading": false,
            "runtime_integration": "SYNTH-preview-only",
            "trading_actionable": false,
            "status": "available",
            "source_artifact": {
              "stitch": "SYNTH-stitch-artifact.json",
              "lilo": "SYNTH-lilo-artifact.json"
            },
            "blocked_controls": [
              "SYNTH-no-order-entry",
              "SYNTH-no-position-mutation"
            ],
            "payload": {
              "as_of": "2026-07-09T21:30:00Z",
              "desks": {
                "stitch": {
                  "status": "SYNTH-active",
                  "mode": "SYNTH-paper",
                  "open_position_count": 2,
                  "closed_recent_count": 1,
                  "pnl_usd": 123.45,
                  "strategies": {
                    "SYNTH-breakout": {
                      "open_count": 1,
                      "closed_count": 1,
                      "pnl_usd": 88.12,
                      "win_rate": 0.55
                    },
                    "SYNTH-mean-revert": {
                      "open_count": 1,
                      "closed_count": 0,
                      "pnl_usd": 35.33,
                      "win_rate": 0.50
                    }
                  }
                },
                "lilo": {
                  "status": "SYNTH-watch",
                  "mode": "SYNTH-paper",
                  "open_position_count": 1,
                  "closed_recent_count": 1,
                  "pnl_usd": -12.34,
                  "strategies": {
                    "SYNTH-gap-fade": {
                      "open_count": 1,
                      "closed_count": 1,
                      "pnl_usd": -12.34,
                      "win_rate": 0.40
                    }
                  }
                }
              },
              "open_positions": [
                {
                  "id": "SYNTH-STITCH-OPEN-1",
                  "desk": "stitch",
                  "symbol": "SYNTH-STITCH-A",
                  "strategy": "SYNTH-breakout",
                  "side": "long",
                  "qty": 12,
                  "entry_price": 10.20,
                  "current_price": 10.90,
                  "stop_loss": 9.80,
                  "target_price": 11.40,
                  "unrealized_pnl_usd": 8.40,
                  "opened_at": "2026-07-09T20:44:00Z",
                  "status": "SYNTH-open"
                },
                {
                  "id": "SYNTH-STITCH-OPEN-2",
                  "desk": "stitch",
                  "symbol": "SYNTH-STITCH-B",
                  "strategy": "SYNTH-mean-revert",
                  "side": "long",
                  "qty": 8,
                  "entry_price": 22.10,
                  "stop_loss": 21.25,
                  "unrealized_pnl_usd": 3.10,
                  "opened_at": "2026-07-09T20:58:00Z"
                },
                {
                  "id": "SYNTH-LILO-OPEN-1",
                  "desk": "lilo",
                  "symbol": "SYNTH-LILO-A",
                  "strategy": "SYNTH-gap-fade",
                  "side": "short",
                  "qty": 5,
                  "entry_price": 31.50,
                  "stop_loss": 32.10,
                  "target_price": 30.30,
                  "unrealized_pnl_usd": -2.25,
                  "opened_at": "2026-07-09T21:05:00Z"
                }
              ],
              "closed_recent": [
                {
                  "id": "SYNTH-STITCH-CLOSED-1",
                  "desk": "stitch",
                  "symbol": "SYNTH-STITCH-C",
                  "strategy": "SYNTH-breakout",
                  "side": "long",
                  "qty": 6,
                  "entry_price": 14.00,
                  "exit_price": 14.72,
                  "realized_pnl_usd": 4.32,
                  "closed_at": "2026-07-09T21:12:00Z",
                  "reason": "SYNTH-target"
                },
                {
                  "id": "SYNTH-LILO-CLOSED-1",
                  "desk": "lilo",
                  "symbol": "SYNTH-LILO-B",
                  "strategy": "SYNTH-gap-fade",
                  "side": "short",
                  "qty": 4,
                  "entry_price": 18.20,
                  "exit_price": 18.44,
                  "realized_pnl_usd": -0.96,
                  "closed_at": "2026-07-09T21:18:00Z",
                  "reason": "SYNTH-stop"
                }
              ]
            }
          }
        }
        """, fallbackReason: "Synthetic preview envelope could not be decoded.")
    }

    static var synthMalformedPreview: FundRouteFeedDTO {
        previewDecoded(
            from: #"{"status":"available","quality":["SYNTH-wrong-shape"],"data":{"payload":{"open_positions":"SYNTH-not-array"}"#,
            fallbackReason: "Malformed synthetic preview envelope rendered as degraded."
        )
    }
}
#endif
