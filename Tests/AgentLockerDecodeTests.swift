import XCTest
@testable import pod

final class AgentLockerDecodeTests: XCTestCase {
    func testMauiLiveLockerCockpitFixtureDecodes() throws {
        let data = try Data(contentsOf: fixtureURL(named: "maui-locker-cockpit-live-2026-06-20"))

        do {
            let locker = try JSONDecoder().decode(AgentLockerDTO.self, from: data)
            XCTAssertEqual(locker.schema, "orca.agent-locker-cockpit.v1")
            XCTAssertEqual(locker.agentProfile?.name, "maui")
        } catch {
            XCTFail("AgentLockerDTO decode failed: \(Self.describeDecodingError(error))")
        }
    }

    private func fixtureURL(named name: String) throws -> URL {
        if let bundledURL = Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures") {
            return bundledURL
        }

        let fallbackURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }

        throw XCTSkip("Missing fixture \(name).json")
    }

    private static func describeDecodingError(_ error: Error) -> String {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            return "keyNotFound(\(key.stringValue)) at \(codingPathDescription(context.codingPath + [key])): \(context.debugDescription)"
        case let DecodingError.typeMismatch(type, context):
            return "typeMismatch(\(type)) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case let DecodingError.valueNotFound(type, context):
            return "valueNotFound(\(type)) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case let DecodingError.dataCorrupted(context):
            return "dataCorrupted at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        default:
            return String(describing: error)
        }
    }

    private static func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "<root>" : path
    }
}
