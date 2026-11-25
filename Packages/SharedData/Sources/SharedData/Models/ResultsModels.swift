import Foundation

/// A server-assigned media object. The URL is relative to the configured server.
public struct MediaReference: Codable, Equatable, Sendable {
    public let group: String
    public let file: String
    public let sha256: String
    public let url: String
    public let isPlaceholder: Bool
}

public struct DriverMedia: Codable, Equatable, Sendable {
    public let avatar: MediaReference?
    public let helmet: MediaReference
    public let driverPhoto: MediaReference
}

public struct ConstructorMedia: Codable, Equatable, Sendable {
    public let teamLogo: MediaReference
    public let carSide: MediaReference
}

public struct ResultMedia: Codable, Equatable, Sendable {
    public let driver: DriverMedia
    public let constructor: ConstructorMedia
}

public struct SessionResult: Codable, Identifiable, Equatable, Sendable {
    public var media: ResultMedia? = nil
    public var id: String { driverId }
    public var classificationLabel: String {
        switch classification.uppercased() {
        case "CLASSIFIED": "已分类"
        case "DNF": "退赛"
        case "DNS": "未起步"
        case "DSQ": "取消资格"
        case "NC": "未分类"
        default: classification
        }
    }
    public let sessionId: String
    public let position: Int?
    public var gridPosition: Int? = nil
    public let classification: String
    public let driverId: String
    public var driverNumber: String?
    public let driverName: String
    public let constructorId: String
    public let team: String
    public let time: String?
    public let bestLap: String?
    public let q1: String?
    public let q2: String?
    public let q3: String?
    public let raceTime: String?
    public let gap: String?
    public let laps: Int?
    public var lapsLed: Int? = nil
    public let points: Double?
    public let source: String
    public let sourceUpdatedAt: String?
    public let fetchedAt: Date
    public let revision: Int
    public let quality: String
}

public struct DriverStanding: Codable, Identifiable, Equatable, Sendable {
    public var media: DriverMedia? = nil
    public var id: String { driverId }
    public let season: Int
    public let position: Int
    public let driverId: String
    public var driverNumber: String?
    public let driverName: String
    public let constructor: String
    public let constructorIds: [String]
    public let points: Double
    public let wins: Int
    public let source: String
    public let fetchedAt: Date
    public let revision: Int
}

public struct ConstructorStanding: Codable, Identifiable, Equatable, Sendable {
    public var media: ConstructorMedia? = nil
    public var id: String { constructorId }
    public let season: Int
    public let position: Int
    public let constructorId: String
    public let constructorName: String
    public let points: Double
    public let wins: Int
    public let source: String
    public let fetchedAt: Date
    public let revision: Int
}

public struct SeasonResultWeekend: Codable, Identifiable, Sendable {
    public var id: String { meeting.id }
    public let meeting: Meeting
    public let sessions: [String: SeasonResultSession]
    public var fastestLaps: FastestLaps? = nil

    public init(meeting: Meeting, sessions: [String: SeasonResultSession], fastestLaps: FastestLaps? = nil) {
        self.meeting = meeting
        self.sessions = sessions
        self.fastestLaps = fastestLaps
    }

    public struct FastestLaps: Codable, Sendable {
        public let weekend: Record
        public let previous: Record?

        public struct Record: Codable, Sendable {
            public let millis: Int
            public let time: String
            public let driverName: String
            public let team: String
            public let year: Int
        }
    }
}

public struct SeasonResultSession: Codable, Sendable {
    public let rows: [SessionResult]
    public let meta: ResponseMeta
}
