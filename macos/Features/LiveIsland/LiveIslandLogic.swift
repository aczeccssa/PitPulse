import Foundation

enum LiveIslandLogic {
    static func displayedSnapshot(current: LiveSnapshot, lastKnown: LiveSnapshot?, meetings: [Meeting], now: Date) -> LiveSnapshot {
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

    static func preferredScreen<Screen>(in screens: [Screen], main: Screen?, hasBuiltInNotch: (Screen) -> Bool) -> Screen? {
        screens.first(where: hasBuiltInNotch) ?? main ?? screens.first
    }

    @MainActor
    static func delayedHideTask(
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

    static func matchedDriver(
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

    static func rosterID(for driver: LiveDriver, favorites: [FavoriteDriver]) -> String? {
        let name = normalizedDriverName(driver.name ?? "")
        guard !name.isEmpty else { return nil }
        let matches = favorites.filter { normalizedDriverName($0.name) == name }
        return matches.count == 1 ? matches[0].id : nil
    }

    static func followableDriverID(for driver: LiveDriver, favorites: [FavoriteDriver], drivers: [LiveDriver]) -> String? {
        guard let id = rosterID(for: driver, favorites: favorites),
              matchedDriver(favoriteId: id, favorites: favorites, drivers: drivers)?.number == driver.number else { return nil }
        return id
    }

    private static func normalizedDriverName(_ name: String) -> String {
        let normalized = normalizedName(name)
        // Live uses Kimi Antonelli; the roster uses his full name Andrea Kimi Antonelli.
        return normalized == "kimi antonelli" ? "andrea kimi antonelli" : normalized
    }

    static func isStarted(_ status: String?) -> Bool {
        status.map { ["started", "green", "inprogress"].contains(normalizedToken($0)) } ?? false
    }

    static func isFinished(_ status: String?) -> Bool {
        status.map { ["finished", "finalised", "finalized", "ends", "aborted", "cancelled"].contains(normalizedToken($0)) } ?? false
    }

    static func shouldAutomaticallyShow(
        enabled: Bool,
        dismissedSessionKey: String?,
        sessionKey: String?,
        sessionChanged: Bool,
        isHidden: Bool
    ) -> Bool {
        enabled && dismissedSessionKey != sessionKey && (sessionChanged || isHidden)
    }

    static func currentScheduledSession(in meetings: [Meeting], now: Date) -> NextSession? {
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

    static func meeting(for snapshot: LiveSnapshot, in meetings: [Meeting], now: Date) -> Meeting? {
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

    static func normalizedName(_ name: String) -> String {
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
