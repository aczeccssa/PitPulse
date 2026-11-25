import Foundation

public struct NextSeasonSchedule: Codable, Sendable {
    public let year: Int
    public let sourceUrl: URL
    public let updatedAt: String?
    public let events: [Event]

    public struct Event: Codable, Identifiable, Sendable {
        public let id: String
        public let round: Int?
        public let name: String
        public let location: String
        public let startDate: String
        public let endDate: String
    }
}
