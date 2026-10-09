import Foundation

struct APIEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    let data: Value
    let meta: ResponseMeta
}

struct ResponseMeta: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let revision: Int
    let stale: Bool
    let quality: DataQuality
    let source: String?
    let fetchedAt: Date?
    let sourceUpdatedAt: Date?
}

enum DataQuality: String, Codable, Sendable {
    case pending
    case partial
    case provisional
    case final
    case stale

    var displayName: String {
        switch self {
        case .pending: "待同步"
        case .partial: "部分数据"
        case .provisional: "暂定"
        case .final: "最终"
        case .stale: "已过期"
        }
    }
}

struct Meeting: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let season: Int
    let round: Int?
    let name: String
    let country: String
    let countryCode: String?
    let location: String
    let startDate: Date
    let endDate: Date
    let status: MeetingStatus
    let sessions: [Session]
    let source: String?
    let fetchedAt: Date?
    let sourceUpdatedAt: Date?
    let revision: Int?

    var nextScheduledSession: Session? {
        sessions
            .filter { $0.status == .scheduled }
            .sorted { $0.startTime < $1.startTime }
            .first
    }
}

struct SessionResult: Codable, Identifiable, Equatable, Sendable {
    var id: String { driverId }
    let sessionId: String
    let position: Int?
    let classification: String
    let driverId: String
    let driverName: String
    let constructorId: String
    let team: String
    let time: String?
    let bestLap: String?
    let q1: String?
    let q2: String?
    let q3: String?
    let raceTime: String?
    let gap: String?
    let laps: Int?
    let points: Double?
    let source: String
    let sourceUpdatedAt: String?
    let fetchedAt: Date
    let revision: Int
    let quality: String
}

struct DriverStanding: Codable, Identifiable, Equatable, Sendable {
    var id: String { driverId }
    let season: Int
    let position: Int
    let driverId: String
    let driverName: String
    let constructor: String
    let constructorIds: [String]
    let points: Double
    let wins: Int
    let source: String
    let fetchedAt: Date
    let revision: Int
}

struct ConstructorStanding: Codable, Identifiable, Equatable, Sendable {
    var id: String { constructorId }
    let season: Int
    let position: Int
    let constructorId: String
    let constructorName: String
    let points: Double
    let wins: Int
    let source: String
    let fetchedAt: Date
    let revision: Int
}

enum MeetingStatus: String, Codable, Sendable {
    case scheduled
    case postponed
    case cancelled

    var displayName: String {
        switch self {
        case .scheduled: "计划中"
        case .postponed: "延期"
        case .cancelled: "取消"
        }
    }
}

struct Session: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let meetingId: String
    let sessionType: SessionType
    let startTime: Date
    let endTime: Date?
    let status: SessionStatus
    let jolpicaSessionId: String?
    let openf1SessionKey: Int?
}

enum SessionType: String, Codable, Sendable {
    case fp1
    case fp2
    case fp3
    case sprintQualifying
    case sprint
    case qualifying
    case race

    var displayName: String {
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

enum SessionStatus: String, Codable, Sendable {
    case scheduled
    case live
    case finished
    case postponed
    case cancelled

    var displayName: String {
        switch self {
        case .scheduled: "计划中"
        case .live: "进行中"
        case .finished: "结束"
        case .postponed: "延期"
        case .cancelled: "取消"
        }
    }
}

struct HealthResponse: Codable, Equatable, Sendable {
    let status: String
    let database: Bool
    let live: Bool
    let version: String
}

enum RFC3339 {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
