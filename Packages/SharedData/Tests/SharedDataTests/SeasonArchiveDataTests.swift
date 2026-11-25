import Foundation
import XCTest
@testable import SharedData

final class SeasonArchiveDataTests: XCTestCase {
    func testPublishedOpeningKeepsSeasonPendingAfterNewYear() throws {
        let january = try XCTUnwrap(RFC3339.parse("2028-01-01T00:00:00Z"))
        let opening = try XCTUnwrap(RFC3339.parse("2028-03-19T00:00:00Z"))
        XCTAssertTrue(CalendarLogic.seasonHasNotStarted(2028, meetings: [], firstRaceDate: "2028-03-19", now: january))
        XCTAssertFalse(CalendarLogic.seasonHasNotStarted(2028, meetings: [], firstRaceDate: "2028-03-19", now: opening))
        XCTAssertFalse(CalendarLogic.seasonHasNotStarted(2027, meetings: [], now: january))
    }

    func testCircuitLengthDecodesWhenArchiveProvidesIt() throws {
        let base = #""id":"track","name":"Track","latitude":1.5,"longitude":2.5"#
        let decoder = JSONDecoder()
        let enriched = try decoder.decode(CircuitLocation.self, from: Data("{\(base),\"lengthKm\":4.309}".utf8))
        let older = try decoder.decode(CircuitLocation.self, from: Data("{\(base)}".utf8))
        XCTAssertEqual(enriched.lengthKm, 4.309)
        XCTAssertNil(older.lengthKm)
    }

    func testStartingPositionPreservesPitLaneAndUnavailableSeparately() throws {
        let base = """
        "sessionId":"2026:20:race","position":1,"classification":"CLASSIFIED",
        "driverId":"test","driverName":"Test Driver","constructorId":"team","team":"Team",
        "source":"archive","fetchedAt":"2026-11-18T00:00:00Z","revision":1,"quality":"provisional"
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fromPit = try decoder.decode(SessionResult.self, from: Data("{\(base),\"gridPosition\":0}".utf8))
        let absent = try decoder.decode(SessionResult.self, from: Data("{\(base)}".utf8))
        XCTAssertEqual(fromPit.gridPosition, 0)
        XCTAssertNil(absent.gridPosition)
    }
}
