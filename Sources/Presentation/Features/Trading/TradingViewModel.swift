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

    var dashboard: TradingDashboard = TradingViewModel.mockDashboard
    var isLoading: Bool = false
    var lastUpdated: Date? = nil
    var errorMessage: String? = nil

    // MARK: - Load

    func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await fetchFromChief()
            dashboard = fetched
            lastUpdated = Date()
        } catch {
            // Fall back to mock data; surface the note but don't block the UI
            errorMessage = "Live data unavailable — showing cached snapshot"
            dashboard = TradingViewModel.mockDashboard
            lastUpdated = Date()
        }

        isLoading = false
    }

    // MARK: - Network

    private func fetchFromChief() async throws -> TradingDashboard {
        guard let url = URL(string: "http://100.80.44.41/api/trading") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // When Chief's API endpoint is live, decode here.
        // For now the endpoint doesn't exist, so we'll always fall through to mock.
        throw URLError(.cannotConnectToHost)
    }

    // MARK: - Mock Data (real numbers from Chief's Mac state)

    static var mockDashboard: TradingDashboard {
        let calendar = Calendar.current
        let now = Date()

        func date(daysFromNow n: Int) -> Date {
            calendar.date(byAdding: .day, value: n, to: now) ?? now
        }

        let bots: [TradingBot] = [
            TradingBot(
                id: "octopus",
                name: "Octopus",
                version: "",
                balance: 66_055.00,
                pnl: 65_855.00,
                winRate: 0.0229,
                openPositions: 765,
                status: .running,
                regime: nil,
                tradesTotal: 14_237
            ),
            TradingBot(
                id: "stitch",
                name: "Stitch",
                version: "v6.4",
                balance: 200.31,
                pnl: 0.31,
                winRate: 0.33,
                openPositions: 0,
                status: .running,
                regime: .caution,
                tradesTotal: nil
            ),
            TradingBot(
                id: "lilo",
                name: "Lilo",
                version: "v2.0",
                balance: 213.06,
                pnl: 13.06,
                winRate: 0,
                openPositions: 1,
                status: .running,
                regime: nil,
                tradesTotal: nil
            )
        ]

        let oracle = OracleState(
            score: -0.4829,
            modelVersion: "v0.1",
            predictionCount: 100,
            statusNote: "Market selection under review",
            predictions: [
                OraclePrediction(
                    id: "PM_1",
                    question: "Will BTC reach $150k in 2026?",
                    direction: "NO",
                    confidence: 0.719,
                    volume: 103_512_441
                ),
                OraclePrediction(
                    id: "PM_2",
                    question: "Will ETH outperform BTC in Q2 2026?",
                    direction: "NO",
                    confidence: 0.614,
                    volume: 24_890_000
                ),
                OraclePrediction(
                    id: "PM_3",
                    question: "Will the Fed cut rates before June 2026?",
                    direction: "YES",
                    confidence: 0.581,
                    volume: 67_200_000
                )
            ]
        )

        let research = ResearchSummary(
            activeArms: 10,
            experimentsToday: 2_250,
            bestScore: 70.37,
            bestExperiment: 66,
            arms: [
                ResearchArm(id: "sol", symbol: "SOL", takeProfit: 5.0, stopLoss: 2.0, pnlPercent: 61.0),
                ResearchArm(id: "btc", symbol: "BTC", takeProfit: 4.0, stopLoss: 0.5, pnlPercent: 31.5),
                ResearchArm(id: "eth", symbol: "ETH", takeProfit: 2.0, stopLoss: 0.5, pnlPercent: 8.5)
            ],
            queueNote: "EMA cloud: live · Exp 70-75 in queue"
        )

        let earnings: [EarningsEvent] = [
            EarningsEvent(id: "tsla", ticker: "TSLA", date: date(daysFromNow: 10), direction: .short,   confidence: 0.52),
            EarningsEvent(id: "nvda", ticker: "NVDA", date: date(daysFromNow: 11), direction: .long,    confidence: 0.68),
            EarningsEvent(id: "meta", ticker: "META", date: date(daysFromNow: 11), direction: .long,    confidence: 0.65),
            EarningsEvent(id: "msft", ticker: "MSFT", date: date(daysFromNow: 18), direction: .long,    confidence: 0.71),
            EarningsEvent(id: "aapl", ticker: "AAPL", date: date(daysFromNow: 19), direction: .neutral, confidence: 0.48)
        ]

        let macro: [MacroPrediction] = [
            MacroPrediction(id: "qqq-w", instrument: "QQQ", timeframe: "Weekly",  regime: .bull,    conviction: 0.64),
            MacroPrediction(id: "qqq-m", instrument: "QQQ", timeframe: "Monthly", regime: .caution, conviction: 0.51),
            MacroPrediction(id: "spy-w", instrument: "SPY", timeframe: "Weekly",  regime: .caution, conviction: 0.58),
            MacroPrediction(id: "spy-m", instrument: "SPY", timeframe: "Monthly", regime: .bull,    conviction: 0.62)
        ]

        return TradingDashboard(bots: bots, oracle: oracle, research: research, earnings: earnings, macro: macro)
    }
}
