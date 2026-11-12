import AppKit
import Foundation
import SharedData

extension AppModel {
    func sessionAnalysis(sessionID: String, driverID: String, season: Int, lap: Int?) async throws -> APIEnvelope<SessionAnalysis> {
        try await analysis(key: "analysis-\(sessionID)-\(driverID)-\(lap ?? 0)", season: season) { client, token in
            try await client.sessionAnalysis(sessionId: sessionID, driverId: driverID, lap: lap, token: token)
        }
    }

    func seasonAnalysis(kind: String, id: String, season: Int) async throws -> APIEnvelope<SeasonAnalysis> {
        try await analysis(key: "analysis-\(kind)-\(id)", season: season) { client, token in
            try await client.seasonAnalysis(kind: kind, id: id, season: season, token: token)
        }
    }

    func cachedAnalysis<Value: Codable & Sendable>(key: String, season: Int, as type: Value.Type) async -> APIEnvelope<Value>? {
        guard let server = configuredServer else { return nil }
        let value = try? await cache.load(server: server.url, season: season, key: key, as: type)
        guard server == configuredServer, !Task.isCancelled else { return nil }
        return value
    }

    func analysis<Value: Codable & Sendable>(key: String, season: Int,
        fetch: (APIClient, String?) async throws -> APIEnvelope<Value>) async throws -> APIEnvelope<Value> {
        guard let server = configuredServer else { throw APIClientError.invalidServerAddress(serverAddress) }
        do {
            let token = try credentials.token(for: server.url)
            let value = try await fetch(APIClient(baseURL: server.url, session: session), token)
            try Task.checkCancellation()
            guard server == configuredServer else { throw CancellationError() }
            if value.meta.analysisCanBeCached {
                try? await cache.save(server: server.url, season: season, key: key, envelope: value)
            }
            return value
        } catch {
            if error is CancellationError { throw error }
            guard server == configuredServer else { throw CancellationError() }
            // Authorization failures must not expose a previous authenticated response.
            if let apiError = error as? APIClientError, apiError == .unauthorized { throw error }
            if let old = try? await cache.load(server: server.url, season: season, key: key, as: Value.self) {
                return APIEnvelope(data: old.data, meta: ResponseMeta(schemaVersion: old.meta.schemaVersion,
                    revision: old.meta.revision, stale: true, quality: old.meta.quality, source: old.meta.source,
                    fetchedAt: old.meta.fetchedAt, sourceUpdatedAt: old.meta.sourceUpdatedAt))
            }
            throw error
        }
    }
}
