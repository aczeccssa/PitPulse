import Foundation

public struct ServerAddress: Equatable, Sendable {
    public let url: URL

    public var identity: String {
        url.absoluteString
    }

    /// Accepts any host / IP and either `http` or `https`.
    /// A missing scheme defaults to `http`, because the server is self-hosted
    /// and is commonly reached by LAN IP; type `https://…` explicitly when the
    /// deployment terminates TLS.
    public init(rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIClientError.invalidServerAddress(rawValue)
        }

        let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"

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
}
