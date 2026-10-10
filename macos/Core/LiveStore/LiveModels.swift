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

enum LiveTrackCondition: Equatable, Sendable {
    case clear, yellow, safetyCar, safetyCarEnding, red, virtualSafetyCar, virtualSafetyCarEnding, unknown

    init(_ value: String?) {
        let token = (value ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
        switch token {
        case "1", "allclear", "clear", "green", "greenflag": self = .clear
        case "2", "yellow", "yellowflag", "yellowflags": self = .yellow
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
        case .safetyCar, .safetyCarEnding: return "car.side.fill"
        case .virtualSafetyCar, .virtualSafetyCarEnding: return "car.side"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct LiveRaceControlMessage: Codable, Equatable, Sendable {
    let message: String?
    let category: String?
    let flag: String?

    private enum CodingKeys: String, CodingKey {
        case message = "Message"
        case category = "Category"
        case flag = "Flag"
    }

    init(from decoder: Decoder) throws {
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else {
            message = nil
            category = nil
            flag = nil
            return
        }
        message = try? values.decode(String.self, forKey: .message)
        category = try? values.decode(String.self, forKey: .category)
        flag = try? values.decode(String.self, forKey: .flag)
    }
}

struct LiveSector: Codable, Equatable, Sendable {
    let value: String?
    let personalFastest: Bool?
    let overallFastest: Bool?
    let segments: [Int?]?
}

struct LiveDriver: Codable, Equatable, Sendable {
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
}

struct LiveSnapshot: Codable, Equatable, Sendable {
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

    var lastUpdatedLabel: String? {
        guard let updatedAt, let date = RFC3339.parse(updatedAt) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
