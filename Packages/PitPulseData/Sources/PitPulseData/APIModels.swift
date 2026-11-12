import Foundation

public struct APIEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    public let data: Value
    public let meta: ResponseMeta

    public init(data: Value, meta: ResponseMeta) {
        self.data = data
        self.meta = meta
    }
}

public enum ManualRefreshTarget: String, Codable, Sendable {
    case calendar, results, standings
}

public struct RefreshRequest: Codable, Sendable {
    public let season: Int
    public let target: ManualRefreshTarget
    public let sessionId: String?
}

public enum DataRefreshStatus: String, Codable, Sendable {
    case inProgress, completed, partial, failed, rateLimited
}

public struct DataRefreshEvent: Codable, Equatable, Sendable {
    public let target: ManualRefreshTarget
    public let season: Int
    public let sessionId: String?
    public let status: DataRefreshStatus
    public let updatedAt: String
    public let retryAfter: String?
}

public struct ResponseMeta: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: Int
    public var stale: Bool
    public let quality: DataQuality
    public let source: String?
    public let fetchedAt: Date?
    public let sourceUpdatedAt: Date?
    public var analysisStatus: String? = nil
    public var analysisError: String? = nil
    public var analysisIsLoading: Bool { analysisStatus == "loading" || analysisStatus == "pending" }
    public var analysisCanBeCached: Bool { analysisStatus == nil || analysisStatus == "ready" }

    public init(
        schemaVersion: Int,
        revision: Int,
        stale: Bool,
        quality: DataQuality,
        source: String?,
        fetchedAt: Date?,
        sourceUpdatedAt: Date?,
        analysisStatus: String? = nil,
        analysisError: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.stale = stale
        self.quality = quality
        self.source = source
        self.fetchedAt = fetchedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.analysisStatus = analysisStatus
        self.analysisError = analysisError
    }
}

public enum DataQuality: String, Codable, Sendable {
    case pending
    case partial
    case provisional
    case final
    case stale

    public var displayName: String {
        switch self {
        case .pending: "待同步"
        case .partial: "部分数据"
        case .provisional: "暂定"
        case .final: "最终"
        case .stale: "已过期"
        }
    }
}

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

public struct SessionResult: Codable, Identifiable, Equatable, Sendable {
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
    public let points: Double?
    public let source: String
    public let sourceUpdatedAt: String?
    public let fetchedAt: Date
    public let revision: Int
    public let quality: String
}

