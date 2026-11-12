import Foundation

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
