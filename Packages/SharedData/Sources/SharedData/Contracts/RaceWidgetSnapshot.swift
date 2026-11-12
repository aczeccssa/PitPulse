import Foundation

/// The app publishes a token-free next-session cache. Widgets never contact providers.
public struct RaceWidgetSnapshot: Codable, Equatable, Sendable {
    public var meeting: String
    public var session: String
    public var start: Date
    public var savedAt: Date
    public var round: Int?
    public var location: String?
    public var sessions: [RaceWidgetSession]?
    public init(meeting: String, session: String, start: Date, savedAt: Date = .now,
                round: Int? = nil, location: String? = nil, sessions: [RaceWidgetSession]? = nil) {
        self.meeting = meeting; self.session = session; self.start = start; self.savedAt = savedAt
        self.round = round; self.location = location; self.sessions = sessions
    }
    public func advancing(to date: Date) -> RaceWidgetSnapshot? {
        let future = sessions?.filter { $0.start >= date }.min { $0.start < $1.start }
        guard let future else { return start >= date ? self : nil }
        var copy = self
        copy.session = future.title
        copy.start = future.start
        return copy
    }
    public func isStale(at date: Date) -> Bool { date.timeIntervalSince(savedAt) > 3600 * 6 }
}

public struct RaceWidgetSession: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public init(id: String, title: String, start: Date) { self.id = id; self.title = title; self.start = start }
}
