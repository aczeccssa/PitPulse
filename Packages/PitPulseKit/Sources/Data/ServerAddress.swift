import Foundation

public struct ServerAddress: Equatable, Sendable {
    public let url: URL

    public var identity: String {
        url.absoluteString
    }

    public init(rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIClientError.invalidServerAddress(rawValue)
        }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else {
            let hostPart = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init) ?? trimmed
            let host = hostPart.split(separator: ":", maxSplits: 1).first.map(String.init) ?? hostPart
            let scheme = ["localhost", "127.0.0.1", "::1"].contains(host) ? "http" : "https"
            candidate = "\(scheme)://\(trimmed)"
        }

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw APIClientError.invalidServerAddress(rawValue)
        }

        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if scheme == "http" && !Self.isLoopback(normalizedHost) {
            throw APIClientError.insecureRemoteServer
        }

        components.host = host
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        components.scheme = scheme
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else {
            throw APIClientError.invalidServerAddress(rawValue)
        }
        self.url = url
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
