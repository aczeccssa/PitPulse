import CryptoKit
import Foundation
import Observation
import SharedData
import WidgetKit

/// The host app refreshes this cache. Extensions only read the published index and blobs.
@MainActor
@Observable
public final class MediaCache {
    public static let shared = MediaCache()

    struct Group: Codable {
        let hash: String
        let files: [String: String]
    }

    struct Manifest: Codable {
        let groups: [String: Group]
    }

    private struct Catalog: Codable {
        var etag: String?
        var target: Manifest?
        var installed: [String: Group] = [:]
    }

    private let root: URL
    private let session: URLSession
    private let onPublish: () -> Void
    private var directory: URL?
    private var catalog = Catalog()
    private(set) var pending: Task<Void, Never>?
    private var generation = 0
    private var lastCheck: Date?
    private var lastRepair: Date?
    private var selectedServer: URL?
    private var selectedToken: String?
    private var online = false
    private let readsPublishedIndex = Bundle.main.bundleURL.pathExtension == "appex"
    private var publishedAt: Date?

    init(root: URL? = nil, session: URLSession = .shared, onPublish: @escaping () -> Void = {
        WidgetCenter.shared.reloadAllTimelines()
    }) {
        let fm = FileManager.default
        self.root = root ?? (fm.containerURL(forSecurityApplicationGroupIdentifier: RaceWidgetCache.group)
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0])
            .appending(path: "PitPulseMedia", directoryHint: .isDirectory)
        self.session = session
        self.onPublish = onPublish
        readPublishedIndex()
    }

    /// Call at startup, server selection, and reconnection. Cache hits only read local files.
    public func refresh(from server: URL?, token: String? = nil, online: Bool = true) {
        refresh(from: server, token: token, online: online, repair: false)
    }

    private func refresh(from server: URL?, token: String?, online: Bool, repair: Bool) {
        guard !readsPublishedIndex else { return }
        let credentialsChanged = selectedToken != token
        selectedToken = token
        selectedServer = server
        self.online = online
        let next = server.map {
            root.appending(path: Self.digest(Data($0.absoluteString.utf8)), directoryHint: .isDirectory)
        }
        if next != directory || credentialsChanged {
            pending?.cancel()
            pending = nil
            generation += 1
            lastCheck = nil
            lastRepair = nil
        }
        let changedServer = next != directory
        if changedServer { load(next) }
        let active = root.appending(path: "active")
        if let next, changedServer || !FileManager.default.fileExists(atPath: active.path) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? next.lastPathComponent.write(to: active, atomically: true, encoding: .utf8)
        } else if next == nil, changedServer {
            try? FileManager.default.removeItem(at: active)
        }
        guard online, let server, let next, pending == nil else { return }
        if repair {
            if let lastRepair, Date().timeIntervalSince(lastRepair) < 60 { return }
            lastRepair = Date()
        } else if let lastCheck, Date().timeIntervalSince(lastCheck) < 60 {
            return
        }
        let current = generation
        pending = Task {
            let checked = await synchronize(server: server, token: token, directory: next)
            if generation == current {
                pending = nil
                if checked { lastCheck = Date() }
            }
        }
    }

    func file(group: String, name: String) -> URL? {
        if readsPublishedIndex { readPublishedIndex() }
        guard let directory, let digest = catalog.installed[group]?.files[name],
              Self.isDigest(digest) else { return nil }
        let url = Self.blobURL(digest, in: directory)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        if !readsPublishedIndex {
            Task { refresh(from: selectedServer, token: selectedToken, online: online, repair: true) }
        }
        return nil
    }

    private func readPublishedIndex() {
        let key = try? String(contentsOf: root.appending(path: "active"), encoding: .utf8)
        let next = key.flatMap {
            Self.isDigest($0) ? root.appending(path: $0, directoryHint: .isDirectory) : nil
        }
        let date = next.flatMap {
            try? $0.appending(path: "index.json").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        if next != directory || date != publishedAt {
            load(next)
            publishedAt = date
        }
    }

    private func load(_ directory: URL?) {
        self.directory = directory
        catalog = directory.flatMap { try? Data(contentsOf: $0.appending(path: "index.json")) }
            .flatMap { try? JSONDecoder().decode(Catalog.self, from: $0) } ?? Catalog()
    }

    private func synchronize(server: URL, token: String?, directory: URL) async -> Bool {
        var updated = false
        defer {
            if updated, !Task.isCancelled { onPublish() }
        }
        do {
            try FileManager.default.createDirectory(at: directory.appending(path: "blobs"), withIntermediateDirectories: true)
            var request = URLRequest(url: server.appending(path: "api/v1/media/manifest.json"),
                                     cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            request.setValue(catalog.etag, forHTTPHeaderField: "If-None-Match")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 200 {
                let manifest = try JSONDecoder().decode(Manifest.self, from: data)
                catalog.target = manifest
                catalog.etag = http.value(forHTTPHeaderField: "ETag")
                try publish(to: directory)
            } else if http.statusCode != 304 { return false }
            guard let target = catalog.target else { return false }
            let groups = target.groups.filter { $0.key != "web-brand" }
            // Brand and navigation become available early on a fresh install.
            let order = ["native-brand", "native-navigation", "flags", "native-flags"]
            let keys = order.filter { groups[$0] != nil } + groups.keys.filter { !order.contains($0) }.sorted()
            for key in keys {
                try Task.checkCancellation()
                guard let group = groups[key] else { continue }
                let installed = catalog.installed[key]
                let missing = Set(group.files.values).filter {
                    !Self.isDigest($0) || !FileManager.default.fileExists(atPath: Self.blobURL($0, in: directory).path)
                }.sorted()
                if installed?.hash == group.hash && missing.isEmpty { continue }
                do {
                    try await fetchMissing(missing, from: server, token: token, into: directory)
                    try Task.checkCancellation()
                    var next = catalog
                    next.installed[key] = group
                    try publish(next, to: directory)
                    catalog = next
                    updated = true
                } catch {
                    try Task.checkCancellation()
                    // Keep this group's last complete version and let other groups advance.
                    continue
                }
            }
            let retired = catalog.installed.keys.filter { groups[$0] == nil }
            if !retired.isEmpty {
                var next = catalog
                for key in retired { next.installed.removeValue(forKey: key) }
                try publish(next, to: directory)
                catalog = next
                updated = true
            }
            if !FileManager.default.fileExists(atPath: directory.appending(path: "index.json").path) {
                try publish(to: directory)
                updated = true
            }
            return true
        } catch {
            // Offline and older servers keep the published cache available.
            return false
        }
    }

    private func publish(_ value: Catalog? = nil, to directory: URL) throws {
        try JSONEncoder().encode(value ?? catalog).write(to: directory.appending(path: "index.json"), options: .atomic)
    }

    private func fetchMissing(_ missing: [String], from server: URL, token: String?, into directory: URL) async throws {
        let session = self.session
        for start in stride(from: 0, to: missing.count, by: 6) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for hash in missing[start..<min(start + 6, missing.count)] {
                    group.addTask {
                        guard Self.isDigest(hash) else { throw URLError(.cannotDecodeContentData) }
                        let url = server.appending(path: "api/v1/media/blob").appending(path: hash)
                        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
                        let (data, response) = try await session.data(for: request)
                        guard (response as? HTTPURLResponse)?.statusCode == 200,
                              Self.digest(data) == hash else { throw URLError(.cannotDecodeContentData) }
                        try Task.checkCancellation()
                        try data.write(to: Self.blobURL(hash, in: directory), options: .atomic)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    nonisolated private static func blobURL(_ digest: String, in directory: URL) -> URL {
        directory.appending(path: "blobs").appending(path: digest + ".png")
    }

    nonisolated static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func isDigest(_ string: String) -> Bool {
        string.utf8.count == 64 && string.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
