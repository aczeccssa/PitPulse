import Foundation

public struct CircuitLocation: Codable, Equatable, Sendable {
    public let id: String?
    public let name: String?
    public let latitude: Double
    public let longitude: Double
}

public struct Meeting: Codable, Identifiable, Equatable, Sendable {
    public var circuit: CircuitLocation? = nil
    public let id: String
    public let season: Int
    public let round: Int?
    public let name: String
    public let country: String
    public let countryCode: String?
    public let location: String
    public let startDate: Date
    public let endDate: Date
    public let status: MeetingStatus
    public let sessions: [Session]
    public let source: String?
    public let fetchedAt: Date?
    public let sourceUpdatedAt: Date?
    public let revision: Int?

    public var nextScheduledSession: Session? {
        sessions
            .filter { $0.status == .scheduled }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    public init(
        circuit: CircuitLocation? = nil,
        id: String,
        season: Int,
        round: Int?,
        name: String,
        country: String,
        countryCode: String?,
        location: String,
        startDate: Date,
        endDate: Date,
        status: MeetingStatus,
        sessions: [Session],
        source: String?,
        fetchedAt: Date?,
        sourceUpdatedAt: Date?,
        revision: Int?
    ) {
        self.circuit = circuit
        self.id = id
        self.season = season
        self.round = round
        self.name = name
        self.country = country
        self.countryCode = countryCode
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.sessions = sessions
        self.source = source
        self.fetchedAt = fetchedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.revision = revision
    }
}

public enum MeetingStatus: String, Codable, Sendable {
    case scheduled
    case postponed
    case cancelled

    public var displayName: String {
        switch self {
        case .scheduled: "计划中"
        case .postponed: "延期"
        case .cancelled: "取消"
        }
    }
}

public struct Session: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let meetingId: String
    public let sessionType: SessionType
    public let startTime: Date
    public let endTime: Date?
    public let status: SessionStatus
    public let jolpicaSessionId: String?
    public let openf1SessionKey: Int?

    public init(
        id: String,
        meetingId: String,
        sessionType: SessionType,
        startTime: Date,
        endTime: Date?,
        status: SessionStatus,
        jolpicaSessionId: String?,
        openf1SessionKey: Int?
    ) {
        self.id = id
        self.meetingId = meetingId
        self.sessionType = sessionType
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.jolpicaSessionId = jolpicaSessionId
        self.openf1SessionKey = openf1SessionKey
    }
}

public enum SessionType: String, Codable, Sendable {
    case fp1
    case fp2
    case fp3
    case sprintQualifying
    case sprint
    case qualifying
    case race

    public var displayName: String {
        switch self {
        case .fp1: "FP1"
        case .fp2: "FP2"
        case .fp3: "FP3"
        case .sprintQualifying: "Sprint 排位"
        case .sprint: "Sprint"
        case .qualifying: "排位赛"
        case .race: "正赛"
        }
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case scheduled
    case live
    case finished
    case postponed
    case cancelled

    public var displayName: String {
        switch self {
        case .scheduled: "计划中"
        case .live: "进行中"
        case .finished: "结束"
        case .postponed: "延期"
        case .cancelled: "取消"
        }
    }
}
