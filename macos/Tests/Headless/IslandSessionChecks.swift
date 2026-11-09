import Foundation
@testable import PitPulseData
@testable import PitPulseShared

// Standalone compilation excludes AppModel and its AppKit lifecycle.
// FavoriteDriver now lives in PitPulseShared.

@main
struct IslandSessionChecks {
    static func main() {
        let now = RFC3339.parse("2026-10-10T13:00:00Z")!
        func meeting(end: Date?) -> Meeting {
            let session = Session(id: "2026:17:qualifying", meetingId: "2026:17", sessionType: .qualifying,
                startTime: now, endTime: end, status: .scheduled, jolpicaSessionId: nil, openf1SessionKey: 11384)
            return Meeting(id: "2026:17", season: 2026, round: 17, name: "Singapore Grand Prix",
                country: "Singapore", countryCode: "SG", location: "Marina Bay", startDate: now,
                endDate: now.addingTimeInterval(86400), status: .scheduled, sessions: [session],
                source: nil, fetchedAt: nil, sourceUpdatedAt: nil, revision: nil)
        }
        func snapshot(status: LiveSourceStatus, type: String, sessionStatus: String, mode: LiveSourceMode = .live) -> LiveSnapshot {
            LiveSnapshot(schemaVersion: 1, stateVersion: 7, sessionId: "11383", sessionName: type,
                sourceStatus: status, sourceMode: mode, statusReason: nil, sessionType: type,
                sessionStatus: sessionStatus, trackStatus: "Green", lapCount: 20, updatedAt: nil,
                lastTransportAt: nil, drivers: [], raceControl: nil)
        }
        let meetings = [meeting(end: now.addingTimeInterval(5400))]
        for status in [LiveSourceStatus.disconnected, .stale, .connected] {
            let old = snapshot(status: status, type: "Sprint", sessionStatus: "Ends")
            let displayed = LiveIslandLogic.displayedSnapshot(current: old, lastKnown: old, meetings: meetings, now: now)
            assert(displayed.sessionId == "2026:17:qualifying" && displayed.sessionType == "排位赛")
            assert(displayed.sourceStatus == .disconnected && displayed.statusReason == "scheduled_session_waiting_for_live")
            assert(displayed.lapCount == nil && displayed.trackStatus == nil && displayed.drivers.isEmpty)
        }
        let old = snapshot(status: .disconnected, type: "Sprint", sessionStatus: "Ends")
        assert(LiveIslandLogic.displayedSnapshot(current: old, lastKnown: nil, meetings: meetings, now: now.addingTimeInterval(-1)).sessionType == "Sprint")
        assert(LiveIslandLogic.displayedSnapshot(current: old, lastKnown: nil, meetings: [meeting(end: nil)], now: now).sessionType == "Sprint")
        assert(LiveIslandLogic.displayedSnapshot(current: old, lastKnown: nil, meetings: meetings + meetings, now: now).sessionType == "Sprint")
        let live = snapshot(status: .connected, type: "Qualifying", sessionStatus: "Started")
        assert(LiveIslandLogic.displayedSnapshot(current: live, lastKnown: old, meetings: meetings, now: now) == live)
        let replay = snapshot(status: .connected, type: "Sprint", sessionStatus: "Ends", mode: .replay)
        assert(LiveIslandLogic.displayedSnapshot(current: replay, lastKnown: nil, meetings: meetings, now: now) == replay)
        print("Island session checks passed: scheduled boundary, ended/stale/disconnected, missing end, ambiguity, live priority, replay")
    }
}
