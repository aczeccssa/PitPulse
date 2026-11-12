import Foundation

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
