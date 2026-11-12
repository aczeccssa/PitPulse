import Foundation
import WidgetKit
import PitPulseData
import PitPulseShared

struct FavoriteRaceSource: Sendable {
    let meeting: Meeting
    let session: Session
    let results: [SessionResult]
    let savedAt: Date
}

/// App-only bridge. Extensions link Shared, never the networking/data module.
@MainActor
final class WidgetSnapshotPublisher {
    private let defaults: UserDefaults?
    private let reload: (String) -> Void
    private var lastLivePublish: Date?
    private var lastLiveIdentity: String?

    init(defaults: UserDefaults? = UserDefaults(suiteName: RaceWidgetCache.group),
         reload: @escaping (String) -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: $0) }) {
        self.defaults = defaults
        self.reload = reload
    }

    func publishCalendar(meetings: [Meeting], savedAt: Date, now: Date = .now) {
        let next = CalendarLogic.nextSession(in: meetings, now: now)
        let snapshot = next.map {
            RaceWidgetSnapshot(meeting: $0.meeting.name, session: $0.session.sessionType.displayName,
                start: $0.session.startTime, savedAt: savedAt, round: $0.meeting.round, location: $0.meeting.location,
                sessions: $0.meeting.sessions.filter { $0.status != .cancelled }.sorted { $0.startTime < $1.startTime }.map {
                    RaceWidgetSession(id: $0.id, title: $0.sessionType.displayName, start: $0.startTime)
                })
        }
        RaceWidgetCache.write(snapshot, to: defaults)
        RaceWidgetCache.writeUpcoming(upcomingSnapshot(meetings: meetings, savedAt: savedAt, now: now), to: defaults)
        reload(RaceWidgetCache.kind)
        reload(RaceWidgetCache.scheduleKind)
        reload(RaceWidgetCache.upcomingKind)
    }

    private func upcomingSnapshot(meetings: [Meeting], savedAt: Date, now: Date) -> UpcomingWidgetSnapshot? {
        let races = meetings
            .filter { $0.status != .cancelled && $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(3)
            .map { meeting -> UpcomingRaceEntry in
                let sessions = meeting.sessions
                    .filter { $0.status != .cancelled && $0.status != .finished && $0.startTime >= now }
                    .sorted { $0.startTime < $1.startTime }
                let next = sessions.first
                let race = meeting.sessions.first { $0.sessionType == .race && $0.status != .cancelled }
                return UpcomingRaceEntry(id: meeting.id, round: meeting.round, name: meeting.name,
                    location: meeting.location, countryCode: meeting.countryCode,
                    start: meeting.startDate, end: meeting.endDate, raceStart: race?.startTime,
                    nextSessionStart: next?.startTime, nextSessionTitle: next?.sessionType.displayName)
            }
        guard !races.isEmpty else { return nil }
        return UpcomingWidgetSnapshot(savedAt: savedAt, races: Array(races))
    }

    func publishStandings(_ standings: [DriverStanding], season: Int, savedAt: Date) {
        guard let leader = standings.min(by: { $0.position < $1.position }) else {
            RaceWidgetCache.writeStandings(nil, to: defaults)
            reload(RaceWidgetCache.standingsKind)
            return
        }
        let drivers = standings.sorted { $0.position < $1.position }.prefix(5).map {
            WidgetStandingDriver(driverID: $0.driverId, name: $0.driverName, team: $0.constructor,
                constructorID: $0.constructorIds.first, position: $0.position, points: $0.points,
                gapToLeader: max(0, leader.points - $0.points))
        }
        RaceWidgetCache.writeStandings(StandingsWidgetSnapshot(season: season, savedAt: savedAt, drivers: Array(drivers)), to: defaults)
        reload(RaceWidgetCache.standingsKind)
    }

    func publishFavoriteDriver(_ standings: [DriverStanding], favoriteID: String?, season: Int, savedAt: Date,
                               recentRaces: [FavoriteRaceSource] = []) {
        let ordered = standings.sorted { $0.position < $1.position }
        guard let favoriteID, let index = ordered.firstIndex(where: { $0.driverId == favoriteID }) else {
            RaceWidgetCache.writeFavoriteDriver(nil, to: defaults)
            reload(RaceWidgetCache.favoriteDriverKind)
            return
        }
        let standing = ordered[index]
        let leaderPoints = ordered.first?.points ?? standing.points
        let driver = WidgetStandingDriver(driverID: standing.driverId, name: standing.driverName,
            team: standing.constructor, constructorID: standing.constructorIds.first,
            position: standing.position, points: standing.points,
            gapToLeader: max(0, leaderPoints - standing.points))
        let recent = recentRaces.compactMap { source -> FavoriteRaceEntry? in
            guard let result = source.results.first(where: { $0.driverId == favoriteID }) else { return nil }
            return FavoriteRaceEntry(
                id: source.session.id, round: source.meeting.round, meeting: source.meeting.name,
                date: source.session.startTime, position: result.position, points: result.points,
                laps: result.laps, fastestLap: result.bestLap,
                gap: result.position == 1 ? (result.raceTime ?? result.time) : (result.gap ?? result.time),
                classification: result.classificationLabel)
        }
        let behind = index + 1 < ordered.count
            ? max(0, standing.points - ordered[index + 1].points) : nil
        let snapshot = FavoriteDriverWidgetSnapshot(season: season, savedAt: savedAt, favoriteID: favoriteID,
            driver: driver, wins: standing.wins, gapToBehind: behind, recentRaces: recent)
        RaceWidgetCache.writeFavoriteDriver(snapshot, to: defaults)
        reload(RaceWidgetCache.favoriteDriverKind)
    }

    func publishLastRace(meeting: Meeting, session: Session, results: [SessionResult],
                         analysis: SessionAnalysis? = nil, savedAt: Date) {
        guard session.sessionType == .race else { return }
        let ordered = results.sorted { ($0.position ?? Int.max) < ($1.position ?? Int.max) }
        guard !ordered.isEmpty else { return }
        let podium = ordered.prefix(3).enumerated().map { index, result in
            let position = result.position ?? index + 1
            let time = position == 1
                ? (result.raceTime ?? result.time ?? result.bestLap ?? "—")
                : (result.gap ?? result.time ?? "—")
            return LastRacePodiumEntry(driverID: result.driverId, name: result.driverName, team: result.team,
                constructorID: result.constructorId, position: position, time: time, points: result.points)
        }
        let fastest = ordered
            .compactMap { result in Self.lapSeconds(result.bestLap).map { (result.bestLap ?? "", $0) } }
            .min { $0.1 < $1.1 }?.0
        let laps = ordered.compactMap(\.laps).max()
        let snapshot = LastRaceWidgetSnapshot(
            meeting: meeting.name, session: session.sessionType.displayName, season: meeting.season,
            round: meeting.round, raceDate: session.startTime, savedAt: savedAt, podium: podium,
            fastestLap: fastest, laps: laps, safetyCars: analysis.flatMap { Self.safetyCarPeriods(in: $0) })
        RaceWidgetCache.writeLastRace(snapshot, to: defaults)
        reload(RaceWidgetCache.lastRaceKind)
    }

    private static func lapSeconds(_ text: String?) -> Double? {
        guard let text else { return nil }
        let cleaned = text.replacingOccurrences(of: "+", with: "").trimmingCharacters(in: .whitespaces)
        let parts = cleaned.split(separator: ":").map { Double($0.replacingOccurrences(of: ",", with: ".")) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let values = parts.compactMap { $0 }
        switch values.count {
        case 2: return values[0] * 60 + values[1]
        case 3: return values[0] * 3600 + values[1] * 60 + values[2]
        default: return values[0]
        }
    }

    private static func safetyCarPeriods(in analysis: SessionAnalysis) -> Int? {
        // Only count deployment messages: a period also emits "in this lap" and
        // "ending" notices, which must not inflate the number.
        let periods = analysis.raceControl.filter { event in
            let message = (event.message ?? "").uppercased()
            return message.contains("SAFETY CAR") && message.contains("DEPLOY")
                && !message.contains("VIRTUAL")
        }
        return periods.isEmpty ? nil : periods.count
    }

    func publishLive(_ snapshot: LiveSnapshot, now: Date = .now) {
        guard !snapshot.isWec else { return }
        let identity = "\(snapshot.sessionId ?? "")|\(snapshot.statusLabel)"
        if let lastLivePublish, identity == lastLiveIdentity, now.timeIntervalSince(lastLivePublish) < 30 { return }
        lastLivePublish = now
        lastLiveIdentity = identity
        if snapshot.sessionId == nil {
            // A disconnect must never leave a fresh-looking timing cache behind.
            if var previous = RaceWidgetCache.readTiming(from: defaults) {
                previous.stale = true
                if !previous.status.contains("回放") { previous.status = snapshot.statusLabel }
                RaceWidgetCache.writeTiming(previous, to: defaults)
            }
        } else {
            RaceWidgetCache.writeTiming(RaceTimingSnapshot(
                meeting: snapshot.meetingName ?? "Formula 1", session: snapshot.sessionName ?? "—",
                lap: snapshot.lapLabel, status: snapshot.statusLabel,
                updatedAt: snapshot.updatedAt.flatMap(RFC3339.parse) ?? .distantPast,
                stale: snapshot.sourceStatus != .connected,
                drivers: snapshot.drivers.sorted { ($0.position ?? Int.max) < ($1.position ?? Int.max) }.prefix(8).map { driver in
                    RaceTimingDriver(id: driver.number, position: driver.position, name: driver.name ?? driver.number,
                        gap: driver.gap ?? driver.interval ?? "—", tire: driver.tireShortLabel,
                        teamAsset: LiveIslandLogic.teamAssetID(for: driver, isWec: false).map { "team-logo-\($0)-2026" })
                }), to: defaults)
        }
        reload(RaceWidgetCache.timingKind)
    }

    func clearLive() {
        lastLivePublish = nil
        lastLiveIdentity = nil
        RaceWidgetCache.writeTiming(nil, to: defaults)
        reload(RaceWidgetCache.timingKind)
    }

    func clear() {
        RaceWidgetCache.write(nil, to: defaults)
        RaceWidgetCache.writeStandings(nil, to: defaults)
        RaceWidgetCache.writeFavoriteDriver(nil, to: defaults)
        RaceWidgetCache.writeLastRace(nil, to: defaults)
        RaceWidgetCache.writeUpcoming(nil, to: defaults)
        reload(RaceWidgetCache.kind)
        reload(RaceWidgetCache.scheduleKind)
        reload(RaceWidgetCache.standingsKind)
        reload(RaceWidgetCache.favoriteDriverKind)
        reload(RaceWidgetCache.lastRaceKind)
        reload(RaceWidgetCache.upcomingKind)
        clearLive()
    }
}
