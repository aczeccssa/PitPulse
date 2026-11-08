import Foundation

struct APIEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    let data: Value
    let meta: ResponseMeta
}

enum ManualRefreshTarget: String, Codable, Sendable {
    case calendar, results, standings
}

struct RefreshRequest: Codable, Sendable {
    let season: Int
    let target: ManualRefreshTarget
    let sessionId: String?
}

enum DataRefreshStatus: String, Codable, Sendable {
    case inProgress, completed, partial, failed, rateLimited
}

struct DataRefreshEvent: Codable, Equatable, Sendable {
    let target: ManualRefreshTarget
    let season: Int
    let sessionId: String?
    let status: DataRefreshStatus
    let updatedAt: String
    let retryAfter: String?
}

struct ResponseMeta: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let revision: Int
    var stale: Bool
    let quality: DataQuality
    let source: String?
    let fetchedAt: Date?
    let sourceUpdatedAt: Date?
    var analysisStatus: String? = nil
    var analysisError: String? = nil
    var analysisIsLoading: Bool { analysisStatus == "loading" || analysisStatus == "pending" }
    var analysisCanBeCached: Bool { analysisStatus == nil || analysisStatus == "ready" }
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

struct CircuitLocation: Codable, Equatable, Sendable {
    let id: String?
    let name: String?
    let latitude: Double
    let longitude: Double
}

struct Meeting: Codable, Identifiable, Equatable, Sendable {
    var circuit: CircuitLocation? = nil
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
    var classificationLabel: String {
        switch classification.uppercased() {
        case "CLASSIFIED": "已分类"
        case "DNF": "退赛"
        case "DNS": "未起步"
        case "DSQ": "取消资格"
        case "NC": "未分类"
        default: classification
        }
    }
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


struct SessionAnalysis: Codable, Sendable {
    let laps: [AnalysisLap]
    let stints: [AnalysisStint]
    let pit: [AnalysisPit]
    let positions: [AnalysisPosition]
    let weather: [AnalysisWeather]
    let raceControl: [AnalysisEvent]
    let grid: [AnalysisGrid]
    let location: [AnalysisLocation]
    let carData: [AnalysisTelemetry]
    let warnings: [String]
    let selectedLap: Int?
    let driver: AnalysisDriver?
    var hasData: Bool { !laps.isEmpty || !stints.isEmpty || !pit.isEmpty || !positions.isEmpty || !weather.isEmpty || !raceControl.isEmpty || !location.isEmpty || !carData.isEmpty }
}
struct AnalysisDriver: Codable, Sendable {
    let driverNumber: Int?
    let fullName: String?
    let teamName: String?
}
struct AnalysisLap: Codable, Sendable {
    let lapNumber: Int?
    let lapDuration: Double?
    let dateStart: Date?
    let durationSector1: Double?
    let durationSector2: Double?
    let durationSector3: Double?
    let isPitOutLap: Bool?
    let i1Speed: Double?
    let i2Speed: Double?
    let stSpeed: Double?
    var sectors: [Double?] { [durationSector1, durationSector2, durationSector3] }
}
struct AnalysisStint: Codable, Sendable {
    let stintNumber: Int?
    let lapStart: Int?
    let lapEnd: Int?
    let compound: String?
    let tyreAgeAtStart: Int?
}
struct AnalysisPit: Codable, Sendable {
    let lapNumber: Int?
    let date: Date?
    let pitDuration: Double?
    let laneDuration: Double?
    let stopDuration: Double?
}
struct AnalysisPosition: Codable, Sendable {
    let date: Date?
    let position: Int?
}
struct AnalysisWeather: Codable, Sendable {
    let date: Date?
    let airTemperature: Double?
    let trackTemperature: Double?
    let humidity: Double?
    let rainfall: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let pressure: Double?
}
struct AnalysisEvent: Codable, Sendable {
    let date: Date?
    let category: String?
    let flag: String?
    let message: String?
    let driverNumber: Int?
    let lapNumber: Int?
}
struct AnalysisGrid: Codable, Sendable {
    let driverNumber: Int?
    let position: Int?
    let lapDuration: Double?
}
struct AnalysisLocation: Codable, Sendable {
    let date: Date?
    let x: Double?
    let y: Double?
    let z: Double?
}
struct AnalysisTelemetry: Codable, Sendable {
    let date: Date?
    let speed: Double?
    let throttle: Double?
    let brake: Double?
    let rpm: Double?
    let nGear: Int?
    let drs: Int?
}
struct SeasonAnalysis: Codable, Sendable {
    let rounds: [AnalysisRound]
    let warnings: [String]
    var hasData: Bool { !rounds.isEmpty }
}
struct AnalysisRound: Codable, Sendable {
    let round: Int?
    let raceName: String?
    let date: String?
    let circuitName: String?
    let country: String?
    let sessionType: String?
    let entries: [AnalysisEntry]
    var points: Double? {
        guard !entries.isEmpty, entries.allSatisfy({ $0.points != nil }) else { return nil }
        return entries.compactMap(\.points).reduce(0, +)
    }
}
struct AnalysisEntry: Codable, Sendable {
    let driverId: String?
    let driverName: String?
    let position: Int?
    let grid: Int?
    let points: Double?
    let laps: Int?
    let status: String?
}

enum AnalysisMath {
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds <= 360000 else { return "—" }
        let milliseconds = Int((seconds * 1000).rounded())
        let whole = milliseconds / 1000
        let tail = String(format: "%02d.%03d", whole % 60, milliseconds % 1000)
        return whole >= 3600 ? "\(whole / 3600):\(String(format: "%02d", whole / 60 % 60)):\(tail)" : "\(whole / 60):\(tail)"
    }
    static func telemetry(at date: Date?, in rows: [AnalysisTelemetry]) -> AnalysisTelemetry? {
        guard let date else { return nil }
        let closest = rows.filter { $0.date != nil }.min {
            abs($0.date!.timeIntervalSince(date)) < abs($1.date!.timeIntervalSince(date))
        }
        guard let closest, abs(closest.date!.timeIntervalSince(date)) <= 1 else { return nil }
        return closest
    }
}
