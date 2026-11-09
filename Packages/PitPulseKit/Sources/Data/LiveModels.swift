import Foundation

public enum LiveSourceStatus: String, Codable, Sendable {
    case connected
    case stale
    case disconnected
}

public enum LiveSourceMode: String, Codable, Sendable {
    case live
    case replay
}

public enum LiveSeries: String, CaseIterable, Hashable, Identifiable, Sendable {
    case f1
    case wec

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .f1: return "Formula 1"
        case .wec: return "FIA WEC"
        }
    }

    public var shortTitle: String {
        switch self {
        case .f1: return "F1"
        case .wec: return "WEC"
        }
    }
}

public enum LiveTrackCondition: Equatable, Sendable {
    case clear, yellow, fullCourseYellow, safetyCar, safetyCarEnding, red, virtualSafetyCar, virtualSafetyCarEnding, unknown

    public init(_ value: String?) {
        let token = (value ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
        switch token {
        case "1", "allclear", "clear", "green", "greenflag", "chequered", "checkered": self = .clear
        case "2", "yellow", "yellowflag", "yellowflags", "slowzone": self = .yellow
        case "fcy", "fullcourseyellow", "code60": self = .fullCourseYellow
        case "4", "sc", "scdeployed", "safetycar", "safetycardeployed": self = .safetyCar
        case "scinthislap", "scending", "safetycarinthislap", "safetycarending": self = .safetyCarEnding
        case "5", "red", "redflag": self = .red
        case "6", "vsc", "vscdeployed", "virtualsafetycar", "virtualsafetycardeployed": self = .virtualSafetyCar
        case "7", "vscending", "virtualsafetycarending": self = .virtualSafetyCarEnding
        default: self = .unknown
        }
    }

    public var label: String {
        switch self {
        case .clear: return "绿旗 · 赛道畅通"
        case .yellow: return "黄旗 · 注意"
        case .fullCourseYellow: return "FCY · 全场黄旗"
        case .safetyCar: return "SC · 安全车"
        case .safetyCarEnding: return "SC · 本圈退出"
        case .red: return "红旗 · 暂停"
        case .virtualSafetyCar: return "VSC · 虚拟安全车"
        case .virtualSafetyCarEnding: return "VSC · 即将结束"
        case .unknown: return "赛道状态未知"
        }
    }

    public var systemName: String {
        switch self {
        case .clear, .yellow, .red: return "flag.fill"
        case .fullCourseYellow, .safetyCar, .safetyCarEnding: return "flag.fill"
        case .virtualSafetyCar, .virtualSafetyCarEnding: return "flag.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Short code shown instead of the generic car icon during neutralisations.
    public var code: String? {
        switch self {
        case .safetyCar, .safetyCarEnding: return "SC"
        case .fullCourseYellow: return "FCY"
        case .virtualSafetyCar, .virtualSafetyCarEnding: return "VSC"
        default: return nil
        }
    }
}

public struct LiveRaceControlMessage: Codable, Equatable, Sendable {
    public let message: String?
    public let category: String?
    public let flag: String?
    public let id: String?
    public let utc: String?
    public let lap: Int?
    public let driverNumber: String?
    public let sector: Int?
    public let scope: String?

    public func concernsDriver(_ selected: String?) -> Bool {
        guard let selected, !selected.isEmpty, selected.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        if driverNumber == selected { return true }
        return message?.range(of: "\\bCAR\\s+\(selected)\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case message = "Message"
        case category = "Category"
        case flag = "Flag"
        case id, utc, lap, driverNumber, sector, scope
    }
    private enum LegacyKeys: String, CodingKey {
        case id = "Id", utc = "Utc", lap = "Lap", driverNumber = "RacingNumber", sector = "Sector", scope = "Scope"
    }

    public init(from decoder: Decoder) throws {
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else {
            message = nil
            category = nil
            flag = nil
            id = nil; utc = nil; lap = nil; driverNumber = nil; sector = nil; scope = nil
            return
        }
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        message = try? values.decode(String.self, forKey: .message)
        category = try? values.decode(String.self, forKey: .category)
        flag = try? values.decode(String.self, forKey: .flag)
        id = (try? values.decode(String.self, forKey: .id)) ?? (try? legacy.decode(String.self, forKey: .id))
        utc = (try? values.decode(String.self, forKey: .utc)) ?? (try? legacy.decode(String.self, forKey: .utc))
        lap = (try? values.decode(Int.self, forKey: .lap)) ?? (try? legacy.decode(Int.self, forKey: .lap))
        let currentText = try? values.decode(String.self, forKey: .driverNumber)
        let currentNumber = (try? values.decode(Int.self, forKey: .driverNumber)).map(String.init)
        let legacyText = try? legacy.decode(String.self, forKey: .driverNumber)
        let legacyNumber = (try? legacy.decode(Int.self, forKey: .driverNumber)).map(String.init)
        driverNumber = currentText ?? currentNumber ?? legacyText ?? legacyNumber
        sector = (try? values.decode(Int.self, forKey: .sector)) ?? (try? legacy.decode(Int.self, forKey: .sector))
        scope = (try? values.decode(String.self, forKey: .scope)) ?? (try? legacy.decode(String.self, forKey: .scope))
    }
}

public struct LiveSector: Codable, Equatable, Sendable {
    public let value: String?
    public let personalFastest: Bool?
    public let overallFastest: Bool?
    public let segments: [Int?]?
}

public struct LiveLocation: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let utc: String
    public let receivedAt: String?
    public let status: String?
    public let longitude: Double?
    public let latitude: Double?
}

public struct LiveTelemetry: Codable, Equatable, Sendable {
    public let utc: String
    public let receivedAt: String?
    public let rpm: Double?
    public let speed: Double?
    public let gear: Double?
    public let throttle: Double?
    public let brake: Double?
    public let drs: Double?
}

public struct LivePositionDiagnostics: Codable, Equatable, Sendable {
    public let received: Int
    public let decoded: Int
    public let calibrated: Int
}

public struct LiveWeather: Codable, Equatable, Sendable {
    public let utc: String
    public let airTemp: Double?
    public let trackTemp: Double?
    public let humidity: Double?
    public let pressure: Double?
    public let windSpeed: Double?
    public let windDirection: Double?
    public let rainfall: Bool?
}

public struct LiveRadio: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let utc: String
    public let driverNumber: String
}

public enum LiveFreshness {
    public static func age(_ utc: String?, now: Date = Date()) -> TimeInterval? {
        guard let utc, let date = RFC3339.parse(utc) else { return nil }
        return now.timeIntervalSince(date)
    }

    public static func isFresh(_ utc: String?, now: Date = Date(), maximumAge: TimeInterval = 10) -> Bool {
        guard let age = age(utc, now: now) else { return false }
        return age >= -5 && age <= maximumAge
    }
}

public struct LiveDriver: Codable, Equatable, Sendable {
    public var teamColorHex: String {
        switch team?.lowercased() {
        case "mercedes": "#27F4D2"
        case "mclaren": "#FF8000"
        case "ferrari": "#E80020"
        case "red bull racing", "red bull": "#3671C6"
        case "williams": "#64C4FF"
        case "racing bulls", "rb": "#6692FF"
        case "aston martin": "#229971"
        case "alpine": "#FF87BC"
        case "haas f1 team", "haas": "#B6BABD"
        case "audi": "#F50537"
        case "cadillac": "#AAAAAA"
        default: "#94A3B8"
        }
    }
    public var location: LiveLocation? = nil
    public var telemetry: LiveTelemetry? = nil
    public let number: String
    public let name: String?
    public let team: String?
    public let position: Int?
    public let gap: String?
    public let interval: String?
    public let lapCount: Int?
    public let lastLap: String?
    public let bestLap: String?
    public var sectors: [LiveSector]? = nil
    public var inPit: Bool? = nil
    public var retired: Bool? = nil
    public var classId: String? = nil
    public var className: String? = nil
    public var classPosition: Int? = nil
    public var manufacturer: String? = nil
    public var tireCompound: String? = nil
    public var tireAgeLaps: Int? = nil
    public var energyPercent: Double? = nil

    public init(
        location: LiveLocation? = nil,
        telemetry: LiveTelemetry? = nil,
        number: String,
        name: String?,
        team: String?,
        position: Int?,
        gap: String?,
        interval: String?,
        lapCount: Int?,
        lastLap: String?,
        bestLap: String?,
        sectors: [LiveSector]? = nil,
        inPit: Bool? = nil,
        retired: Bool? = nil,
        classId: String? = nil,
        className: String? = nil,
        classPosition: Int? = nil,
        manufacturer: String? = nil,
        tireCompound: String? = nil,
        tireAgeLaps: Int? = nil,
        energyPercent: Double? = nil
    ) {
        self.location = location
        self.telemetry = telemetry
        self.number = number
        self.name = name
        self.team = team
        self.position = position
        self.gap = gap
        self.interval = interval
        self.lapCount = lapCount
        self.lastLap = lastLap
        self.bestLap = bestLap
        self.sectors = sectors
        self.inPit = inPit
        self.retired = retired
        self.classId = classId
        self.className = className
        self.classPosition = classPosition
        self.manufacturer = manufacturer
        self.tireCompound = tireCompound
        self.tireAgeLaps = tireAgeLaps
        self.energyPercent = energyPercent
    }

    public var classLabel: String? {
        guard let classId, !classId.isEmpty else { return nil }
        let name = (className ?? classId).uppercased()
        return classPosition.map { "\(name) P\($0)" } ?? name
    }

    public var tireShortLabel: String? {
        guard let compound = tireCompound?.uppercased(), !compound.isEmpty else { return nil }
        return switch compound {
        case "SOFT": "S"
        case "MEDIUM": "M"
        case "HARD": "H"
        case "INTERMEDIATE", "INTER": "I"
        case "WET": "W"
        default: String(compound.prefix(1))
        }
    }

    public var tireLabel: String? {
        guard let tireShortLabel else { return nil }
        return tireAgeLaps.map { "\(tireShortLabel) \($0)" } ?? tireShortLabel
    }

    public var energyLabel: String? {
        energyPercent.map { "\(Int($0.rounded()))%" }
    }
}

public struct LiveSnapshot: Codable, Equatable, Sendable {
    public var series: String? = nil
    public var circuitKey: String? = nil
    public var circuitName: String? = nil
    public var weather: LiveWeather? = nil
    public var teamRadio: [LiveRadio]? = nil
    public let schemaVersion: Int
    public let stateVersion: Int
    public let sessionId: String?
    public let sessionName: String?
    public var meetingName: String? = nil
    public var countryCode: String? = nil
    public let sourceStatus: LiveSourceStatus
    public let sourceMode: LiveSourceMode
    public let statusReason: String?
    public let sessionType: String?
    public let sessionStatus: String?
    public let trackStatus: String?
    public let lapCount: Int?
    public var totalLaps: Int? = nil
    public let updatedAt: String?
    public let lastTransportAt: String?
    public let drivers: [LiveDriver]
    public let raceControl: [LiveRaceControlMessage]?
    public var positionStatus: String? = nil
    public var positionDiagnostics: LivePositionDiagnostics? = nil
    public var timeRemainingSeconds: Int? = nil
    public var elapsedSeconds: Int? = nil
    public var isTimeBased: Bool? = nil

    public init(
        series: String? = nil,
        circuitKey: String? = nil,
        circuitName: String? = nil,
        weather: LiveWeather? = nil,
        teamRadio: [LiveRadio]? = nil,
        schemaVersion: Int,
        stateVersion: Int,
        sessionId: String?,
        sessionName: String?,
        meetingName: String? = nil,
        countryCode: String? = nil,
        sourceStatus: LiveSourceStatus,
        sourceMode: LiveSourceMode,
        statusReason: String?,
        sessionType: String?,
        sessionStatus: String?,
        trackStatus: String?,
        lapCount: Int?,
        totalLaps: Int? = nil,
        updatedAt: String?,
        lastTransportAt: String?,
        drivers: [LiveDriver],
        raceControl: [LiveRaceControlMessage]?,
        positionStatus: String? = nil,
        positionDiagnostics: LivePositionDiagnostics? = nil,
        timeRemainingSeconds: Int? = nil,
        elapsedSeconds: Int? = nil,
        isTimeBased: Bool? = nil
    ) {
        self.series = series
        self.circuitKey = circuitKey
        self.circuitName = circuitName
        self.weather = weather
        self.teamRadio = teamRadio
        self.schemaVersion = schemaVersion
        self.stateVersion = stateVersion
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.meetingName = meetingName
        self.countryCode = countryCode
        self.sourceStatus = sourceStatus
        self.sourceMode = sourceMode
        self.statusReason = statusReason
        self.sessionType = sessionType
        self.sessionStatus = sessionStatus
        self.trackStatus = trackStatus
        self.lapCount = lapCount
        self.totalLaps = totalLaps
        self.updatedAt = updatedAt
        self.lastTransportAt = lastTransportAt
        self.drivers = drivers
        self.raceControl = raceControl
        self.positionStatus = positionStatus
        self.positionDiagnostics = positionDiagnostics
        self.timeRemainingSeconds = timeRemainingSeconds
        self.elapsedSeconds = elapsedSeconds
        self.isTimeBased = isTimeBased
    }

    public static func disconnected(reason: String = "not_connected") -> LiveSnapshot {
        LiveSnapshot(
            schemaVersion: 1,
            stateVersion: 0,
            sessionId: nil,
            sessionName: nil,
            sourceStatus: .disconnected,
            sourceMode: .live,
            statusReason: reason,
            sessionType: nil,
            sessionStatus: nil,
            trackStatus: nil,
            lapCount: nil,
            updatedAt: nil,
            lastTransportAt: nil,
            drivers: [],
            raceControl: nil
        )
    }

    public var statusLabel: String {
        if sourceMode == .replay {
            switch sourceStatus {
            case .connected: return "回放"
            case .stale: return "回放 · 数据过期"
            case .disconnected: return "回放 · 已断开"
            }
        }
        switch sourceStatus {
        case .connected: return updatedAt == nil ? "等待实时数据" : "实时"
        case .stale: return "数据过期"
        case .disconnected: return "已断开"
        }
    }

    public var trackCondition: LiveTrackCondition {
        sourceStatus == .connected ? LiveTrackCondition(trackStatus) : .unknown
    }

    public var sessionStateLabel: String {
        switch sessionStatus?.lowercased() {
        case "started", "green", "inprogress": return trackCondition == .red ? "红旗暂停" : "进行中"
        case "finished", "finalised", "finalized", "ends": return "已结束"
        case "aborted": return "已中止"
        case "inactive": return "等待开始"
        default: return sessionStatus ?? "状态未知"
        }
    }

    public var lapLabel: String {
        guard let lapCount else { return "— 圈" }
        return totalLaps.map { "L\(lapCount)/\($0)" } ?? "L\(lapCount)"
    }

    public var isWec: Bool { series == "wec" }

    public var remainingLabel: String? {
        guard let timeRemainingSeconds, timeRemainingSeconds > 0 else { return nil }
        let hours = timeRemainingSeconds / 3600
        let minutes = (timeRemainingSeconds % 3600) / 60
        let seconds = timeRemainingSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    public var lastUpdatedLabel: String? {
        guard let updatedAt, let date = RFC3339.parse(updatedAt) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
