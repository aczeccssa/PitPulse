import Foundation

/// Only the two widget destinations are accepted; no arbitrary URL dispatch.
public enum WidgetDestination: String, Sendable {
    case calendar, live

    public init?(url: URL) {
        guard ["pitpulse", "pitpulse-desktop"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              url.path.isEmpty || url.path == "/",
              let host = url.host, let destination = Self(rawValue: host) else { return nil }
        self = destination
    }

    public var url: URL {
        #if os(macOS)
        URL(string: "pitpulse-desktop://\(rawValue)")!
        #else
        URL(string: "pitpulse://\(rawValue)")!
        #endif
    }
}
