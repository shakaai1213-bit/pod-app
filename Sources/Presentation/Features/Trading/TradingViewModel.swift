import Foundation
import Observation

// MARK: - Models

struct TradingBot: Identifiable {
    let id: String
    let name: String
    let version: String
    let balance: Double
    let pnl: Double
    let winRate: Double
    let openPositions: Int
    let status: BotStatus
    let regime: MarketRegime?
    let tradesTotal: Int?

    enum BotStatus: String {
        case running, paused, stopped, error
    }
}

enum MarketRegime: String {
    case bull = "BULL"
    case caution = "CAUTION"
    case bear = "BEAR"
}

struct OraclePrediction: Identifiable {
    let id: String
    let question: String
    let direction: String     // "YES" / "NO"
    let confidence: Double    // 0.0 – 1.0
    let volume: Int
}

struct OracleState {
    let score: Double           // -1.0 to +1.0
    let modelVersion: String
    let predictionCount: Int
    let statusNote: String
    let predictions: [OraclePrediction]
}

struct ResearchArm: Identifiable {
    let id: String
    let symbol: String
    let takeProfit: Double      // %
    let stopLoss: Double        // %
    let pnlPercent: Double
}

struct ResearchSummary {
    let activeArms: Int
    let experimentsToday: Int
    let bestScore: Double
    let bestExperiment: Int
    let arms: [ResearchArm]
    let queueNote: String
}

struct EarningsEvent: Identifiable {
    let id: String
    let ticker: String
    let date: Date
    let direction: EarningsDirection
    let confidence: Double       // 0.0 – 1.0

    enum EarningsDirection: String {
        case long = "LONG"
        case short = "SHORT"
        case neutral = "NEUTRAL"
    }
}

struct MacroPrediction: Identifiable {
    let id: String
    let instrument: String      // "QQQ" / "SPY"
    let timeframe: String       // "Weekly" / "Monthly"
    let regime: MarketRegime
    let conviction: Double       // 0.0 – 1.0
}

struct EarningsQualitySurface {
    let generatedAt: String?
    let policy: String
    let topTen: [EarningsQualityCandidate]
    let chartSetups: [ChartSetupLevel]
    let sectorTrends: [SectorETFTrend]
    let gates: [EvidenceGate]
    let evidenceRefs: [String]
}

struct EarningsQualityCandidate: Identifiable {
    let id: String
    let ticker: String
    let score: Double?
    let headline: String?
    let qualityNote: String?
}

struct ChartSetupLevel: Identifiable {
    let id: String
    let ticker: String
    let setup: String?
    let support: Double?
    let resistance: Double?
    let stop: Double?
    let target: Double?
}

struct SectorETFTrend: Identifiable {
    let id: String
    let symbol: String
    let trend: String
    let score: Double?
    let note: String?
}

struct EvidenceGate: Identifiable {
    let id: String
    let name: String
    let status: String
    let note: String?
}

struct MarketPredictionBrief {
    let generatedAt: String?
    let asOfDate: String?
    let marketRows: [MarketTrendPrediction]
    let earningsRows: [WeekAheadEarningsPrediction]
    let calibration: PredictionCalibrationSummary?
}

struct MarketTrendPrediction: Identifiable {
    let id: String
    let symbol: String
    let name: String?
    let assetClass: String?
    let lastPrice: Double?
    let return30d: Double?
    let return60d: Double?
    let return90d: Double?
    let prediction30d: String?
    let prediction60d: String?
    let prediction90d: String?
    let confidence30d: Double?
    let confidence60d: Double?
    let confidence90d: Double?
}

struct WeekAheadEarningsPrediction: Identifiable {
    let id: String
    let symbol: String
    let companyName: String?
    let sector: String?
    let earningsDate: String?
    let daysUntil: Int?
    let prediction: String?
    let confidence: Double?
    let qualityScore: Double?
    let epsEstimate: Double?
    let chartSetup: String?
    let lastPrice: Double?
}

struct PredictionCalibrationSummary {
    let totalPredictions: Int
    let resolved: Int
    let unresolved: Int
    let accuracy: Double?
    let read: String?
}

