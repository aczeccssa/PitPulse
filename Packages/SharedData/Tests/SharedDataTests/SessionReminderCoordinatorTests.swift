import Foundation
import Testing
@testable import SharedData

@MainActor
struct SessionReminderCoordinatorTests {
    @Test
    func reschedulesByIdentifierAndOnlyRemovesObsoleteSessionReminders() async throws {
        let center = RecordingReminderCenter()
        let coordinator = SessionReminderCoordinator(center: center)
        let start = Date.now.addingTimeInterval(3 * 3600)

        func plan(start: Date, status: SessionStatus = .scheduled) -> [SessionReminder] {
            let session = Session(id: "race", meetingId: "weekend", sessionType: .race,
                                  startTime: start, endTime: nil, status: status,
                                  jolpicaSessionId: nil, openf1SessionKey: nil)
            let meeting = Meeting(id: "weekend", season: 2026, round: 1, name: "Test GP",
                                  country: "Test", countryCode: nil, location: "Test",
                                  startDate: start, endDate: start, status: .scheduled,
                                  sessions: [session], source: nil, fetchedAt: nil,
                                  sourceUpdatedAt: nil, revision: nil)
            return SessionReminderPlanner.reminders(
                meetings: [meeting], serverIdentity: "test", season: 2026,
                minutesBefore: SessionReminderPlanner.defaultMinutes, now: .now
            )
        }

        let first = try #require(plan(start: start).first)
        #expect(first.fireDate == start.addingTimeInterval(-3600))
        try await coordinator.sync([first])
        try await coordinator.sync([first])
        #expect(center.scheduled.count == 1)

        let newStart = start.addingTimeInterval(1800)
        let moved = try #require(plan(start: newStart).first)
        try await coordinator.sync([moved])
        #expect(moved.identifier == first.identifier)
        #expect(center.scheduled[first.identifier]?.fireDate == newStart.addingTimeInterval(-3600))

        try await coordinator.sync(plan(start: newStart, status: .cancelled))
        #expect(center.scheduled.isEmpty)
        #expect(await center.pendingIdentifiers() == ["unrelated"])
    }
}

@MainActor
private final class RecordingReminderCenter: SessionReminderCenter {
    var scheduled: [String: SessionReminder] = [:]

    func authorization() async -> ReminderAuthorization { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func pendingIdentifiers() async -> [String] { ["unrelated"] + Array(scheduled.keys) }
    func schedule(_ reminder: SessionReminder) async throws { scheduled[reminder.identifier] = reminder }
    func removePending(identifiers: [String]) async {
        for identifier in identifiers { scheduled.removeValue(forKey: identifier) }
    }
}
