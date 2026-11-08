import Foundation

enum LiveSourceStatus: String, Codable, Sendable {
    case connected
    case stale
    case disconnected
}

enum LiveSourceMode: String, Codable, Sendable {
    case live
    case replay
}

enum LiveSeries: String, CaseIterable, Hashable, Identifiable, Sendable {
    case f1
    case wec

    var id: String { rawValue }

    var title: String {
        switch self {
        case .f1: return "Formula 1"
        case .wec: return "FIA WEC"
        }
    }

    var shortTitle: String {
        switch self {
        case .f1: return "F1"
        case .wec: return "WEC"
        }
    }
}

enum LiveTrackCondition: Equatable, Sendable {
    case clear, yellow, fullCourseYellow, safetyCar, safetyCarEnding, red, virtualSafetyCar, virtualSafetyCarEnding, unknown

    init(_ value: String?) {
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

    var label: String {
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

    var systemName: String {
        switch self {
        case .clear, .yellow, .red: return "flag.fill"
        case .fullCourseYellow, .safetyCar, .safetyCarEnding: return "flag.fill"
        case .virtualSafetyCar, .virtualSafetyCarEnding: return "flag.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Short code shown instead of the generic car icon during neutralisations.
    var code: String? {
        switch self {
        case .safetyCar, .safetyCarEnding: return "SC"
        case .fullCourseYellow: return "FCY"
        case .virtualSafetyCar, .virtualSafetyCarEnding: return "VSC"
        default: return nil
        }
    }
}

struct LiveRaceControlMessage: Codable, Equatable, Sendable {
    let message: String?
    let category: String?
    let flag: String?
    let id: String?
    let utc: String?
    let lap: Int?
    let driverNumber: String?
    let sector: Int?
    let scope: String?

    func concernsDriver(_ selected: String?) -> Bool {
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

    init(from decoder: Decoder) throws {
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

struct LiveSector: Codable, Equatable, Sendable {
    let value: String?
    let personalFastest: Bool?
    let overallFastest: Bool?
    let segments: [Int?]?
}

struct LiveLocation: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let utc: String
    let receivedAt: String?
    let status: String?
    let longitude: Double?
    let latitude: Double?
}

struct LiveTelemetry: Codable, Equatable, Sendable {
    let utc: String
    let receivedAt: String?
    let rpm: Double?
    let speed: Double?
    let gear: Double?
    let throttle: Double?
    let brake: Double?
    let drs: Double?
}

struct LivePositionDiagnostics: Codable, Equatable, Sendable {
    let received: Int
    let decoded: Int
    let calibrated: Int
}

struct LiveWeather: Codable, Equatable, Sendable {
    let utc: String
    let airTemp: Double?
    let trackTemp: Double?
    let humidity: Double?
    let pressure: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let rainfall: Bool?
}

struct LiveRadio: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let utc: String
    let driverNumber: String
}

enum LiveFreshness {
    static func age(_ utc: String?, now: Date = Date()) -> TimeInterval? {
        guard let utc, let date = RFC3339.parse(utc) else { return nil }
        return now.timeIntervalSince(date)
    }

    static func isFresh(_ utc: String?, now: Date = Date(), maximumAge: TimeInterval = 10) -> Bool {
        guard let age = age(utc, now: now) else { return false }
        return age >= -5 && age <= maximumAge
    }
}

struct LiveDriver: Codable, Equatable, Sendable {
    var teamColorHex: String {
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
    var location: LiveLocation? = nil
    var telemetry: LiveTelemetry? = nil
    let number: String
    let name: String?
    let team: String?
    let position: Int?
    let gap: String?
    let interval: String?
    let lapCount: Int?
    let lastLap: String?
    let bestLap: String?
    var sectors: [LiveSector]? = nil
    var inPit: Bool? = nil
    var retired: Bool? = nil
    var classId: String? = nil
    var className: String? = nil
    var classPosition: Int? = nil
    var manufacturer: String? = nil
    var tireCompound: String? = nil
    var tireAgeLaps: Int? = nil
    var energyPercent: Double? = nil

    var classLabel: String? {
        guard let classId, !classId.isEmpty else { return nil }
        let name = (className ?? classId).uppercased()
        return classPosition.map { "\(name) P\($0)" } ?? name
    }

    var tireShortLabel: String? {
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

    var tireLabel: String? {
        guard let tireShortLabel else { return nil }
        return tireAgeLaps.map { "\(tireShortLabel) \($0)" } ?? tireShortLabel
    }

    var energyLabel: String? {
        energyPercent.map { "\(Int($0.rounded()))%" }
    }
}

struct LiveSnapshot: Codable, Equatable, Sendable {
    var series: String? = nil
    var circuitKey: String? = nil
    var circuitName: String? = nil
    var weather: LiveWeather? = nil
    var teamRadio: [LiveRadio]? = nil
    let schemaVersion: Int
    let stateVersion: Int
    let sessionId: String?
    let sessionName: String?
    var meetingName: String? = nil
    var countryCode: String? = nil
    let sourceStatus: LiveSourceStatus
    let sourceMode: LiveSourceMode
    let statusReason: String?
    let sessionType: String?
    let sessionStatus: String?
    let trackStatus: String?
    let lapCount: Int?
    var totalLaps: Int? = nil
    let updatedAt: String?
    let lastTransportAt: String?
    let drivers: [LiveDriver]
    let raceControl: [LiveRaceControlMessage]?
    var positionStatus: String? = nil
    var positionDiagnostics: LivePositionDiagnostics? = nil
    var timeRemainingSeconds: Int? = nil
    var elapsedSeconds: Int? = nil
    var isTimeBased: Bool? = nil

    static func disconnected(reason: String = "not_connected") -> LiveSnapshot {
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

    var statusLabel: String {
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

    var trackCondition: LiveTrackCondition {
        sourceStatus == .connected ? LiveTrackCondition(trackStatus) : .unknown
    }

    var sessionStateLabel: String {
        switch sessionStatus?.lowercased() {
        case "started", "green", "inprogress": return trackCondition == .red ? "红旗暂停" : "进行中"
        case "finished", "finalised", "finalized", "ends": return "已结束"
        case "aborted": return "已中止"
        case "inactive": return "等待开始"
        default: return sessionStatus ?? "状态未知"
        }
    }

    var lapLabel: String {
        guard let lapCount else { return "— 圈" }
        return totalLaps.map { "L\(lapCount)/\($0)" } ?? "L\(lapCount)"
    }

    var isWec: Bool { series == "wec" }

    var remainingLabel: String? {
        guard let timeRemainingSeconds, timeRemainingSeconds > 0 else { return nil }
        let hours = timeRemainingSeconds / 3600
        let minutes = (timeRemainingSeconds % 3600) / 60
        let seconds = timeRemainingSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    var lastUpdatedLabel: String? {
        guard let updatedAt, let date = RFC3339.parse(updatedAt) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