public struct DriverStanding: Codable, Identifiable, Equatable, Sendable {
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

public struct HealthResponse: Codable, Equatable, Sendable {
    public let status: String
    public let database: Bool
    public let live: Bool
    public let version: String
}

public enum RFC3339 {
    public static func parse(_ value: String) -> Date? {
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


public struct SessionAnalysis: Codable, Sendable {
    public let laps: [AnalysisLap]
    public let stints: [AnalysisStint]
    public let pit: [AnalysisPit]
    public let positions: [AnalysisPosition]
    public let weather: [AnalysisWeather]
    public let raceControl: [AnalysisEvent]
    public let grid: [AnalysisGrid]
    public let location: [AnalysisLocation]
    public let carData: [AnalysisTelemetry]
    public let warnings: [String]
    public let selectedLap: Int?
    public let driver: AnalysisDriver?
    public var hasData: Bool { !laps.isEmpty || !stints.isEmpty || !pit.isEmpty || !positions.isEmpty || !weather.isEmpty || !raceControl.isEmpty || !location.isEmpty || !carData.isEmpty }
}
public struct AnalysisDriver: Codable, Sendable {
    public let driverNumber: Int?
    public let fullName: String?
    public let teamName: String?
}
public struct AnalysisLap: Codable, Sendable {
    public let lapNumber: Int?
    public let lapDuration: Double?
    public let dateStart: Date?
    public let durationSector1: Double?
    public let durationSector2: Double?
    public let durationSector3: Double?
    public let isPitOutLap: Bool?
    public let i1Speed: Double?
    public let i2Speed: Double?
    public let stSpeed: Double?
    public var sectors: [Double?] { [durationSector1, durationSector2, durationSector3] }
}
public struct AnalysisStint: Codable, Sendable {
    public let stintNumber: Int?
    public let lapStart: Int?
    public let lapEnd: Int?
    public let compound: String?
    public let tyreAgeAtStart: Int?
}
public struct AnalysisPit: Codable, Sendable {
    public let lapNumber: Int?
    public let date: Date?
    public let pitDuration: Double?
    public let laneDuration: Double?
    public let stopDuration: Double?
}
public struct AnalysisPosition: Codable, Sendable {
    public let date: Date?
    public let position: Int?
}
public struct AnalysisWeather: Codable, Sendable {
    public let date: Date?
    public let airTemperature: Double?
    public let trackTemperature: Double?
    public let humidity: Double?
    public let rainfall: Double?
    public let windSpeed: Double?
    public let windDirection: Double?
    public let pressure: Double?
}
public struct AnalysisEvent: Codable, Sendable {
    public let date: Date?
    public let category: String?
    public let flag: String?
    public let message: String?
    public let driverNumber: Int?
    public let lapNumber: Int?
}
public struct AnalysisGrid: Codable, Sendable {
    public let driverNumber: Int?
    public let position: Int?
    public let lapDuration: Double?
}
public struct AnalysisLocation: Codable, Sendable {
    public let date: Date?
    public let x: Double?
    public let y: Double?
    public let z: Double?
}
public struct AnalysisTelemetry: Codable, Sendable {
    public let date: Date?
    public let speed: Double?
    public let throttle: Double?
    public let brake: Double?
    public let rpm: Double?
    public let nGear: Int?
    public let drs: Int?
}
public struct SeasonAnalysis: Codable, Sendable {
    public let rounds: [AnalysisRound]
    public let warnings: [String]
    public var hasData: Bool { !rounds.isEmpty }

    /// Sprint and race entries share a round; sum them before accumulating.
    /// Stop at missing points so later totals do not silently undercount.
    public var cumulativePointsByRound: [(round: Int, points: Double)] {
        let grouped = Dictionary(grouping: rounds.compactMap { row in row.round.map { ($0, row) } }, by: { $0.0 })
        var total = 0.0
        var result: [(round: Int, points: Double)] = []
        for round in grouped.keys.sorted() {
            let rows = grouped[round]!.map { $0.1 }
            guard rows.allSatisfy({ $0.points != nil }) else { break }
            total += rows.compactMap(\.points).reduce(0, +)
            result.append((round, total))
        }
        return result
    }
}
public struct AnalysisRound: Codable, Sendable {
    public let round: Int?
    public let raceName: String?
    public let date: String?
    public let circuitName: String?
    public let country: String?
    public let sessionType: String?
    public let entries: [AnalysisEntry]
    public var points: Double? {
        guard !entries.isEmpty, entries.allSatisfy({ $0.points != nil }) else { return nil }
        return entries.compactMap(\.points).reduce(0, +)
    }
}
public struct AnalysisEntry: Codable, Sendable {
    public let driverId: String?
    public let driverName: String?
    public let position: Int?
    public let grid: Int?
    public let points: Double?
    public let laps: Int?
    public let status: String?
}

public enum AnalysisMath {
    public static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds <= 360000 else { return "—" }
        let milliseconds = Int((seconds * 1000).rounded())
        let whole = milliseconds / 1000
        let tail = String(format: "%02d.%03d", whole % 60, milliseconds % 1000)
        return whole >= 3600 ? "\(whole / 3600):\(String(format: "%02d", whole / 60 % 60)):\(tail)" : "\(whole / 60):\(tail)"
    }
    public static func telemetry(at date: Date?, in rows: [AnalysisTelemetry]) -> AnalysisTelemetry? {
        guard let date else { return nil }
        let closest = rows.filter { $0.date != nil }.min {
            abs($0.date!.timeIntervalSince(date)) < abs($1.date!.timeIntervalSince(date))
        }
        guard let closest, abs(closest.date!.timeIntervalSince(date)) <= 1 else { return nil }
        return closest
    }
}