struct PredictionRadar {
    let generatedAt: String?
    let status: String
    let marketStaleCount: Int
    let marketPredictionCounts: [String: Int]
    let earningsDueCount: Int
    let feedbackRequestCount: Int
    let feedbackByOwner: [String: Int]
    let highPriority: [PredictionRadarRequest]
    let computeRunId: String?
    let computeStatus: String?
    let computeBackend: String?
}

struct PredictionRadarRequest: Identifiable {
    let id: String
    let owner: String?
    let priority: String?
    let title: String?
}

struct TradingDashboard {
    let bots: [TradingBot]
    let oracle: OracleState
    let research: ResearchSummary
    let earnings: [EarningsEvent]
    let macro: [MacroPrediction]
}

// MARK: - ViewModel

@MainActor
@Observable
final class TradingViewModel {

    var dashboard: TradingDashboard = TradingDashboard.empty
    var isLoading: Bool = false
    var lastUpdated: Date? = nil
    var errorMessage: String? = nil
    var isSnapshot: Bool = true
    var earningsQuality: EarningsQualitySurface? = nil
    var earningsQualityError: String? = nil
    var marketPredictionBrief: MarketPredictionBrief? = nil
    var marketPredictionError: String? = nil
    var predictionRadar: PredictionRadar? = nil
    var predictionRadarError: String? = nil

    // MARK: - Load

    func loadData() async {
        isLoading = true
        errorMessage = nil
        earningsQualityError = nil
        marketPredictionError = nil
        predictionRadarError = nil

        do {
            let landing: FundLanding = try await APIClient.shared.get(path: "/api/v1/fund/landing")
            guard landing.isAvailable else {
                throw APIError(code: 503, message: landing.degradedReason ?? "Fund landing degraded")
            }
            let fetched = TradingDashboard.fundLanding(landing)
            dashboard = fetched
            isSnapshot = false
            lastUpdated = Date()
        } catch {
            errorMessage = "ORCA Fund landing unavailable. Pod is not showing direct Chief data or snapshot financials."
            dashboard = TradingDashboard.empty
            isSnapshot = true
            lastUpdated = Date()
        }

        await loadEarningsQuality()
        await loadMarketPredictionBrief()
        await loadPredictionRadar()
        isLoading = false
    }

    private func loadEarningsQuality() async {
        do {
            let dto: EarningsQualitySurfaceDTO = try await APIClient.shared.get(path: "/api/v1/research/earnings-quality/latest")
            earningsQuality = dto.toDomain()
            earningsQualityError = nil
        } catch let apiError as APIError where apiError.code == 404 {
            earningsQuality = nil
            earningsQualityError = "Waiting for ORCA /api/v1/research/earnings-quality/latest."
        } catch {
            earningsQuality = nil
            earningsQualityError = "Earnings quality research is unavailable from ORCA."
        }
    }

    private func loadMarketPredictionBrief() async {
        do {
            let dto: MarketPredictionBriefDTO = try await APIClient.shared.get(path: "/api/v1/research/predictions/market-brief/latest")
            marketPredictionBrief = dto.toDomain()
            marketPredictionError = nil
        } catch let apiError as APIError where apiError.code == 404 {
            marketPredictionBrief = nil
            marketPredictionError = "Waiting for ORCA /api/v1/research/predictions/market-brief/latest."
        } catch {
            marketPredictionBrief = nil
            marketPredictionError = "Market prediction brief is unavailable from ORCA."
        }
    }

    private func loadPredictionRadar() async {
        do {
            let dto: PredictionRadarDTO = try await APIClient.shared.get(path: "/api/v1/research/predictions/radar/latest")
            predictionRadar = dto.toDomain()
            predictionRadarError = nil
        } catch let apiError as APIError where apiError.code == 404 {
            predictionRadar = nil
            predictionRadarError = "Waiting for ORCA /api/v1/research/predictions/radar/latest."
        } catch {
            predictionRadar = nil
            predictionRadarError = "Prediction radar is unavailable from ORCA."
        }
    }
}

extension TradingDashboard {
    static var empty: TradingDashboard {
        TradingDashboard(
            bots: [],
            oracle: OracleState(score: 0, modelVersion: "ORCA Fund", predictionCount: 0, statusNote: "No ORCA Fund landing available.", predictions: []),
            research: ResearchSummary(activeArms: 0, experimentsToday: 0, bestScore: 0, bestExperiment: 0, arms: [], queueNote: "Fund research details are not exposed through ORCA yet."),
            earnings: [],
            macro: []
        )
    }

