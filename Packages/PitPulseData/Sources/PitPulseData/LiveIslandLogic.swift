import Foundation
import PitPulseShared

public enum LiveIslandLogic {
    public static func displayedSnapshot(current: LiveSnapshot, lastKnown: LiveSnapshot?, meetings: [Meeting], now: Date) -> LiveSnapshot {
        let retained = current.sourceStatus == .disconnected ? lastKnown ?? current : current
        if current.sourceMode == .live,
           let planned = currentScheduledSession(in: meetings, now: now),
           current.sourceStatus != .connected || isFinished(current.sessionStatus) {
            return LiveSnapshot(schemaVersion: current.schemaVersion, stateVersion: current.stateVersion,
                sessionId: planned.session.id, sessionName: "\(planned.session.sessionType.displayName)",
                meetingName: planned.meeting.name, countryCode: planned.meeting.countryCode,
                sourceStatus: .disconnected, sourceMode: .live, statusReason: "scheduled_session_waiting_for_live",
                sessionType: "\(planned.session.sessionType.displayName)", sessionStatus: nil,
                trackStatus: nil, lapCount: nil, updatedAt: nil, lastTransportAt: nil, drivers: [], raceControl: nil)
        }
        guard current.sourceStatus != .connected else { return current }
        return LiveSnapshot(schemaVersion: current.schemaVersion, stateVersion: current.stateVersion,
            sessionId: retained.sessionId, sessionName: retained.sessionName,
            meetingName: retained.meetingName, countryCode: retained.countryCode,
            sourceStatus: current.sourceStatus, sourceMode: current.sourceMode, statusReason: current.statusReason,
            sessionType: retained.sessionType, sessionStatus: retained.sessionStatus,
            trackStatus: nil, lapCount: nil, updatedAt: retained.updatedAt,
            lastTransportAt: current.lastTransportAt, drivers: [], raceControl: nil)
    }

    public static func preferredScreen<Screen>(in screens: [Screen], main: Screen?, hasBuiltInNotch: (Screen) -> Bool) -> Screen? {
        screens.first(where: hasBuiltInNotch) ?? main ?? screens.first
    }

