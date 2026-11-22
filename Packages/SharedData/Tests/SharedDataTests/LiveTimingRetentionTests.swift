import XCTest
@testable import SharedData

final class LiveTimingRetentionTests: XCTestCase {
    func testTransientDisconnectKeepsTimingAndFreezesClock() {
        let last = snapshot(status: "started")
        for reason in ["connecting", "reconnecting", "server_unavailable"] {
            let connection = LiveSnapshot.disconnected(reason: reason)
            let held = connection.retainingTiming(from: last)
            XCTAssertEqual(held.sourceStatus, .stale)
            XCTAssertEqual(held.statusReason, reason)
            XCTAssertEqual(held.sessionId, last.sessionId)
            XCTAssertEqual(held.drivers, last.drivers)
            XCTAssertEqual(held.lapCount, last.lapCount)
            XCTAssertEqual(held.updatedAt, last.updatedAt)
            XCTAssertEqual(held.clockRunning, false)
        }
    }

    func testDoesNotRestoreFinishedOrUnauthorizedTiming() {
        let awaiting = LiveSnapshot.disconnected(reason: "connecting")
        XCTAssertEqual(awaiting.retainingTiming(from: snapshot(status: "finished")), awaiting)
        XCTAssertEqual(awaiting.retainingTiming(from: nil), awaiting)
        let unauthorized = LiveSnapshot.disconnected(reason: "unauthorized")
        XCTAssertEqual(unauthorized.retainingTiming(from: snapshot(status: "started")), unauthorized)
    }

    private func snapshot(status: String) -> LiveSnapshot {
        let driver = LiveDriver(number: "12", name: "Antonelli", team: nil, position: 1, gap: nil,
                                interval: nil, lapCount: 4, lastLap: nil, bestLap: nil)
        return LiveSnapshot(schemaVersion: 1, stateVersion: 3, sessionId: "race", sessionName: "Race",
                            sourceStatus: .connected, sourceMode: .live, statusReason: nil,
                            sessionType: "race", sessionStatus: status, trackStatus: nil, lapCount: 4,
                            updatedAt: "2026-01-01T00:00:00Z", lastTransportAt: nil,
                            drivers: [driver], raceControl: nil, clockRunning: true)
    }
}
