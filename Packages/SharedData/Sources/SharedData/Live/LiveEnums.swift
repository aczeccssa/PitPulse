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
