import Foundation

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
