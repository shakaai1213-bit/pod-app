import Foundation

struct FundCockpitFeedDTO: Decodable {
    let status: String
    let quality: String
    let asOf: String?
    let stale: Bool
    let degradedReason: String?
    let data: FundCockpitEnvelopeDTO?

    enum CodingKeys: String, CodingKey {
        case status, quality, stale, data
        case asOf = "as_of"
        case degradedReason = "degraded_reason"
    }

    var isAvailable: Bool {
        status == "available" && quality == "available" && !stale
            && data?.schemaVersion == "fund_routes_cockpit/v0"
            && data?.route == "fund.cockpit"
            && data?.payload != nil
    }

    var displayAsOf: String? {
        data?.payload?.generatedAt ?? asOf ?? data?.generatedAt
    }
}

struct FundCockpitEnvelopeDTO: Decodable {
    let schemaVersion: String
    let route: String
    let generatedAt: String
    let payload: FundCockpitPayloadDTO?

    enum CodingKeys: String, CodingKey {
        case route, payload
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
    }
}

struct FundCockpitPayloadDTO: Decodable {
    let generatedAt: String?
    let execution: [FundCockpitExecutionDTO]
    let engines: FundCockpitEnginesDTO
    let predictors: FundCockpitPredictorsDTO?
    let shadows: FundCockpitShadowsDTO?
    let runCapture: FundCockpitRunCaptureDTO?
    let orcaSync: FundCockpitSyncDTO?
    let chieffish: FundCockpitChieffishDTO?
    let alerts: [FundCockpitAlertDTO]

    enum CodingKeys: String, CodingKey {
        case execution, engines, predictors, shadows, chieffish, alerts
        case generatedAt = "generated_at"
        case orcaSync = "orca_sync"
        case runCapture = "run_capture"
    }
}

struct FundCockpitExecutionDTO: Decodable, Identifiable {
    let label: String
    let alive: Bool?

    var id: String { label }
}

struct FundCockpitEnginesDTO: Decodable {
    let generatedAt: String?
    let rows: [FundCockpitEngineDTO]

    enum CodingKeys: String, CodingKey {
        case rows
        case generatedAt = "generated_at"
    }
}

struct FundCockpitEngineDTO: Decodable, Identifiable {
    let engine: String
    let pillar: String?
    let verdict: String

    var id: String { engine }
}

struct FundCockpitPredictorsDTO: Decodable {
    let predictors: [String: FundCockpitPredictorDTO]
}

struct FundCockpitPredictorDTO: Decodable {
    let label: String?
    let verdict: String?
    let nResolved: Int?
    let accuracy: Double?
    let randomBaseline: Double?
    let skill: String?
    let baselineKind: String?

    enum CodingKeys: String, CodingKey {
        case label, verdict, accuracy, skill
        case nResolved = "n_resolved"
        case randomBaseline = "random_baseline"
        case baselineKind = "baseline_kind"
    }
}

struct FundCockpitShadowsDTO: Decodable {
    let ok: Bool?
    let candidates: [String: FundCockpitShadowDTO]
    let problems: [String]?
}

struct FundCockpitRunCaptureDTO: Decodable {
    let symbols: [String: FundCockpitCaptureSymbolDTO]
}

struct FundCockpitCaptureSymbolDTO: Decodable {
    let runDetected: Bool?

    enum CodingKeys: String, CodingKey {
        case runDetected = "run_detected"
    }
}

struct FundCockpitShadowDTO: Decodable {
    let status: String?
    let stage: String?
    let tradeCount: Int?

    enum CodingKeys: String, CodingKey {
        case status, stage
        case tradeCount = "trade_count"
    }
}

struct FundCockpitSyncDTO: Decodable {
    let total: Int
    let inSync: Int
    let problems: [FundCockpitSyncProblemDTO]

    enum CodingKeys: String, CodingKey {
        case total, problems
        case inSync = "in_sync"
    }
}

struct FundCockpitSyncProblemDTO: Decodable, Identifiable {
    let surface: String?
    let verdict: String?

    var id: String { surface ?? "unknown" }
}

struct FundCockpitChieffishDTO: Decodable {
    let ok: Bool?
    let pendingAfter: Int?

    enum CodingKeys: String, CodingKey {
        case ok
        case pendingAfter = "pending_after"
    }
}

struct FundCockpitAlertDTO: Decodable, Identifiable {
    let severity: String
    let name: String

    var id: String { "\(severity):\(name)" }
}
