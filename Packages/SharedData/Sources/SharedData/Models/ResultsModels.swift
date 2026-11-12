import Foundation

public struct SessionResult: Codable, Identifiable, Equatable, Sendable {
    public var id: String { driverId }
    public var classificationLabel: String {
        switch classification.uppercased() {
        case "CLASSIFIED": "已分类"
        case "DNF": "退赛"
        case "DNS": "未起步"
        case "DSQ": "取消资格"
        case "NC": "未分类"
        default: classification
        }
    }
    public let sessionId: String
    public let position: Int?
    public let classification: String
    public let driverId: String
    public var driverNumber: String?
    public let driverName: String
    public let constructorId: String
    public let team: String
    public let time: String?
    public let bestLap: String?
    public let q1: String?
    public let q2: String?
    public let q3: String?
    public let raceTime: String?
    public let gap: String?
    public let laps: Int?
    public let points: Double?
    public let source: String
    public let sourceUpdatedAt: String?
    public let fetchedAt: Date
    public let revision: Int
    public let quality: String
}

public struct DriverStanding: Codable, Identifiable, Equatable, Sendable {
    public var id: String { driverId }
    public let season: Int
    public let position: Int
    public let driverId: String
    public var driverNumber: String?
    public let driverName: String
    public let constructor: String
    public let constructorIds: [String]
    public let points: Double
    public let wins: Int
    public let source: String
    public let fetchedAt: Date
    public let revision: Int
}

public struct ConstructorStanding: Codable, Identifiable, Equatable, Sendable {
    public var id: String { constructorId }
    public let season: Int
    public let position: Int
    public let constructorId: String
    public let constructorName: String
    public let points: Double
    public let wins: Int
    public let source: String
    public let fetchedAt: Date
    public let revision: Int
}
