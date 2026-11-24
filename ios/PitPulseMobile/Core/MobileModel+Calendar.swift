import Foundation
import SharedData

extension MobileModel {
    func loadCalendar(force: Bool = false) async {
        guard let serverURL else {
            loadState = .failed(APIClientError.invalidServerAddress(serverText).localizedDescription)
            return
        }
        if !force, loadState.lastLoaded != nil { return }
        let context = dataContext
        let selectedSeason = season
        let requestID = UUID()
        calendarRequestID = requestID
        if meetings.isEmpty, let cached = try? await cache.load(server: serverURL, season: selectedSeason) {
            guard dataContext == context, calendarRequestID == requestID, !Task.isCancelled else { return }
            meetings = cached.envelope.data.sorted { $0.startDate < $1.startDate }
            updateScheduledLiveSession()
            publishWidget(savedAt: cached.envelope.meta.stale ? .distantPast : cached.savedAt)
        }
        loadState = .loading
        do {
            let envelope = try await APIClient(baseURL: serverURL).calendar(season: selectedSeason, token: currentToken)
            guard dataContext == context, calendarRequestID == requestID, !Task.isCancelled else { return }
            meetings = envelope.data.sorted { $0.startDate < $1.startDate }
            updateScheduledLiveSession()
            loadState = meetings.isEmpty
                ? .failed("The server has no F1 calendar for \(selectedSeason). Check the server address or sync status.")
                : .loaded(Date())
            publishWidget(savedAt: envelope.meta.stale ? .distantPast : (envelope.meta.fetchedAt ?? .distantPast))
            if !envelope.meta.stale, selectedSeason == reminderSeason {
                await syncReminders(envelope.data, server: serverURL, season: selectedSeason) {
                    self.dataContext == context && self.calendarRequestID == requestID
                }
            }
            try? await cache.save(server: serverURL, season: selectedSeason, envelope: envelope)
        } catch {
            guard dataContext == context, calendarRequestID == requestID, !Task.isCancelled else { return }
            loadState = .failed((meetings.isEmpty ? "" : "Cached data · ") + Self.message(for: error))
        }
    }
    var reminderSeason: Int { Calendar(identifier: .gregorian).component(.year, from: .now) }

    func setRemindersEnabled(_ enabled: Bool) async {
        guard !updatingReminderPreference else { return }
        updatingReminderPreference = true
        defer { updatingReminderPreference = false }
        reminderMessage = nil
        do {
            if enabled {
                let allowed = try await reminderCoordinator.authorize()
                reminderPermissionDenied = !allowed
                guard !reminderPermissionDenied else { return }
            }
            remindersEnabled = enabled
            defaults.set(enabled, forKey: PreferenceKeys.remindersEnabled)
            if !enabled {
                reminderPermissionDenied = false
                try await reminderCoordinator.sync([])
            } else if season == reminderSeason {
                await loadCalendar(force: true)
            } else {
                await loadCurrentSeasonLiveCalendar()
            }
        } catch {
            reminderMessage = Self.message(for: error)
        }
    }

    func syncReminders(
        _ meetings: [Meeting], server: URL, season: Int, isCurrent: () -> Bool
    ) async {
        guard remindersEnabled else { return }
        let authorized = await reminderCoordinator.authorization() == .authorized
        guard !Task.isCancelled, remindersEnabled, isCurrent() else { return }
        reminderPermissionDenied = !authorized
        guard authorized else { return }
        let reminders = SessionReminderPlanner.reminders(
            meetings: meetings, serverIdentity: server.absoluteString, season: season,
            minutesBefore: SessionReminderPlanner.defaultMinutes, now: .now
        )
        do {
            // Keep the nearest sessions within iOS's pending notification budget.
            try await reminderCoordinator.sync(Array(reminders.prefix(48)))
            if remindersEnabled, isCurrent() { reminderMessage = nil }
        } catch {
            if remindersEnabled, isCurrent() { reminderMessage = Self.message(for: error) }
        }
    }

    func loadSeasonArchive(force: Bool = false) async {
        if let seasonArchiveTask {
            await seasonArchiveTask.value
            return
        }
        guard force || seasonArchive == nil else { return }
        guard let serverURL else {
            seasonArchiveError = "服务器地址无效"
            return
        }
        let context = dataContext
        let requestSeason = season
        let token = currentToken
        let task = Task {
            do {
                let envelope = try await APIClient(baseURL: serverURL).seasonResults(season: requestSeason, token: token)
                guard context == dataContext, !Task.isCancelled else { return }
                seasonArchive = envelope
                seasonArchiveError = nil
            } catch {
                guard context == dataContext, !Task.isCancelled else { return }
                seasonArchiveError = Self.message(for: error)
            }
            seasonArchiveTask = nil
        }
        seasonArchiveTask = task
        await task.value
    }

    func loadWidgetHighlights(force: Bool = false) async {
        guard let serverURL else { return }
        let races = completedRaces(limit: 3)
        guard let newest = races.first else { return }
        let baseContext = dataContext
        let context = "\(baseContext)|" + races.map(\.session.id).joined(separator: ",")
        guard force || widgetHighlightsContext != context else { return }
        let client = APIClient(baseURL: serverURL)
        var sources: [FavoriteRaceSource] = []
        for race in races {
            do {
                let response = try await client.sessionResults(sessionId: race.session.id, token: currentToken)
                guard baseContext == dataContext, !Task.isCancelled else { return }
                guard !response.data.isEmpty else { continue }
                sources.append(FavoriteRaceSource(meeting: race.meeting, session: race.session,
                    results: response.data,
                    savedAt: response.meta.stale ? .distantPast : (response.meta.fetchedAt ?? .now)))
            } catch {
                continue
            }
        }
        guard let newestSource = sources.first(where: { $0.session.id == newest.session.id }) else { return }
        widgetHighlightsContext = context
        recentRaceSources = sources
        recentRaceSavedAt = sources.contains { $0.savedAt == .distantPast }
            ? .distantPast
            : (sources.map(\.savedAt).max() ?? .distantPast)
        // Results are enough for the podium, fastest lap and distance. Safety-car
        // periods need the much heavier analysis payload, so the widget omits them
        // rather than making every launch download telemetry.
        widgetPublisher.publishLastRace(meeting: newestSource.meeting, session: newestSource.session,
            results: newestSource.results, savedAt: newestSource.savedAt)
        publishFavoriteWidget()
    }
    func completedRaces(limit: Int) -> [(meeting: Meeting, session: Session)] {
        let now = Date()
        let races = meetings
            .compactMap { meeting -> (Meeting, Session)? in
                let race = meeting.sessions
                    .filter { $0.sessionType == .race && $0.status != .cancelled && $0.status != .postponed }
                    .filter { session in
                        if session.status == .finished { return true }
                        guard session.status != .live else { return false }
                        let end = session.endTime ?? session.startTime.addingTimeInterval(3 * 3600)
                        return end < now
                    }
                    .max { $0.startTime < $1.startTime }
                return race.map { (meeting, $0) }
            }
            .sorted { $0.1.startTime > $1.1.startTime }
        return Array(races.prefix(limit))
    }
}
