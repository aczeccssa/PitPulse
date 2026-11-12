import Foundation

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
