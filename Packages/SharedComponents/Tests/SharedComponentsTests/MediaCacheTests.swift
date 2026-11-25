import Foundation
import SharedData
import Testing
@testable import SharedComponents

@Suite(.serialized)
@MainActor
struct MediaCacheTests {
    @Test func persistsAndRepairsGroupsWithoutRequestingCachedBlobs() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = try #require(URL(string: "https://media.test/pitpulse"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MediaTransport.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let original = Data("original".utf8)
        let shared = Data("unchanged".utf8)
        let updated = Data("updated".utf8)
        let firstHash = MediaCache.digest(original)
        let sharedHash = MediaCache.digest(shared)
        let nextHash = MediaCache.digest(updated)
        let first = try manifest(version: "first", image: firstHash, shared: sharedHash)
        let second = try manifest(version: "second", image: nextHash, shared: sharedHash)

        func client() -> MediaCache { MediaCache(root: root, session: session, onPublish: {}) }
        let initial = client()
        MediaTransport.fixture.install(first, etag: "first", blobs: [firstHash: original, sharedHash: shared])
        initial.refresh(from: origin)
        await initial.pending?.value
        let file = try #require(initial.file(group: "native-brand", name: "logo.png"))
        #expect(try Data(contentsOf: file) == original)
        #expect(MediaTransport.fixture.blobRequests == Set([firstHash, sharedHash]))

        let warm = client()
        MediaTransport.fixture.install(first, etag: "first", blobs: [:])
        warm.refresh(from: origin)
        await warm.pending?.value
        #expect(MediaTransport.fixture.manifestHeaders == ["first"])
        #expect(MediaTransport.fixture.blobRequests.isEmpty)
        #expect(warm.file(group: "native-brand", name: "logo.png") == file)

        try FileManager.default.removeItem(at: file)
        try FileManager.default.removeItem(at: root.appending(path: "active"))
        MediaTransport.fixture.install(first, etag: "first", blobs: [firstHash: original])
        #expect(warm.file(group: "native-brand", name: "logo.png") == nil)
        for _ in 0..<100 {
            if let repair = warm.pending {
                await repair.value
                break
            }
            if FileManager.default.fileExists(atPath: file.path) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(MediaTransport.fixture.blobRequests == Set([firstHash]))
        #expect(try Data(contentsOf: file) == original)
        #expect(client().file(group: "native-brand", name: "logo.png") == file)

        let failed = client()
        MediaTransport.fixture.install(second, etag: "second", blobs: [nextHash: Data("corrupt".utf8)])
        failed.refresh(from: origin)
        await failed.pending?.value
        #expect(failed.file(group: "native-brand", name: "logo.png") == file)
        #expect(MediaTransport.fixture.blobRequests == Set([nextHash]))

        let recovered = client()
        MediaTransport.fixture.install(second, etag: "second", blobs: [nextHash: updated])
        recovered.refresh(from: origin)
        await recovered.pending?.value
        #expect(MediaTransport.fixture.manifestHeaders == ["second"])
        #expect(MediaTransport.fixture.blobRequests == Set([nextHash]))
        let new = try #require(recovered.file(group: "native-brand", name: "logo.png"))
        #expect(try Data(contentsOf: new) == updated)

        let other = try #require(URL(string: "https://other.test/pitpulse"))
        recovered.refresh(from: other, online: false)
        #expect(recovered.file(group: "native-brand", name: "logo.png") == nil)
        recovered.refresh(from: origin, online: false)
        #expect(recovered.file(group: "native-brand", name: "logo.png") == new)
    }

    @Test func driverAvatarsPreferHelmetsThenSameSeasonPortraits() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = try #require(URL(string: "https://media.test/pitpulse"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MediaTransport.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let photo2024 = Data("2024 portrait".utf8)
        let photo2025 = Data("2025 portrait".utf8)
        let helmet2026 = Data("2026 helmet".utf8)
        let images = [photo2024, photo2025, helmet2026]
        let hashes = images.map(MediaCache.digest)
        let manifest = try JSONEncoder().encode(MediaCache.Manifest(groups: [
            "2024/driver-photo": .init(hash: "2024", files: ["max_verstappen.png": hashes[0]]),
            "2025/driver-photo": .init(hash: "2025", files: ["max_verstappen.png": hashes[1]]),
            "2026/driver-photo": .init(hash: "2026-photo", files: ["max_verstappen.png": hashes[1]]),
            "native-2026/helmet": .init(hash: "2026-helmet", files: ["helmet-max_verstappen-2026.png": hashes[2]])
        ]))
        MediaTransport.fixture.install(manifest, etag: "avatars", blobs: Dictionary(uniqueKeysWithValues: zip(hashes, images)))
        let cache = MediaCache(root: root, session: session, onPublish: {})
        cache.refresh(from: origin)
        await cache.pending?.value

        for (season, expected) in zip(2024...2026, images) {
            let avatar = MotorsportAssetName.driverAvatarName(driverID: "verstappen", name: "Max Verstappen", season: season)
            let file = try #require(MotorsportImages.artworkURL(named: avatar, dark: false, cache: cache))
            #expect(try Data(contentsOf: file) == expected)
        }
        let historicalHelmet = MotorsportAssetName.helmetName(driverID: "verstappen", name: "Max Verstappen", season: 2025)
        #expect(MotorsportImages.artworkURL(named: historicalHelmet, dark: false, cache: cache) == nil)
        let missingSeason = MotorsportAssetName.driverAvatarName(driverID: "verstappen", name: "Max Verstappen", season: 2023)
        #expect(MotorsportImages.artworkURL(named: missingSeason, dark: false, cache: cache) == nil)
    }

    private func manifest(version: String, image: String, shared: String) throws -> Data {
        try JSONEncoder().encode(MediaCache.Manifest(groups: [
            "native-brand": .init(hash: version, files: ["logo.png": image]),
            "flags": .init(hash: "flags", files: ["flag-jp.png": shared])
        ]))
    }
}

private final class MediaTransport: URLProtocol, @unchecked Sendable {
    static let fixture = Fixture()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, etag, body) = Self.fixture.respond(to: request, url: url)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["ETag": etag])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    final class Fixture: @unchecked Sendable {
        private let lock = NSLock()
        private var manifest = Data()
        private var etag = ""
        private var blobs: [String: Data] = [:]
        private var requestedBlobs: Set<String> = []
        private var requestedTags: [String] = []

        var blobRequests: Set<String> { lock.withLock { requestedBlobs } }
        var manifestHeaders: [String] { lock.withLock { requestedTags } }

        func install(_ manifest: Data, etag: String, blobs: [String: Data]) {
            lock.withLock {
                self.manifest = manifest
                self.etag = etag
                self.blobs = blobs
                requestedBlobs.removeAll()
                requestedTags.removeAll()
            }
        }

        func respond(to request: URLRequest, url: URL) -> (Int, String, Data) {
            lock.withLock {
                if url.path == "/pitpulse/api/v1/media/manifest.json" {
                    let tag = request.value(forHTTPHeaderField: "If-None-Match") ?? ""
                    requestedTags.append(tag)
                    return tag == etag ? (304, etag, Data()) : (200, etag, manifest)
                }
                guard url.path.hasPrefix("/pitpulse/api/v1/media/blob/") else { return (404, etag, Data()) }
                let digest = url.lastPathComponent
                requestedBlobs.insert(digest)
                guard let bytes = blobs[digest] else { return (404, etag, Data()) }
                return (200, etag, bytes)
            }
        }
    }
}
