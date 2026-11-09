import XCTest
@testable import PitPulseShared
@testable import PitPulseData

final class LiveActivityContentStateTests: XCTestCase {
    func testContentStateRoundTripsThroughJSON() throws {
        #if os(iOS)
        let state = PitPulseActivityAttributes.ContentState(
            sessionName: "Race",
            meetingName: "São Paulo Grand Prix",
            statusLabel: "进行中",
            lapLabel: "L32/71",
            leaderName: "Lando NORRIS",
            leaderGap: "LEADER",
            trackLabel: "绿旗 · 赛道畅通",
            driverCount: 22,
            isStale: false,
            updatedLabel: "刚刚"
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PitPulseActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, state)
        #endif
    }

    func testCalendarCountdownText() {
        XCTAssertEqual(CalendarLogic.countdownText(until: Date(), now: Date()), "不到 1 分钟")
    }

    func testLiveSnapshotDecodesActivityFields() throws {
        let json = """
        {"schemaVersion":1,"stateVersion":7,"sessionId":"2026:21:race","sessionName":"Race",
         "meetingName":"São Paulo Grand Prix","sourceStatus":"connected","sourceMode":"live",
         "statusReason":null,"sessionType":"Race","sessionStatus":"started","trackStatus":"AllClear",
         "lapCount":32,"totalLaps":71,"updatedAt":"2026-11-09T05:40:49Z","lastTransportAt":null,
         "drivers":[{"number":"1","name":"Lando NORRIS","position":1,"gap":"LEADER","lapCount":32}],
         "raceControl":[]}
        """
        let snapshot = try JSONDecoder().decode(LiveSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.lapLabel, "L32/71")
        XCTAssertEqual(snapshot.sessionStateLabel, "进行中")
        XCTAssertEqual(snapshot.drivers.first?.name, "Lando NORRIS")
    }
}
