import XCTest
@testable import F1Companion

final class LiveStoreTests: XCTestCase {
    func testSnapshotDecodesOptionalRaceControlFieldsAndIgnoresUnknownValues() throws {
        let data = Data(#"{"schemaVersion":1,"stateVersion":2,"sessionId":"race","sessionName":"Race","sourceStatus":"connected","sourceMode":"replay","sessionStatus":"Started","updatedAt":"2026-10-10T01:00:00Z","lastTransportAt":"2026-10-10T01:00:00Z","drivers":[],"raceControl":[{"Message":"Safety car","Category":"SafetyCar","Flag":"YELLOW","NewField":true},{"Category":7},null]}"#.utf8)
        let snapshot = try JSONDecoder().decode(LiveSnapshot.self, from: data)

        XCTAssertEqual(snapshot.raceControl?.count, 3)
        XCTAssertEqual(snapshot.raceControl?.first?.message, "Safety car")
        XCTAssertNil(snapshot.raceControl?[1].message)
        XCTAssertNil(snapshot.raceControl?[2].category)
    }

    func testSectorsDecodeAndMissingFieldsStayUnavailable() throws {
        let driver = try JSONDecoder().decode(LiveDriver.self, from: Data(#"{"number":"1","sectors":[{"value":"25.001","overallFastest":true,"segments":[2048,null,2051]},{},{}],"inPit":true,"unknown":17}"#.utf8))
        XCTAssertEqual(driver.sectors?.count, 3)
        XCTAssertEqual(driver.sectors?[0].segments, [2048, nil, 2051])
        XCTAssertNil(driver.sectors?[1].value)
        XCTAssertTrue(driver.inPit == true)
        XCTAssertNil(try JSONDecoder().decode(LiveDriver.self, from: Data(#"{"number":"1"}"#.utf8)).sectors)
    }

    func testTrackConditionsRecognizeCodesAndMessagesWithoutUsingStaleFlags() throws {
        let cases: [(String, LiveTrackCondition)] = [
            ("1", .clear), ("AllClear", .clear), ("Yellow flag", .yellow), ("2", .yellow),
            ("4", .safetyCar), ("SCDeployed", .safetyCar), ("SCInThisLap", .safetyCarEnding),
            ("5", .red), ("Red flag", .red), ("6", .virtualSafetyCar), ("VSCDeployed", .virtualSafetyCar),
            ("7", .virtualSafetyCarEnding), ("Virtual safety car ending", .virtualSafetyCarEnding)
        ]
        for (value, condition) in cases { XCTAssertEqual(LiveTrackCondition(value), condition, value) }
        XCTAssertEqual(LiveTrackCondition(nil), .unknown)
        XCTAssertEqual(LiveTrackCondition("future_status"), .unknown)
        let red = try JSONDecoder().decode(LiveSnapshot.self, from: Data(#"{"schemaVersion":1,"stateVersion":1,"sourceStatus":"connected","sourceMode":"live","sessionStatus":"Started","trackStatus":"5","drivers":[]}"#.utf8))
        XCTAssertEqual(red.sessionStateLabel, "红旗暂停")
        for status in ["stale", "disconnected"] {
            let data = Data("{\"schemaVersion\":1,\"stateVersion\":1,\"sourceStatus\":\"\(status)\",\"sourceMode\":\"live\",\"trackStatus\":\"SCDeployed\",\"drivers\":[]}".utf8)
            XCTAssertEqual(try JSONDecoder().decode(LiveSnapshot.self, from: data).trackCondition, .unknown)
        }
    }

    func testTrackIconsDistinguishFlagsSafetyCarAndVirtualSafetyCar() {
        let cases: [(LiveTrackCondition, String)] = [
            (.clear, "flag.fill"), (.yellow, "flag.fill"), (.red, "flag.fill"),
            (.safetyCar, "car.side.fill"), (.safetyCarEnding, "car.side.fill"),
            (.virtualSafetyCar, "car.side"), (.virtualSafetyCarEnding, "car.side"),
            (.unknown, "questionmark.circle")
        ]
        for (condition, symbol) in cases { XCTAssertEqual(condition.systemName, symbol) }
    }

    func testParserHandlesSplitUTF8CRLFCommentsAndMultipleDataLines() {
        var parser = SSEParser()
        let input = ": keep-alive\r\nevent: snapshot\r\ndata: {\"name\":\"赛\"\r\ndata: \"line\":2}\r\n\r\n"
        var events: [SSEEvent] = []
        for byte in input.utf8 {
            events += parser.append(byte)
        }

        XCTAssertEqual(events, [SSEEvent(name: "snapshot", data: "{\"name\":\"赛\"\n\"line\":2}")])
    }

    func testParserDropsMalformedUTF8LineAndRecovers() {
        var parser = SSEParser()
        let bytes: [UInt8] = [0xFF, 0x0A] + Array("data: ok\n\n".utf8)
        var events: [SSEEvent] = []
        for byte in bytes {
            events += parser.append(byte)
        }
        XCTAssertEqual(events, [SSEEvent(name: "message", data: "ok")])
    }

    @MainActor
    func testSnapshotVersionsResetAcrossConnectionsAndOldTasksCannotWrite() {
        let store = LiveStore()
        let firstGeneration = store.beginConnection()
        let firstConnection = store.beginStream(generation: firstGeneration)!
        XCTAssertTrue(store.accept(snapshot(version: 12), generation: firstGeneration, connection: firstConnection))
        XCTAssertFalse(store.accept(snapshot(version: 11), generation: firstGeneration, connection: firstConnection))

        let nextConnection = store.beginStream(generation: firstGeneration)!
        XCTAssertTrue(store.accept(snapshot(version: 1), generation: firstGeneration, connection: nextConnection))
        XCTAssertEqual(store.snapshot.stateVersion, 1)

        let nextGeneration = store.beginConnection()
        XCTAssertFalse(store.accept(snapshot(version: 50), generation: firstGeneration))
        XCTAssertTrue(store.accept(snapshot(version: 1), generation: nextGeneration))
    }

    private func snapshot(version: Int) -> LiveSnapshot {
        LiveSnapshot(
            schemaVersion: 1,
            stateVersion: version,
            sessionId: nil,
            sessionName: nil,
            sourceStatus: .connected,
            sourceMode: .live,
            statusReason: nil,
            sessionType: nil,
            sessionStatus: nil,
            trackStatus: nil,
            lapCount: nil,
            updatedAt: nil,
            lastTransportAt: nil,
            drivers: [],
            raceControl: nil
        )
    }
}