    static func fundLanding(_ landing: FundLanding) -> TradingDashboard {
        let bot = TradingBot(
            id: "chief-fund",
            name: "Chief Fund",
            version: landing.schemaVersion,
            balance: landing.accountUsd ?? 0,
            pnl: landing.netPnlUsd ?? 0,
            winRate: landing.sharpe ?? 0,
            openPositions: 0,
            status: landing.gateReady == true ? .running : .paused,
            regime: landing.gateReady == true ? .bull : .caution,
            tradesTotal: landing.closedTrades
        )

        let oracle = OracleState(
            score: landing.gateReady == true ? 1 : -1,
            modelVersion: landing.schemaVersion,
            predictionCount: 0,
            statusNote: landing.headline ?? landing.readiness ?? "Fund landing available from ORCA.",
            predictions: []
        )

        let research = ResearchSummary(
            activeArms: 1,
            experimentsToday: landing.closedTrades ?? 0,
            bestScore: landing.sharpe ?? 0,
            bestExperiment: 0,
            arms: [],
            queueNote: landing.blockers.isEmpty ? "No blockers reported by Fund landing." : landing.blockers.joined(separator: " · ")
        )

        return TradingDashboard(bots: [bot], oracle: oracle, research: research, earnings: [], macro: [])
    }
}

// MARK: - API DTOs (snake_case wire format → domain models)

private struct TradingDashboardDTO: Decodable {
    let updated_at: String
    let bots:       [TradingBotDTO]
    let oracle:     OracleStateDTO
    let research:   ResearchSummaryDTO
    let earnings:   [EarningsEventDTO]
    let macro:      [MacroPredictionDTO]

    func toDomain() -> TradingDashboard {
        TradingDashboard(
            bots:     bots.map { $0.toDomain() },
            oracle:   oracle.toDomain(),
            research: research.toDomain(),
            earnings: earnings.compactMap { $0.toDomain() },
            macro:    macro.compactMap { $0.toDomain() }
        )
    }
}

private struct TradingBotDTO: Decodable {
    let id:              String
    let name:            String
    let version:         String
    let balance:         Double
    let pnl:             Double
    let win_rate:        Double?
    let open_positions:  Int
    let status:          String
    let regime:          String?
    let trades_total:    Int?

    func toDomain() -> TradingBot {
        TradingBot(
            id:             id,
            name:           name,
            version:        version,
            balance:        balance,
            pnl:            pnl,
            winRate:        win_rate ?? 0,
            openPositions:  open_positions,
            status:         TradingBot.BotStatus(rawValue: status) ?? .stopped,
            regime:         regime.flatMap { MarketRegime(rawValue: $0) },
            tradesTotal:    trades_total
        )
    }
}

private struct OracleStateDTO: Decodable {
    let score:            Double
    let model_version:    String
    let prediction_count: Int
    let status_note:      String
    let predictions:      [OraclePredictionDTO]

    func toDomain() -> OracleState {
        OracleState(
            score:           score,
            modelVersion:    model_version,
            predictionCount: prediction_count,
            statusNote:      status_note,
            predictions:     predictions.map { $0.toDomain() }
        )
    }
}

private struct OraclePredictionDTO: Decodable {
    let id:         String
    let question:   String
    let direction:  String
    let confidence: Double
    let volume:     Int

    func toDomain() -> OraclePrediction {
        OraclePrediction(id: id, question: question,
                         direction: direction, confidence: confidence, volume: volume)
    }
}

private struct ResearchSummaryDTO: Decodable {
    let active_arms:       Int
    let experiments_today: Int
    let best_score:        Double
    let best_experiment:   Int
    let arms:              [ResearchArmDTO]
    let queue_note:        String

    func toDomain() -> ResearchSummary {
        ResearchSummary(
            activeArms:       active_arms,
            experimentsToday: experiments_today,
            bestScore:        best_score,
            bestExperiment:   best_experiment,
            arms:             arms.map { $0.toDomain() },
            queueNote:        queue_note
        )
    }
}

private struct ResearchArmDTO: Decodable {
    let id:          String
    let symbol:      String
    let take_profit: Double
    let stop_loss:   Double
    let pnl_percent: Double

