import AppKit
import SwiftUI
import SharedData

struct PitPulseForecastEnvelope: Decodable {
    let data: PitPulseForecast
    let meta: PitPulseForecastMeta
}

struct PitPulseForecastMeta: Decodable {
    let stale: Bool
}

struct PitPulseForecast: Decodable {
    let status: String
    let hours: [PitPulseForecastHour]

    var statusText: String {
        switch status {
        case "available": "比赛日预报"
        case "historical": "历史实测天气 · 已归档"
        case "history_pending", "past_event": "历史天气尚未归档"
        default: "尚无比赛日期预报"
        }
    }
}

struct PitPulseForecastHour: Decodable {
    let utc: String
    var time: Double { RFC3339.parse(utc)?.timeIntervalSince1970 ?? .greatestFiniteMagnitude }
    let airTemp: Double?
    let precipitationProbability: Double?
    let precipitation: Double?
    let windSpeed: Double?
    let weatherCode: Int?
    let sessionId: String?
    let trackTemp: Double?
    let rainfall: Double?

    var rainText: String {
        if let rainfall { return rainfall > 0 ? "有雨" : "无雨" }
        return precipitationProbability.map { String(format: "%.0f%%", $0) } ?? "未提供"
    }

    var conditionText: String {
        guard let weatherCode else { return rainfall == nil ? "预报" : "实测" }
        switch weatherCode {
        case 0: return "晴"
        case 1...3: return "多云"
        case 45, 48: return "雾"
        case 51...57: return "毛毛雨"
        case 61...67: return "降雨"
        case 71...77: return "降雪"
        case 80...82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95...99: return "雷暴"
        default: return "预报"
        }
    }
}

enum MeetingForecast {
    static func load(meetingID: String, model: AppModel) async throws -> (forecast: PitPulseForecast, stale: Bool) {
        let data = try await model.mapData(path: "/api/v1/meetings/\(meetingID)/weather")
        let envelope = try JSONDecoder().decode(PitPulseForecastEnvelope.self, from: data)
        return (envelope.data, envelope.meta.stale)
    }
}
