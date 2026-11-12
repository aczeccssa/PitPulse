import XCTest
@testable import PitPulseData
@testable import PitPulseDesktop

final class CalendarLogicTests: XCTestCase {
    func testNextSessionChoosesEarliestFutureScheduledSession() {
        let future = TestData.meeting(
            sessions: [
                TestData.session(id: "2026:1:fp1", start: "2026-03-06T01:30:00Z", status: .finished),
                TestData.session(id: "2026:1:race", type: .race, start: "2026-03-08T04:00:00Z")
            ]
        )
        let result = CalendarLogic.nextSession(
            in: [future],
            now: TestData.date("2026-03-06T12:00:00Z")
        )
        XCTAssertEqual(result?.session.id, "2026:1:race")
    }

    func testCancelledMeetingAndPostponedSessionAreExcluded() {
        let cancelled = TestData.meeting(id: "2026:1", status: .cancelled)
        let postponed = TestData.meeting(
            id: "2026:2",
            round: 2,
            sessions: [TestData.session(id: "2026:2:fp1", meetingId: "2026:2", status: .postponed)]
        )
        let result = CalendarLogic.nextSession(
            in: [cancelled, postponed],
            now: TestData.date("2026-03-01T00:00:00Z")
        )
        XCTAssertNil(result)
    }

    func testAsiaShanghaiCrossesDayBoundary() {
        let components = CalendarLogic.localDateComponents(
            TestData.date("2026-03-08T16:00:00Z"),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 9)
        XCTAssertEqual(components.hour, 0)
    }

    func testNewYorkDSTHourBoundaries() {
        let before = CalendarLogic.localDateComponents(
            TestData.date("2026-03-08T06:30:00Z"),
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        let after = CalendarLogic.localDateComponents(
            TestData.date("2026-03-08T07:30:00Z"),
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        XCTAssertEqual(before.hour, 1)
        XCTAssertEqual(after.hour, 3)
    }

    func testCountdownNeverBecomesNegative() {
        let date = TestData.date("2026-03-08T04:00:00Z")
        XCTAssertEqual(
            CalendarLogic.countdownText(until: date, now: date.addingTimeInterval(60)),
            "不到 1 分钟"
        )
        XCTAssertEqual(
            CalendarLogic.countdownText(until: date, now: date.addingTimeInterval(-3_900)),
            "1 小时 5 分钟"
        )
    }

    func testSprintWeekendDoesNotAssumeFixedSessionCount() {
        let sessions = [
            TestData.session(id: "2026:2:fp1", meetingId: "2026:2", type: .fp1),
            TestData.session(id: "2026:2:sq", meetingId: "2026:2", type: .sprintQualifying),
            TestData.session(id: "2026:2:sprint", meetingId: "2026:2", type: .sprint),
            TestData.session(id: "2026:2:race", meetingId: "2026:2", type: .race)
        ]
        let meeting = TestData.meeting(id: "2026:2", round: 2, name: "Chinese Grand Prix", sessions: sessions)
        XCTAssertEqual(meeting.sessions.count, 4)
    }
}

extension CalendarLogicTests {
    func testSeasonEndHasNoNextSessionAndExactBoundaryRemainsScheduled() {
        let meeting = TestData.meeting()
        let start = meeting.sessions[0].startTime
        XCTAssertNotNil(CalendarLogic.nextSession(in: [meeting], now: start))
        XCTAssertNil(CalendarLogic.nextSession(in: [meeting], now: start.addingTimeInterval(1)))
        XCTAssertNil(CalendarLogic.nextSession(in: [], now: start))
    }
}

extension CalendarLogicTests {
    func testFeaturedMeetingKeepsCurrentWeekendAfterLastSessionStarts() {
        let meeting = TestData.meeting()
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(CalendarLogic.featuredMeeting(in: [meeting], now: TestData.date("2026-03-08T05:00:00Z"), calendar: calendar)?.id, meeting.id)
        XCTAssertNil(CalendarLogic.nextSession(in: [meeting], now: TestData.date("2026-03-08T05:00:00Z")))
    }

    func testFeaturedMeetingFallsBackToRecentAndExcludesCancelled() {
        let recent = TestData.meeting()
        let cancelled = TestData.meeting(id: "cancelled", status: .cancelled)
        XCTAssertEqual(CalendarLogic.featuredMeeting(in: [cancelled, recent], now: TestData.date("2026-12-31T00:00:00Z"))?.id, recent.id)
        XCTAssertNil(CalendarLogic.featuredMeeting(in: [cancelled], now: Date()))
        XCTAssertNil(CalendarLogic.featuredMeeting(in: [], now: Date()))
    }

    func testFeaturedMeetingAdvancesAfterRaceDayEvenWhenPreviousRaceIsCloser() {
        func meeting(_ id: String, start: String, end: String) -> Meeting {
            Meeting(
                id: id, season: 2026, round: nil, name: id, country: "", countryCode: nil,
                location: "", startDate: TestData.date(start), endDate: TestData.date(end),
                status: .scheduled, sessions: [], source: nil, fetchedAt: nil,
                sourceUpdatedAt: nil, revision: nil
            )
        }
        let brazil = meeting("brazil", start: "2026-11-06T14:30:00Z", end: "2026-11-08T19:00:00Z")
        let upcoming = meeting("next", start: "2026-11-19T14:30:00Z", end: "2026-11-22T19:00:00Z")
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let meetings = [upcoming, brazil]
        for (time, expected) in [
            ("2026-11-08T20:00:00Z", brazil.id),
            ("2026-11-09T15:59:59Z", brazil.id),
            ("2026-11-09T16:00:00Z", upcoming.id),
            ("2026-11-12T04:00:00Z", upcoming.id),
            ("2026-12-01T04:00:00Z", upcoming.id)
        ] {
            XCTAssertEqual(
                CalendarLogic.featuredMeeting(in: meetings, now: TestData.date(time), calendar: calendar)?.id,
                expected, time
            )
        }
    }
}