    func toDomain() -> ResearchArm {
        ResearchArm(id: id, symbol: symbol,
                    takeProfit: take_profit, stopLoss: stop_loss, pnlPercent: pnl_percent)
    }
}

private struct EarningsEventDTO: Decodable {
    let id:         String
    let ticker:     String
    let date:       String   // "YYYY-MM-DD"
    let direction:  String
    let confidence: Double

    func toDomain() -> EarningsEvent? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        guard let d = fmt.date(from: date) else { return nil }
        return EarningsEvent(
            id:         id,
            ticker:     ticker,
            date:       d,
            direction:  EarningsEvent.EarningsDirection(rawValue: direction) ?? .neutral,
            confidence: confidence
        )
    }
}

private struct MacroPredictionDTO: Decodable {
    let id:         String
    let instrument: String
    let timeframe:  String
    let regime:     String
    let conviction: Double

    func toDomain() -> MacroPrediction? {
        guard let r = MarketRegime(rawValue: regime) else { return nil }
        return MacroPrediction(id: id, instrument: instrument,
                               timeframe: timeframe, regime: r, conviction: conviction)
    }
}

private struct EarningsQualitySurfaceDTO: Decodable {
    let generatedAt: String?
    let policy: String?
    let topTen: [EarningsQualityCandidateDTO]
    let chartSetups: [ChartSetupLevelDTO]
    let sectorTrends: [SectorETFTrendDTO]
    let gates: [EvidenceGateDTO]
    let evidenceRefs: [String]

    private enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case policy = "pod_policy"
        case topTen = "top_10"
        case candidates
        case chartSetups = "chart_setup_levels"
        case chartSetupLevels = "chart_setups"
        case sectorTrends = "sector_etf_trend_tape"
        case sectorETFTrendTape = "sector_trends"
        case gates
        case evidenceGates = "evidence_gates"
        case evidenceAndGates = "evidence_and_gates"
        case evidenceRefs = "evidence_refs"
        case sourceRefs = "source_refs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        policy = try container.decodeIfPresent(String.self, forKey: .policy)
        topTen = try container.decodeIfPresent([EarningsQualityCandidateDTO].self, forKey: .topTen)
            ?? container.decodeIfPresent([EarningsQualityCandidateDTO].self, forKey: .candidates)
            ?? []
        chartSetups = try container.decodeIfPresent([ChartSetupLevelDTO].self, forKey: .chartSetups)
            ?? container.decodeIfPresent([ChartSetupLevelDTO].self, forKey: .chartSetupLevels)
            ?? []
        sectorTrends = try container.decodeIfPresent([SectorETFTrendDTO].self, forKey: .sectorTrends)
            ?? container.decodeIfPresent([SectorETFTrendDTO].self, forKey: .sectorETFTrendTape)
            ?? []
        gates = try container.decodeIfPresent([EvidenceGateDTO].self, forKey: .gates)
            ?? container.decodeIfPresent([EvidenceGateDTO].self, forKey: .evidenceGates)
            ?? container.decodeIfPresent([EvidenceGateDTO].self, forKey: .evidenceAndGates)
            ?? []
        evidenceRefs = try container.decodeIfPresent([String].self, forKey: .evidenceRefs)
            ?? container.decodeIfPresent([String].self, forKey: .sourceRefs)
            ?? []
    }

    func toDomain() -> EarningsQualitySurface {
        EarningsQualitySurface(
            generatedAt: generatedAt,
            policy: policy ?? "Research only · not a trade signal",
            topTen: topTen.prefix(10).map { $0.toDomain() },
            chartSetups: chartSetups.map { $0.toDomain() },
            sectorTrends: sectorTrends.map { $0.toDomain() },
            gates: gates.map { $0.toDomain() },
            evidenceRefs: evidenceRefs
        )
    }
}

private struct EarningsQualityCandidateDTO: Decodable {
    let id: String?
    let ticker: String?
    let symbol: String?
    let score: Double?
    let qualityScore: Double?
    let headline: String?
    let title: String?
    let qualityNote: String?
    let note: String?
    let thesis: String?

    enum CodingKeys: String, CodingKey {
        case id, ticker, symbol, score, headline, title, note, thesis
        case qualityScore = "quality_score"
        case qualityNote = "quality_note"
    }

