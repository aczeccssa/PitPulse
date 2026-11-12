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
            publishWidget(savedAt: cached.envelope.meta.stale ? .distantPast : cached.savedAt)
        }
        loadState = .loading
        do {
            let envelope = try await APIClient(baseURL: serverURL).calendar(season: selectedSeason, token: currentToken)
            guard dataContext == context, calendarRequestID == requestID, !Task.isCancelled else { return }
            meetings = envelope.data.sorted { $0.startDate < $1.startDate }
            loadState = meetings.isEmpty
                ? .failed("当前服务器尚无 \(selectedSeason) 赛季 F1 赛历。请检查服务地址或服务器同步状态。")
                : .loaded(Date())
            publishWidget(savedAt: envelope.meta.stale ? .distantPast : (envelope.meta.fetchedAt ?? .distantPast))
            try? await cache.save(server: serverURL, season: selectedSeason, envelope: envelope)
        } catch {
            guard dataContext == context, calendarRequestID == requestID, !Task.isCancelled else { return }
            loadState = .failed((meetings.isEmpty ? "" : "缓存数据 · ") + Self.message(for: error))
        }
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
