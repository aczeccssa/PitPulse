import AppKit
import SwiftUI
import SharedData

struct ForecastEnvelope: Decodable { let data: ForecastData; let meta: ForecastMeta }
struct ForecastMeta: Decodable { let stale: Bool }
struct ForecastData: Decodable { let status: String; let hours: [ForecastHour] }
struct ForecastHour: Decodable {
    let utc: String
    var time: Double { RFC3339.parse(utc)?.timeIntervalSince1970 ?? .greatestFiniteMagnitude }
    let temperature: Double?
    let probability: Double?
    enum CodingKeys: String, CodingKey { case utc, temperature = "airTemp", probability = "precipitationProbability" }
}