    func toDomain() -> EarningsQualityCandidate {
        let tickerValue = ticker ?? symbol ?? "?"
        return EarningsQualityCandidate(
            id: id ?? tickerValue,
            ticker: tickerValue,
            score: qualityScore ?? score,
            headline: headline ?? title,
            qualityNote: qualityNote ?? note ?? thesis
        )
    }
}

private struct ChartSetupLevelDTO: Decodable {
    let id: String?
    let ticker: String?
    let symbol: String?
    let setup: String?
    let support: Double?
    let resistance: Double?
    let stop: Double?
    let target: Double?

    func toDomain() -> ChartSetupLevel {
        let tickerValue = ticker ?? symbol ?? "?"
        return ChartSetupLevel(
            id: id ?? tickerValue,
            ticker: tickerValue,
            setup: setup,
            support: support,
            resistance: resistance,
            stop: stop,
            target: target
        )
    }
}

private struct SectorETFTrendDTO: Decodable {
    let id: String?
    let symbol: String?
    let ticker: String?
    let trend: String?
    let signal: String?
    let score: Double?
    let note: String?

    func toDomain() -> SectorETFTrend {
        let symbolValue = symbol ?? ticker ?? "?"
        return SectorETFTrend(
            id: id ?? symbolValue,
            symbol: symbolValue,
            trend: trend ?? signal ?? "unknown",
            score: score,
            note: note
        )
    }
}

private struct EvidenceGateDTO: Decodable {
    let id: String?
    let name: String?
    let gate: String?
    let status: String?
    let state: String?
    let note: String?
    let reason: String?

    func toDomain() -> EvidenceGate {
        let nameValue = name ?? gate ?? "Gate"
        return EvidenceGate(
            id: id ?? nameValue,
            name: nameValue,
            status: status ?? state ?? "unknown",
            note: note ?? reason
        )
    }
}

private struct MarketPredictionBriefDTO: Decodable {
    let generatedAt: String?
    let asOfDate: String?
    let podSurface: PredictionPodSurfaceDTO?
    let calibration: PredictionCalibrationDTO?

    private enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case asOfDate = "as_of_date"
        case podSurface = "pod_surface"
        case calibration
    }

    func toDomain() -> MarketPredictionBrief {
        MarketPredictionBrief(
            generatedAt: generatedAt,
            asOfDate: asOfDate,
            marketRows: podSurface?.marketRows ?? [],
            earningsRows: podSurface?.earningsRows ?? [],
            calibration: calibration?.toDomain()
        )
    }
}

private struct PredictionPodSurfaceDTO: Decodable {
    let marketRows: [MarketTrendPrediction]
    let earningsRows: [WeekAheadEarningsPrediction]

    private struct Card: Decodable {
        let id: String?
        let rows: [PredictionRowValue]?
        let summary: PredictionCalibrationDTO?
    }

    private enum CodingKeys: String, CodingKey {
        case cards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cards = try container.decodeIfPresent([Card].self, forKey: .cards) ?? []
        marketRows = cards.first(where: { $0.id == "market_30_60_90" })?.rows?.compactMap { $0.marketRow } ?? []
        earningsRows = cards.first(where: { $0.id == "week_ahead_earnings" })?.rows?.compactMap { $0.earningsRow } ?? []
    }
}

private struct PredictionRowValue: Decodable {
    let symbol: String?
    let name: String?
    let assetClass: String?
    let lastPrice: Double?
    let return30d: Double?
    let return60d: Double?
    let return90d: Double?
    let prediction30d: String?
    let prediction60d: String?
    let prediction90d: String?
    let confidence30d: Double?
    let confidence60d: Double?
    let confidence90d: Double?
    let companyName: String?
    let sector: String?
    let earningsDate: String?
    let daysUntil: Int?
    let prediction: String?
    let confidence: Double?
    let qualityScore: Double?
    let epsEstimate: Double?
    let chartSetup: String?

    private enum CodingKeys: String, CodingKey {
        case symbol, name, sector, prediction, confidence
        case assetClass = "asset_class"
        case lastPrice = "last_price"
        case return30d = "return_30d"
        case return60d = "return_60d"
        case return90d = "return_90d"
        case prediction30d = "prediction_30d"
        case prediction60d = "prediction_60d"
        case prediction90d = "prediction_90d"
        case confidence30d = "confidence_30d"
        case confidence60d = "confidence_60d"
        case confidence90d = "confidence_90d"
        case companyName = "company_name"
        case earningsDate = "earnings_date"
        case daysUntil = "days_until"
        case qualityScore = "quality_score"
        case epsEstimate = "eps_estimate"
        case chartSetup = "chart_setup"
    }

