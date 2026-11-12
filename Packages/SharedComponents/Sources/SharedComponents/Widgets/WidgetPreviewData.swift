#if DEBUG && (os(iOS) || os(macOS))
import Foundation
import SharedData

// Canvas-only sample data. Never reads or writes the App Group cache.
enum WidgetPreviewData {
    static let now = Date()
    static let sessions = zip(["FP1", "FP2", "FP3", "排位赛", "正赛"], [3600.0, 14400, 86400, 100800, 172800]).map {
        RaceWidgetSession(id: $0.0, title: $0.0, start: now.addingTimeInterval($0.1))
    }
    static let weekend = RaceWidgetSnapshot(
        meeting: "Las Vegas Grand Prix", session: "FP1", start: sessions[0].start,
        savedAt: now, round: 21, location: "Las Vegas", sessions: sessions
    )
    static let drivers: [WidgetStandingDriver] = [
        .init(driverID: "antonelli", name: "Andrea Kimi Antonelli", team: "Mercedes", constructorID: "mercedes", position: 1, points: 390, gapToLeader: 0, driverNumber: "12"),
        .init(driverID: "verstappen", name: "Max Verstappen", team: "Red Bull Racing", constructorID: "red_bull", position: 2, points: 279, gapToLeader: 111, driverNumber: "1"),
        .init(driverID: "russell", name: "George Russell", team: "Mercedes", constructorID: "mercedes", position: 3, points: 262, gapToLeader: 128, driverNumber: "63"),
        .init(driverID: "leclerc", name: "Charles Leclerc", team: "Ferrari", constructorID: "ferrari", position: 4, points: 249, gapToLeader: 141, driverNumber: "16"),
        .init(driverID: "norris", name: "Lando Norris", team: "McLaren", constructorID: "mclaren", position: 5, points: 228, gapToLeader: 162, driverNumber: "4")
    ]
    static let standings = StandingsWidgetSnapshot(season: 2026, savedAt: now, drivers: drivers)
    static let recentRaces: [FavoriteRaceEntry] = [
        .init(id: "brazil", round: 20, meeting: "São Paulo Grand Prix", date: now.addingTimeInterval(-4 * 86400),
              position: 1, points: 25, laps: 71, fastestLap: "1:11.900", gap: "1:32:45.678", classification: "已完赛"),
        .init(id: "mexico", round: 19, meeting: "Mexico City Grand Prix", date: now.addingTimeInterval(-11 * 86400),
              position: 2, points: 18, laps: 71, fastestLap: "1:18.642", gap: "+2.145", classification: "已完赛"),
        .init(id: "austin", round: 18, meeting: "United States Grand Prix", date: now.addingTimeInterval(-18 * 86400),
              position: 3, points: 15, laps: 56, fastestLap: "1:36.521", gap: "+8.902", classification: "已完赛")
    ]
    static let favorite = FavoriteDriverWidgetSnapshot(
        season: 2026, savedAt: now, favoriteID: drivers[3].driverID, driver: drivers[3],
        wins: 3, gapToBehind: 21, recentRaces: recentRaces
    )
    static let lastRace = LastRaceWidgetSnapshot(
        meeting: "São Paulo Grand Prix", session: "正赛", season: 2026, round: 20,
        raceDate: recentRaces[0].date, savedAt: now,
        podium: [
            .init(driverID: "leclerc", name: "Charles Leclerc", team: "Ferrari", position: 1, time: "1:32:45.678", points: 25, driverNumber: "16"),
            .init(driverID: "verstappen", name: "Max Verstappen", team: "Red Bull Racing", position: 2, time: "+2.145", points: 18, driverNumber: "1"),
            .init(driverID: "russell", name: "George Russell", team: "Mercedes", position: 3, time: "+8.902", points: 15, driverNumber: "63")
        ], fastestLap: "1:11.900", laps: 71, safetyCars: 2
    )
    static let upcoming = UpcomingWidgetSnapshot(savedAt: now, races: [
        .init(id: "vegas", round: 21, name: "Las Vegas Grand Prix", location: "Las Vegas", countryCode: "US",
              start: sessions[0].start, end: sessions[4].start, raceStart: sessions[4].start,
              nextSessionStart: sessions[0].start, nextSessionTitle: "FP1", sessions: sessions),
        .init(id: "qatar", round: 22, name: "Qatar Grand Prix", location: "Lusail", countryCode: "QA",
              start: now.addingTimeInterval(7 * 86400), end: now.addingTimeInterval(9 * 86400)),
        .init(id: "abu-dhabi", round: 23, name: "Abu Dhabi Grand Prix", location: "Yas Marina", countryCode: "AE",
              start: now.addingTimeInterval(14 * 86400), end: now.addingTimeInterval(16 * 86400))
    ])
    static let timing = RaceTimingSnapshot(
        meeting: "São Paulo Grand Prix", session: "正赛", lap: "L42 / 71", status: "绿旗", updatedAt: now, stale: false,
        drivers: [
            .init(id: "leclerc", position: 1, name: "Charles Leclerc", gap: "LEADER", tire: "M"),
            .init(id: "verstappen", position: 2, name: "Max Verstappen", gap: "+2.145", tire: "H"),
            .init(id: "russell", position: 3, name: "George Russell", gap: "+8.902", tire: "M"),
            .init(id: "antonelli", position: 4, name: "Andrea Kimi Antonelli", gap: "+11.320", tire: "M"),
            .init(id: "norris", position: 5, name: "Lando Norris", gap: "+14.721", tire: "H"),
            .init(id: "piastri", position: 6, name: "Oscar Piastri", gap: "+18.200", tire: "M"),
            .init(id: "hamilton", position: 7, name: "Lewis Hamilton", gap: "+21.453", tire: "H"),
            .init(id: "alonso", position: 8, name: "Fernando Alonso", gap: "+28.156", tire: "M")
        ]
    )
}
#endif
