import Foundation
import Testing
@testable import PodContracts

@Test("Standards envelope tolerates omitted version history")
func standardsEnvelopeDecodes() throws {
    let response = try makeDecoder().decode(
        StandardListResponse.self,
        from: fixture("standards-live")
    )

    #expect(response.items.count == 1)
    #expect(response.items[0].authorName == "Captain")
    #expect(response.items[0].versions.isEmpty)
}

@Test("Control Room accepts keyed section payloads")
func controlRoomKeyedSectionsDecode() throws {
    let digest = try makeDecoder().decode(
        ControlRoomDigestDTO.self,
        from: fixture("control-room-live")
    )

    #expect(digest.sections.map(\.id) == ["activation", "compute"])
    #expect(digest.sections[0].status == "needs_attention")
    #expect(digest.sections[0].summary?.contains("2") == true)
}

@Test("Maker ignores array-valued discovery details")
func makerReadyIdeaDecodes() throws {
    let ideas = try makeDecoder().decode([ReadyIdea].self, from: fixture("maker-ready-live"))

    #expect(ideas.count == 1)
    #expect(ideas[0].scope == "Add a live stage badge.")
    #expect(ideas[0].effortEstimate == "M")
    #expect(ideas[0].rationale == "The queue needs visible progress.")
}

@Test("Fund degraded state hides backend exception names")
func fundDegradedReasonIsCaptainSafe() throws {
    let feed = try makeDecoder().decode(FundRouteFeedDTO.self, from: fixture("fund-trades-degraded-live"))

    #expect(feed.normalizedQuality == "unavailable")
    #expect(feed.userFacingDegradedReason == "Trade feed is awaiting delivery to ORCA Mini.")
    #expect(FundTradesFormat.relativeTime(nil) == "pending")
}

@Test("Fund available route decodes the protected v0 read model")
func fundAvailableRouteDecodes() throws {
    let feed = try makeDecoder().decode(FundRouteFeedDTO.self, from: fixture("fund-trades-available-live"))
    let payload = try #require(feed.data?.payload)
    let stitch = try #require(payload.desks.first { $0.id == "stitch" })
    let strategy = try #require(stitch.strategyAggregates.first)
    let position = try #require(payload.openPositions.first)
    let closed = try #require(payload.closedRecent.first)

    #expect(feed.hasPayloadData)
    #expect(feed.stage == .paper)
    #expect(payload.totalOpenCount == 1)
    #expect(strategy.displayName == "test_alpha")
    #expect(strategy.closedCount == 1)
    #expect(strategy.winRate == 100)
    #expect(position.strategy == "test_alpha")
    #expect(position.sizeDollars == 25)
    #expect(position.openedAt == "2026-07-09T22:00:00Z")
    #expect(closed.strategy == "test_alpha")
    #expect(closed.pnlPercent == 0.1)
    #expect(closed.closedAt == "2026-07-09T21:00:00Z")
}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = internet.date(from: value) { return date }
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: value) { return date }

        let local = DateFormatter()
        local.calendar = Calendar(identifier: .iso8601)
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone(secondsFromGMT: 0)
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = local.date(from: value) { return date }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ORCA date")
    }
    return decoder
}
