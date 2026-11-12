import AppKit
import Foundation
import SharedData

extension AppModel {
    func clearCurrentCache() {
        guard let server = configuredServer else { return }
        Task {
            do {
                try await cache.clear(server: server.url)
                settingsMessage = "当前服务器缓存已清除"
            } catch {
                settingsMessage = error.localizedDescription
            }
        }
    }
    func loadCachedIfAvailable() async {
        guard let server = configuredServer else { return }
        let season = selectedSeason
        let cacheGeneration = generation
        do {
            let cached = try await cache.load(server: server.url, season: season)
            guard cacheGeneration == generation,
                  server == configuredServer, season == selectedSeason else { return }
            if let cached {
                meetings = cached.envelope.data
                meta = cached.envelope.meta
                widgetPublisher?.publishCalendar(meetings: meetings, savedAt: cached.envelope.meta.stale ? .distantPast : cached.savedAt)
                lastSuccessfulLoadAt = cached.savedAt
                // Cached content is not a successful connection in this process.
                nextMeetingOverride = nil
                connectionStatus = Date().timeIntervalSince(cached.savedAt) > Self.staleCacheInterval
                    ? .offline
                    : .stale
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func validServerNextMeeting(_ meeting: Meeting?) -> Meeting? {
        guard let meeting,
              CalendarLogic.nextSession(in: [meeting], now: Date()) != nil
        else {
            return nil
        }
        return meeting
    }
}
