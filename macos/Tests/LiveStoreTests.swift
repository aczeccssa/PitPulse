import XCTest
@testable import SharedData
@testable import PitPulseDesktop

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
            ("1", .clear), ("AllClear", .clear), ("Chequered", .clear),
            ("Yellow flag", .yellow), ("2", .yellow), ("Slow zone", .yellow),
            ("FCY", .fullCourseYellow), ("Full course yellow", .fullCourseYellow),
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

    func testWecSnapshotDecodesSeriesClassAndRemainingTime() throws {
        let data = Data(#"{"schemaVersion":1,"stateVersion":3,"series":"wec","sessionId":"wec:18162","sessionName":"Race","meetingName":"FIA WEC - 6 Hours of Monza","sourceStatus":"connected","sourceMode":"live","sessionStatus":"started","trackStatus":"FCY","lapCount":14,"timeRemainingSeconds":20112,"elapsedSeconds":1488,"isTimeBased":true,"drivers":[{"number":"38","name":"Jack Aitken","team":"CADILLAC HERTZ TEAM JOTA","position":1,"gap":"LEADER","classId":"HYPERCAR","className":"Hypercar","classPosition":1,"manufacturer":"Cadillac V-Series.R","inPit":false,"retired":false,"tireCompound":"MEDIUM","tireAgeLaps":8,"energyPercent":82.4}]}"#.utf8)
        let snapshot = try JSONDecoder().decode(LiveSnapshot.self, from: data)
        XCTAssertEqual(snapshot.series, "wec")
        XCTAssertTrue(snapshot.isWec)
        XCTAssertEqual(snapshot.remainingLabel, "5:35:12")
        XCTAssertEqual(snapshot.trackCondition, .fullCourseYellow)
        XCTAssertEqual(snapshot.drivers.first?.classLabel, "HYPERCAR P1")
        XCTAssertEqual(snapshot.drivers.first?.className, "Hypercar")
        XCTAssertEqual(snapshot.drivers.first?.tireLabel, "M 8")
        XCTAssertEqual(snapshot.drivers.first?.energyLabel, "82%")
        XCTAssertEqual(snapshot.drivers.first?.tireShortLabel, "M")
    }

    func testTrackIconsDistinguishFlagsSafetyCarAndVirtualSafetyCar() {
        let cases: [(LiveTrackCondition, String)] = [
            (.clear, "flag.fill"), (.yellow, "flag.fill"), (.red, "flag.fill"),
            (.fullCourseYellow, "flag.fill"),
            (.safetyCar, "flag.fill"), (.safetyCarEnding, "flag.fill"),
            (.virtualSafetyCar, "flag.fill"), (.virtualSafetyCarEnding, "flag.fill"),
            (.unknown, "questionmark.circle")
        ]
        for (condition, symbol) in cases { XCTAssertEqual(condition.systemName, symbol) }
        XCTAssertEqual(LiveTrackCondition.fullCourseYellow.code, "FCY")
        XCTAssertEqual(LiveTrackCondition.safetyCar.code, "SC")
        XCTAssertEqual(LiveTrackCondition.safetyCarEnding.code, "SC")
        XCTAssertEqual(LiveTrackCondition.virtualSafetyCar.code, "VSC")
        XCTAssertNil(LiveTrackCondition.clear.code)
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

    func testParserPreservesIndependentDataRefreshEvent() {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for byte in "event: dataRefresh\ndata: {\"target\":\"standings\"}\n\n".utf8 {
            events += parser.append(byte)
        }
        XCTAssertEqual(events, [SSEEvent(name: "dataRefresh", data: #"{"target":"standings"}"#)])
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

    func testOldSnapshotsAndNewTelemetryKeepIndependentFreshness() throws {
        let old = try JSONDecoder().decode(LiveSnapshot.self, from: Data(#"{"schemaVersion":1,"stateVersion":1,"sourceStatus":"connected","sourceMode":"live","drivers":[{"number":"44"}]}"#.utf8))
        XCTAssertNil(old.weather)
        XCTAssertNil(old.teamRadio)
        XCTAssertNil(old.drivers[0].location)
        let driver = try JSONDecoder().decode(LiveDriver.self, from: Data(#"{"number":"44","telemetry":{"utc":"2026-10-10T10:00:00Z","speed":300,"rpm":12000,"gear":8,"throttle":100,"brake":0,"drs":12},"location":{"x":100,"y":200,"utc":"2026-10-10T10:00:05Z"}}"#.utf8))
        XCTAssertEqual(driver.telemetry?.speed, 300)
        let now = RFC3339.parse("2026-10-10T10:00:12Z")!
        XCTAssertFalse(LiveFreshness.isFresh(driver.telemetry?.receivedAt ?? driver.telemetry?.utc, now: now))
        XCTAssertTrue(LiveFreshness.isFresh(driver.location?.receivedAt ?? driver.location?.utc, now: now))
        XCTAssertFalse(LiveFreshness.isFresh(nil, now: now))
        XCTAssertFalse(LiveFreshness.isFresh("2026-10-10T10:00:30Z", now: now))
    }

    func testReceivedAtControlsFreshnessWithoutReplacingUpstreamUTC() throws {
        let driver = try JSONDecoder().decode(LiveDriver.self, from: Data(#"{"number":"44","location":{"x":100,"y":200,"utc":"2026-10-10T10:00:00Z","receivedAt":"2026-10-10T10:00:11Z"},"telemetry":{"utc":"2026-10-10T10:00:01Z","receivedAt":"2026-10-10T10:00:11Z","speed":300}}"#.utf8))
        let now = RFC3339.parse("2026-10-10T10:00:18Z")!
        XCTAssertTrue(LiveFreshness.isFresh(driver.location?.receivedAt ?? driver.location?.utc, now: now))
        XCTAssertTrue(LiveFreshness.isFresh(driver.telemetry?.receivedAt ?? driver.telemetry?.utc, now: now))
        XCTAssertEqual(driver.location?.utc, "2026-10-10T10:00:00Z")
        XCTAssertEqual(driver.location?.receivedAt, "2026-10-10T10:00:11Z")
        XCTAssertEqual(LiveFreshness.age(driver.location?.utc, now: now), 18)
        XCTAssertFalse(LiveFreshness.isFresh(driver.location?.receivedAt, now: now.addingTimeInterval(11)))
    }

    @MainActor
    func testMapReleaseClearsResourcesAndCallbacks() {
        let map = MapStore()
        _ = map.view()
        map.publicToken = "pk.test"
        map.onDriver = { _ in }
        map.release()
        XCTAssertNil(map.webView)
        XCTAssertNil(map.publicToken)
        XCTAssertNil(map.onDriver)
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
