import XCTest
@testable import SharedData
@testable import PitPulseDesktop

extension AppModelTests {
    func testReminderPlannerUsesStableServerScopedIDsAndUTCInstants() throws {
        let beforeDST = TestData.session(id: "2026:1:fp1", type: .fp1, start: "2026-03-08T06:30:00Z")
        let afterDST = TestData.session(id: "2026:1:race", type: .race, start: "2026-03-08T07:30:00Z")
        let meeting = TestData.meeting(sessions: [beforeDST, afterDST])
        let now = TestData.date("2026-03-08T06:00:00Z")
        let reminders = SessionReminderPlanner.reminders(meetings: [meeting], serverIdentity: "https://a.example", season: 2026, minutesBefore: 15, now: now)
        XCTAssertEqual(reminders.count, 2)
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(newYork.component(.hour, from: beforeDST.startTime), 1)
        XCTAssertEqual(newYork.component(.hour, from: afterDST.startTime), 3)
        XCTAssertEqual(reminders[0].fireDate, beforeDST.startTime.addingTimeInterval(-15 * 60))
        XCTAssertEqual(reminders[1].fireDate, afterDST.startTime.addingTimeInterval(-15 * 60))
        XCTAssertEqual(reminders[0].identifier, SessionReminderPlanner.reminders(
            meetings: [meeting], serverIdentity: "https://a.example", season: 2026, minutesBefore: 15, now: now
        )[0].identifier)
        XCTAssertNotEqual(reminders[0].identifier, SessionReminderPlanner.reminders(
            meetings: [meeting], serverIdentity: "https://b.example", season: 2026, minutesBefore: 15, now: now
        )[0].identifier)
        let nextSeasonSession = TestData.session(id: "2027:1:fp1", meetingId: "2027:1", type: .fp1,
                                                 start: "2027-03-05T01:30:00Z")
        let nextSeason = TestData.meeting(id: "2027:1", season: 2027, sessions: [nextSeasonSession])
        XCTAssertNotEqual(reminders[0].identifier, SessionReminderPlanner.reminders(
            meetings: [nextSeason], serverIdentity: "https://a.example", season: 2027,
            minutesBefore: 15, now: now
        )[0].identifier)
        XCTAssertTrue(SessionReminderPlanner.reminders(
            meetings: [meeting], serverIdentity: "https://a.example", season: 2026,
            minutesBefore: 15, now: afterDST.startTime
        ).isEmpty)
    }

    @MainActor
    func testReminderPermissionAndRefreshReconcileChangedAndCancelledSessions() async throws {
        let center = TestReminderCenter()
        center.authorizationStatus = .notDetermined
        let (model, root, suite) = makeModel(reminderCenter: center)
        defer { cleanup(root, suite) }
        XCTAssertFalse(model.remindersEnabled)
        await model.setRemindersEnabled(true)
        XCTAssertTrue(model.remindersEnabled)
        XCTAssertEqual(center.permissionRequests, 1)

        let start = Date.now.addingTimeInterval(86_400)
        let session = Session(id: "2026:1:fp1", meetingId: "2026:1", sessionType: .fp1,
                              startTime: start, endTime: nil, status: .scheduled,
                              jolpicaSessionId: nil, openf1SessionKey: nil)
        let meeting = Meeting(id: "2026:1", season: model.selectedSeason, round: 1,
                              name: "Test GP", country: "Australia", countryCode: "AU", location: "Melbourne",
                              startDate: start, endDate: start.addingTimeInterval(86_400), status: .scheduled,
                              sessions: [session], source: "fixture", fetchedAt: Date(), sourceUpdatedAt: nil, revision: 1)
        let state = MutableMeetingFixture(meeting)
        let counter = RequestCounter()
        center.shouldFailScheduling = true
        URLProtocolStub.handler = { request in
            if request.url!.path.hasSuffix("/calendar") {
                counter.increment()
                Thread.sleep(forTimeInterval: 0.1)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let current = state.value
            let data: Data
            if request.url!.path.hasSuffix("/next") {
                data = try encoder.encode(APIEnvelope(data: Optional<Meeting>.none, meta: TestData.meta()))
            } else {
                data = try encoder.encode(APIEnvelope(data: [current], meta: TestData.meta()))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, data)
        }
        let firstRefresh = Task { await model.refreshNow() }
        let concurrentRefresh = Task { await model.refreshNow() }
        await firstRefresh.value
        await concurrentRefresh.value
        XCTAssertEqual(counter.value, 1)
        XCTAssertNotNil(model.reminderMessage)
        XCTAssertTrue(center.scheduled.isEmpty)

        center.shouldFailScheduling = false
        await model.refreshNow()
        XCTAssertNil(model.reminderMessage)
        let original = try XCTUnwrap(center.scheduled.values.first)
        XCTAssertEqual(center.scheduled.count, 1)
        await model.refreshNow()
        XCTAssertEqual(center.scheduled.count, 1)

        let movedSession = Session(id: session.id, meetingId: session.meetingId, sessionType: session.sessionType,
                                   startTime: start.addingTimeInterval(3600), endTime: nil, status: .scheduled,
                                   jolpicaSessionId: nil, openf1SessionKey: nil)
        state.value = Meeting(id: meeting.id, season: meeting.season, round: meeting.round, name: meeting.name,
                              country: meeting.country, countryCode: meeting.countryCode, location: meeting.location,
                              startDate: meeting.startDate, endDate: meeting.endDate, status: .scheduled,
                              sessions: [movedSession], source: meeting.source, fetchedAt: Date(),
                              sourceUpdatedAt: nil, revision: 2)
        await model.refreshNow()
        XCTAssertEqual(center.scheduled.count, 1)
        XCTAssertEqual(center.scheduled[original.identifier]?.fireDate.timeIntervalSince1970 ?? 0,
                       movedSession.startTime.addingTimeInterval(-15 * 60).timeIntervalSince1970, accuracy: 1)

        XCTAssertTrue(model.updateServerAddress("https://b.example"))
        await model.refreshNow()
        let movedServer = try XCTUnwrap(center.scheduled.values.first)
        XCTAssertEqual(center.scheduled.count, 1)
        XCTAssertNotEqual(movedServer.identifier, original.identifier)

        state.value = Meeting(id: meeting.id, season: meeting.season, round: meeting.round, name: meeting.name,
                              country: meeting.country, countryCode: meeting.countryCode, location: meeting.location,
                              startDate: meeting.startDate, endDate: meeting.endDate, status: .cancelled,
                              sessions: [movedSession], source: meeting.source, fetchedAt: Date(),
                              sourceUpdatedAt: nil, revision: 3)
        await model.refreshNow()
        XCTAssertTrue(center.scheduled.isEmpty)
    }

    @MainActor
    func testDeniedReminderPermissionDoesNotEnableOrRepeatPrompt() async throws {
        let center = TestReminderCenter()
        center.authorizationStatus = .denied
        let (model, root, suite) = makeModel(reminderCenter: center)
        defer { cleanup(root, suite) }
        await model.setRemindersEnabled(true)
        await model.setRemindersEnabled(true)
        XCTAssertFalse(model.remindersEnabled)
        XCTAssertTrue(model.reminderPermissionDenied)
        XCTAssertEqual(center.permissionRequests, 0)
    }
}
