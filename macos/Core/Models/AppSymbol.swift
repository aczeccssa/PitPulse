import AppKit
import SharedData

enum AppSymbol: String, CaseIterable, Sendable {
    case menuBar
    case calendar
    case clock
    case timer
    case results
    case standings
    case reminder
    case settings
    case refresh
    case cache
    case offline
    case warning
    case favorite
    case favoriteFilled
    case globe
    case liveDisconnected

    var systemName: String {
        switch self {
        case .menuBar: "flag.checkered"
        case .calendar: "calendar"
        case .clock: "clock"
        case .timer: "timer"
        case .results: "list.number"
        case .standings: "trophy"
        case .reminder: "bell"
        case .settings: "gearshape"
        case .refresh: "arrow.clockwise"
        case .cache: "externaldrive"
        case .offline: "wifi.slash"
        case .warning: "exclamationmark.triangle"
        case .favorite: "star"
        case .favoriteFilled: "star.fill"
        case .globe: "globe"
        case .liveDisconnected: "antenna.radiowaves.left.and.right.slash"
        }
    }

    var fallbackSystemName: String {
        switch self {
        case .menuBar: "flag"
        case .results: "list.bullet"
        case .standings: "list.bullet"
        case .refresh: "arrow.triangle.2.circlepath"
        case .cache: "internaldrive"
        case .offline: "wifi"
        case .warning: "exclamationmark.triangle"
        case .favoriteFilled: "star"
        case .liveDisconnected: "antenna.radiowaves.left.and.right"
        default: systemName
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .menuBar: "PitPulse"
        case .calendar: "赛历"
        case .clock: "Session 时间"
        case .timer: "倒计时"
        case .results: "成绩"
        case .standings: "积分榜"
        case .reminder: "提醒"
        case .settings: "设置"
        case .refresh: "刷新"
        case .cache: "缓存"
        case .offline: "离线"
        case .warning: "数据异常"
        case .favorite: "关注"
        case .favoriteFilled: "已关注"
        case .globe: "国家未知"
        case .liveDisconnected: "Live 未连接"
        }
    }

    @MainActor
    func resolvedSystemName() -> String {
        if NSImage(systemSymbolName: systemName, accessibilityDescription: accessibilityLabel) != nil {
            return systemName
        }
        return fallbackSystemName
    }
}

enum StatusSymbolResolver {
    static func symbol(for status: AppConnectionStatus) -> AppSymbol {
        switch status {
        case .idle, .loading, .connected: .menuBar
        case .offline, .requiresToken: .offline
        case .stale: .cache
        case .failed: .warning
        }
    }
}
