import CryptoKit
import Foundation

public struct CachedCalendar: Codable, Sendable {
    public static let currentVersion = 1

    public let cacheVersion: Int
    public let serverIdentity: String
    public let season: Int
    public let savedAt: Date
    public let envelope: APIEnvelope<[Meeting]>
}

private struct CachedEndpoint<Value: Codable & Sendable>: Codable, Sendable {
    public let cacheVersion: Int
    public let serverIdentity: String
    public let season: Int
    public let savedAt: Date
    public let envelope: APIEnvelope<Value>
}

public actor DiskCalendarCache {
    private let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL = DiskCalendarCache.defaultRootURL(), fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("PitPulse", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
    }

    public func load(server: URL, season: Int) throws -> CachedCalendar? {
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

    public func save(
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

    public func load<Value: Codable & Sendable>(
        server: URL,
        season: Int,
        key: String,
        as: Value.Type
    ) throws -> APIEnvelope<Value>? {
        let url = endpointURL(server: server, season: season, key: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cached = try decoder.decode(CachedEndpoint<Value>.self, from: Data(contentsOf: url))
            guard cached.cacheVersion == CachedCalendar.currentVersion,
                  cached.serverIdentity == normalizedIdentity(server),
                  cached.season == season,
                  cached.envelope.meta.schemaVersion == APIClient.supportedSchemaVersion
            else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            return cached.envelope
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    public func save<Value: Codable & Sendable>(
        server: URL,
        season: Int,
        key: String,
        envelope: APIEnvelope<Value>
    ) throws {
        let cached = CachedEndpoint(
            cacheVersion: CachedCalendar.currentVersion,
            serverIdentity: normalizedIdentity(server),
            season: season,
            savedAt: Date(),
            envelope: envelope
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cached)
        let url = endpointURL(server: server, season: season, key: key)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    public func clear(server: URL) throws {
        let directory = serverDirectory(server: server)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    public func fileURL(server: URL, season: Int) -> URL {
        serverDirectory(server: server).appendingPathComponent("calendar-\(season).json")
    }

    private func serverDirectory(server: URL) -> URL {
        rootURL
            .appendingPathComponent("v\(CachedCalendar.currentVersion)", isDirectory: true)
            .appendingPathComponent(hash(normalizedIdentity(server)), isDirectory: true)
    }

    private func endpointURL(server: URL, season: Int, key: String) -> URL {
        serverDirectory(server: server).appendingPathComponent("\(season)-\(hash(key)).json")
    }

    private func normalizedIdentity(_ server: URL) -> String {
        (try? ServerAddress(rawValue: server.absoluteString).identity) ?? server.absoluteString
    }

    private func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