    @MainActor
    public static func delayedHideTask(
        after duration: Duration,
        shouldHide: @escaping @MainActor () -> Bool,
        hide: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, shouldHide() else { return }
            await hide()
        }
    }

    public static func matchedDriver(
        favoriteId: String?,
        favorites: [FavoriteDriver],
        drivers: [LiveDriver]
    ) -> LiveDriver? {
        guard let favoriteId,
              let favorite = favorites.first(where: { $0.id == favoriteId })
        else {
            return nil
        }
        let name = normalizedDriverName(favorite.name)
        guard !name.isEmpty else { return nil }
        let matches = drivers.filter { normalizedDriverName($0.name ?? "") == name }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Follow state belongs to the driver, so a favourite car number driven by
    /// somebody else is not shown as followed.
    public static func isFavoriteDriver(_ driver: LiveDriver, favoriteId: String?, favorites: [FavoriteDriver]) -> Bool {
        guard favoriteId != nil else { return false }
        return matchedDriver(favoriteId: favoriteId, favorites: favorites, drivers: [driver]) != nil
    }

    public static func rosterID(for driver: LiveDriver, favorites: [FavoriteDriver]) -> String? {
        let name = normalizedDriverName(driver.name ?? "")
        guard !name.isEmpty else { return nil }
        let matches = favorites.filter { normalizedDriverName($0.name) == name }
        return matches.count == 1 ? matches[0].id : nil
    }

    /// Constructor id for a bundled team-logo asset.
    public static func teamAssetID(for driver: LiveDriver, isWec: Bool) -> String? {
        isWec ? wecTeamAssetID(for: driver) : f1TeamAssetID(for: driver)
    }

    /// WEC bundles one side view per car number; F1 publishes one per team.
    public static func carSideAssetID(for driver: LiveDriver, isWec: Bool) -> String? {
        isWec ? driver.number : f1TeamAssetID(for: driver)
    }

    private static func f1TeamAssetID(for driver: LiveDriver) -> String? {
        let known = [
            "red bull": "red_bull",
            "mercedes": "mercedes",
            "mclaren": "mclaren",
            "ferrari": "ferrari",
            "williams": "williams",
            "racing bulls": "rb",
            "aston martin": "aston_martin",
            "alpine": "alpine",
            "haas": "haas",
            "audi": "audi",
            "cadillac": "cadillac"
        ]
        for source in [driver.manufacturer, driver.team].compactMap({ $0?.lowercased() }) {
            if let id = known.first(where: { source.contains($0.key) })?.value {
                return id
            }
        }
        return nil
    }

    /// Marque logos bundled from the official WEC grid.
    private static let wecBrands: [(key: String, id: String)] = [
        ("alpine", "wec_alpine"),
        ("aston martin", "wec_aston_martin"),
        ("bmw", "wec_bmw"),
        ("cadillac", "wec_cadillac"),
        ("corvette", "wec_corvette"),
        ("ferrari", "wec_ferrari"),
        ("ford", "wec_ford"),
        ("genesis", "wec_genesis"),
        ("lexus", "wec_lexus"),
        ("mclaren", "wec_mclaren"),
        ("mercedes", "wec_mercedes"),
        ("peugeot", "wec_peugeot"),
        ("porsche", "wec_porsche"),
        ("toyota", "wec_toyota")
    ]

    /// Manufacturer logo for the WEC timing list, which shows the marque
    /// rather than the current driver portrait.
    public static func wecManufacturerAssetID(for driver: LiveDriver) -> String? {
        let source = (driver.manufacturer ?? "").lowercased()
        guard !source.isEmpty else { return nil }
        return wecBrands.first(where: { source.contains($0.key) })?.id
    }

    /// WEC teams publish their own logos for customer entries; manufacturer
    /// teams fall back to the marque logo used by the official grid.
    private static func wecTeamAssetID(for driver: LiveDriver) -> String? {
        let teams = [
            "garage 59": "wec_garage_59",
            "heart of racing team": "wec_heart_of_racing",
            "team wrt": "wec_team_wrt",
            "tf sport": "wec_tf_sport",
            "iron lynx": "wec_iron_lynx",
            "proton competition": "wec_proton_competition",
            "akkodis asp team": "wec_akkodis_asp",
            "manthey dk engineering": "wec_manthey_dk",
            "the bend manthey": "wec_the_bend_manthey"
        ]
        let team = normalizedName(driver.team ?? "")
        if let id = teams[team] { return id }
        for source in [driver.manufacturer, driver.team].compactMap({ $0?.lowercased() }) {
            if let id = wecBrands.first(where: { source.contains($0.key) })?.id { return id }
        }
        return nil
    }

    /// File-name id for the official WEC driver portrait bundled for a season.
    public static func driverAssetID(for driver: LiveDriver) -> String? {
        guard let name = driver.name, !name.isEmpty else { return nil }
        return assetSlug(name)
    }

    public static func assetSlug(_ value: String) -> String {
        let replacements = ["ø": "o", "Ø": "O", "æ": "ae", "Æ": "AE", "œ": "oe", "Œ": "OE", "ß": "ss", "ł": "l", "Ł": "L", "đ": "d", "Đ": "D", "ð": "d", "Ð": "D", "þ": "th", "Þ": "TH"]
        var text = value
        for (from, to) in replacements { text = text.replacingOccurrences(of: from, with: to) }
        return text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
            .lowercased()
    }

    /// Sector values arrive as "30.452" or "1:34.951"; WEC has no per-segment
    /// data, so this feeds the class-relative pace color of its sector bars.
    public static func sectorSeconds(_ value: String) -> Double? {
        let text = value.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: ":")
        if parts.count == 2 {
            guard let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        }
        return Double(text)
    }

    public static func followableDriverID(for driver: LiveDriver, favorites: [FavoriteDriver], drivers: [LiveDriver]) -> String? {
        guard let id = rosterID(for: driver, favorites: favorites),
              matchedDriver(favoriteId: id, favorites: favorites, drivers: drivers)?.number == driver.number else { return nil }
        return id
    }

    /// WEC drivers are absent from the F1 roster, so follow them by car number.
    public static func followableID(for driver: LiveDriver, favorites: [FavoriteDriver], drivers: [LiveDriver], isWec: Bool) -> String? {
        isWec ? "wec:\(driver.number)" : followableDriverID(for: driver, favorites: favorites, drivers: drivers)
    }

    public static func favorites(for series: LiveSeries, in favorites: [FavoriteDriver]) -> [FavoriteDriver] {
        favorites.filter { series == .wec ? $0.id.hasPrefix("wec:") : !$0.id.hasPrefix("wec:") }
    }

    private static func normalizedDriverName(_ name: String) -> String {
        let normalized = normalizedName(name)
        // Live uses Kimi Antonelli; the roster uses his full name Andrea Kimi Antonelli.
        return normalized == "kimi antonelli" ? "andrea kimi antonelli" : normalized
    }

    public static func isStarted(_ status: String?) -> Bool {
        status.map { ["started", "green", "inprogress"].contains(normalizedToken($0)) } ?? false
    }

    public static func isFinished(_ status: String?) -> Bool {
        status.map { ["finished", "finalised", "finalized", "ends", "aborted", "cancelled"].contains(normalizedToken($0)) } ?? false
    }

    public static func shouldAutomaticallyShow(
        enabled: Bool,
        dismissedSessionKey: String?,
        sessionKey: String?,
        sessionChanged: Bool,
        isHidden: Bool
    ) -> Bool {
        enabled && dismissedSessionKey != sessionKey && (sessionChanged || isHidden)
    }

    public static func currentScheduledSession(in meetings: [Meeting], now: Date) -> NextSession? {
        let matches = meetings
            .filter { $0.status == .scheduled }
            .flatMap { meeting in
                meeting.sessions.compactMap { session -> NextSession? in
                    guard session.status == .scheduled,
                          let endTime = session.endTime,
                          session.startTime <= now,
                          now < endTime
                    else { return nil }
                    return NextSession(meeting: meeting, session: session)
                }
            }
        return matches.count == 1 ? matches[0] : nil
    }

    public static func meeting(for snapshot: LiveSnapshot, in meetings: [Meeting], now: Date) -> Meeting? {
        if let name = snapshot.meetingName, let country = snapshot.countryCode {
            let matches = meetings.filter { normalizedName($0.name) == normalizedName(name) && $0.countryCode == country }
            if matches.count == 1 { return matches[0] }
        }
        guard snapshot.sourceStatus == .connected,
              isStarted(snapshot.sessionStatus),
              let sessionType = snapshot.sessionType
        else { return nil }

        let matches = meetings.filter { meeting in
            meeting.status == .scheduled && meeting.sessions.contains { session in
                session.status == .scheduled
                    && session.startTime <= now
                    && session.endTime.map { now < $0 } == true
                    && sessionTypeMatches(sessionType, session.sessionType)
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    public static func sessionLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "race": return "Race"
        case "sprint": return "Sprint"
        case "qualifying": return "Qualifying"
        case "practice": return "Practice"
        case "fp1": return "FP1"
        case "fp2": return "FP2"
        case "fp3": return "FP3"
        case "sprintqualifying", "sprint qualifying", "sprint shootout": return "Sprint Qualifying"
        default: return value
        }
    }

    public static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    private static func sessionTypeMatches(_ value: String, _ type: SessionType) -> Bool {
        let token = normalizedToken(value)
        return switch type {
        case .fp1: ["fp1", "practice", "practice1", "firstpractice"].contains(token)
        case .fp2: ["fp2", "practice2", "secondpractice"].contains(token)
        case .fp3: ["fp3", "practice3", "thirdpractice"].contains(token)
        case .sprintQualifying: ["sprintqualifying", "sprintshootout"].contains(token)
        case .sprint: token == "sprint"
        case .qualifying: ["qualifying", "qualification"].contains(token)
        case .race: ["race", "grandprix"].contains(token)
        }
    }

    private static func normalizedToken(_ value: String) -> String {
        normalizedName(value).replacingOccurrences(of: " ", with: "")
    }
}
