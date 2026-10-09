import CryptoKit
import Foundation

struct CachedCalendar: Codable, Sendable {
    static let currentVersion = 1

    let cacheVersion: Int
    let serverIdentity: String
    let season: Int
    let savedAt: Date
    let envelope: APIEnvelope<[Meeting]>
}

actor DiskCalendarCache {
    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL = DiskCalendarCache.defaultRootURL(), fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("PitPulse", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
    }

    func load(server: URL, season: Int) throws -> CachedCalendar? {
        let url = fileURL(server: server, season: season)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cached = try decoder.decode(CachedCalendar.self, from: data)
            guard cached.cacheVersion == CachedCalendar.currentVersion,
                  cached.serverIdentity == normalizedIdentity(server),
                  cached.season == season,
                  cached.envelope.meta.schemaVersion == APIClient.supportedSchemaVersion
            else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            return cached
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func save(
        server: URL,
        season: Int,
        envelope: APIEnvelope<[Meeting]>,
        savedAt: Date = Date()
    ) throws {
        let cached = CachedCalendar(
            cacheVersion: CachedCalendar.currentVersion,
            serverIdentity: normalizedIdentity(server),
            season: season,
            savedAt: savedAt,
            envelope: envelope
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cached)
        let url = fileURL(server: server, season: season)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    func clear(server: URL) throws {
        let directory = serverDirectory(server: server)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    func fileURL(server: URL, season: Int) -> URL {
        serverDirectory(server: server).appendingPathComponent("calendar-\(season).json")
    }

    private func serverDirectory(server: URL) -> URL {
        rootURL
            .appendingPathComponent("v\(CachedCalendar.currentVersion)", isDirectory: true)
            .appendingPathComponent(hash(normalizedIdentity(server)), isDirectory: true)
    }

    private func normalizedIdentity(_ server: URL) -> String {
        (try? ServerAddress(rawValue: server.absoluteString).identity) ?? server.absoluteString
    }

    private func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