    var marketRow: MarketTrendPrediction? {
        guard let symbol else { return nil }
        return MarketTrendPrediction(
            id: symbol,
            symbol: symbol,
            name: name,
            assetClass: assetClass,
            lastPrice: lastPrice,
            return30d: return30d,
            return60d: return60d,
            return90d: return90d,
            prediction30d: prediction30d,
            prediction60d: prediction60d,
            prediction90d: prediction90d,
            confidence30d: confidence30d,
            confidence60d: confidence60d,
            confidence90d: confidence90d
        )
    }

    var earningsRow: WeekAheadEarningsPrediction? {
        guard let symbol else { return nil }
        return WeekAheadEarningsPrediction(
            id: "\(symbol)-\(earningsDate ?? "pending")",
            symbol: symbol,
            companyName: companyName,
            sector: sector,
            earningsDate: earningsDate,
            daysUntil: daysUntil,
            prediction: prediction,
            confidence: confidence,
            qualityScore: qualityScore,
            epsEstimate: epsEstimate,
            chartSetup: chartSetup,
            lastPrice: lastPrice
        )
    }
}

private struct PredictionCalibrationDTO: Decodable {
    let totalPredictions: Int?
    let resolved: Int?
    let unresolved: Int?
    let accuracy: Double?
    let read: String?

    private enum CodingKeys: String, CodingKey {
        case totalPredictions = "total_predictions"
        case resolved, unresolved, accuracy, read
    }

    func toDomain() -> PredictionCalibrationSummary {
        PredictionCalibrationSummary(
            totalPredictions: totalPredictions ?? 0,
            resolved: resolved ?? 0,
            unresolved: unresolved ?? 0,
            accuracy: accuracy,
            read: read
        )
    }
}

private struct PredictionRadarDTO: Decodable {
    let generatedAt: String?
    let status: String?
    let market: Market?
    let earnings: Earnings?
    let feedback: Feedback?
    let compute: Compute?

    private enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case status, market, earnings, feedback, compute
    }

    struct Market: Decodable {
        let staleCount: Int?
        let predictionCounts: [String: Int]?

        private enum CodingKeys: String, CodingKey {
            case staleCount = "stale_count"
            case predictionCounts = "prediction_counts"
        }
    }

    struct Earnings: Decodable {
        let dueOrLiveCount: Int?

        private enum CodingKeys: String, CodingKey {
            case dueOrLiveCount = "due_or_live_count"
        }
    }

    struct Feedback: Decodable {
        let requestCount: Int?
        let requestsByOwner: [String: Int]?
        let highPriority: [Request]?

        private enum CodingKeys: String, CodingKey {
            case requestCount = "request_count"
            case requestsByOwner = "requests_by_owner"
            case highPriority = "high_priority"
        }
    }

    struct Request: Decodable {
        let id: String?
        let owner: String?
        let priority: String?
        let title: String?

        func toDomain() -> PredictionRadarRequest {
            PredictionRadarRequest(
                id: id ?? title ?? UUID().uuidString,
                owner: owner,
                priority: priority,
                title: title
            )
        }
    }

    struct Compute: Decodable {
        let computeRunId: String?
        let status: String?
        let actualBackend: String?

        private enum CodingKeys: String, CodingKey {
            case computeRunId = "compute_run_id"
            case status
            case actualBackend = "actual_backend"
        }
    }

    func toDomain() -> PredictionRadar {
        PredictionRadar(
            generatedAt: generatedAt,
            status: status ?? "unknown",
            marketStaleCount: market?.staleCount ?? 0,
            marketPredictionCounts: market?.predictionCounts ?? [:],
            earningsDueCount: earnings?.dueOrLiveCount ?? 0,
            feedbackRequestCount: feedback?.requestCount ?? 0,
            feedbackByOwner: feedback?.requestsByOwner ?? [:],
            highPriority: feedback?.highPriority?.map { $0.toDomain() } ?? [],
            computeRunId: compute?.computeRunId,
            computeStatus: compute?.status,
            computeBackend: compute?.actualBackend
        )
    }
}
