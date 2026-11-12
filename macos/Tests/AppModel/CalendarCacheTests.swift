import XCTest
@testable import SharedData
@testable import PitPulseDesktop

final class CalendarCacheTests: XCTestCase {
    func testRoundTripAndCacheRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCalendarCache(rootURL: root)
        let server = URL(string: "https://pitpulse.example")!
        let first = TestData.envelope()
        try await cache.save(server: server, season: 2026, envelope: first, savedAt: TestData.date("2026-03-01T00:00:00Z"))

        let loaded = try await cache.load(server: server, season: 2026)
        XCTAssertEqual(loaded?.envelope.data, first.data)
        XCTAssertEqual(loaded?.savedAt, TestData.date("2026-03-01T00:00:00Z"))
    }

    func testServerAndSeasonIsolation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCalendarCache(rootURL: root)
        let serverA = URL(string: "https://a.example")!
        let serverB = URL(string: "https://b.example")!
        try await cache.save(server: serverA, season: 2026, envelope: TestData.envelope())

        let serverBResult = try await cache.load(server: serverB, season: 2026)
        let seasonResult = try await cache.load(server: serverA, season: 2027)
        XCTAssertNil(serverBResult)
        XCTAssertNil(seasonResult)
    }

    func testEndpointCacheIsIsolatedByServerSeasonAndSessionKey() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCalendarCache(rootURL: root)
        let server = URL(string: "https://a.example")!
        let row = DriverStanding(
            season: 2026, position: 1, driverId: "norris", driverName: "Lando Norris",
            constructor: "McLaren", constructorIds: ["mclaren"], points: 25, wins: 1,
            source: "fixture", fetchedAt: TestData.date("2026-03-08T00:00:00Z"), revision: 2
        )
        let envelope = APIEnvelope(data: [row], meta: TestData.meta(revision: 2))
        try await cache.save(server: server, season: 2026, key: "results-2026:1:race", envelope: envelope)

        let loaded = try await cache.load(server: server, season: 2026, key: "results-2026:1:race", as: [DriverStanding].self)
        let otherSession = try await cache.load(server: server, season: 2026, key: "results-2026:2:race", as: [DriverStanding].self)
        let otherServer = try await cache.load(server: URL(string: "https://b.example")!, season: 2026, key: "results-2026:1:race", as: [DriverStanding].self)
        XCTAssertEqual(loaded?.data, [row])
        XCTAssertNil(otherSession)
        XCTAssertNil(otherServer)
    }

    func testCorruptCacheIsRemovedAndRecoveredAsMiss() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCalendarCache(rootURL: root)
        let server = URL(string: "https://pitpulse.example")!
        try await cache.save(server: server, season: 2026, envelope: TestData.envelope())
        let fileURL = await cache.fileURL(server: server, season: 2026)
        try Data("not-json".utf8).write(to: fileURL)

        let recovered = try await cache.load(server: server, season: 2026)
        XCTAssertNil(recovered)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testAtomicWriteFailureDoesNotReplaceExistingCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("blocking-file".utf8).write(to: root)
        let cache = DiskCalendarCache(rootURL: root)
        let server = URL(string: "https://pitpulse.example")!
        do {
            try await cache.save(server: server, season: 2026, envelope: TestData.envelope())
            XCTFail("Expected cache write failure")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("v1").path))
        }
    }


}

struct ModelCredentials: CredentialStore {
    var fail = false
    func token(for server: URL) throws -> String? {
        if fail { throw CredentialError.invalidService }
        return nil
    }
    func save(token: String, for server: URL) throws {
        if fail { throw CredentialError.invalidService }
    }
    func deleteToken(for server: URL) throws {
        if fail { throw CredentialError.invalidService }
    }
}


extension CalendarCacheTests {
    func testOldCacheVersionAndSchemaAreInvalidated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCalendarCache(rootURL: root)
        let server = URL(string: "https://a.example")!
        for field in ["cacheVersion", "schemaVersion"] {
            try await cache.save(server: server, season: 2026, envelope: TestData.envelope())
            let url = await cache.fileURL(server: server, season: 2026)
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            if field == "cacheVersion" {
                json[field] = 0
            } else {
                var envelope = json["envelope"] as! [String: Any]
                var meta = envelope["meta"] as! [String: Any]
                meta[field] = 2
                envelope["meta"] = meta
                json["envelope"] = envelope
            }
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            let loaded = try await cache.load(server: server, season: 2026)
            XCTAssertNil(loaded)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }
}
