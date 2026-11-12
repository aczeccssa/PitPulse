import Foundation

public struct LiveDriver: Codable, Equatable, Sendable {
    public var teamColorHex: String {
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
    public var location: LiveLocation? = nil
    public var telemetry: LiveTelemetry? = nil
    public let number: String
    public let name: String?
    public let team: String?
    public let position: Int?
    public let gap: String?
    public let interval: String?
    public let lapCount: Int?
    public let lastLap: String?
    public let bestLap: String?
    public var sectors: [LiveSector]? = nil
    public var inPit: Bool? = nil
    public var retired: Bool? = nil
    public var classId: String? = nil
    public var className: String? = nil
    public var classPosition: Int? = nil
    public var manufacturer: String? = nil
    public var tireCompound: String? = nil
    public var tireAgeLaps: Int? = nil
    public var energyPercent: Double? = nil

    public init(
        location: LiveLocation? = nil,
        telemetry: LiveTelemetry? = nil,
        number: String,
        name: String?,
        team: String?,
        position: Int?,
        gap: String?,
        interval: String?,
        lapCount: Int?,
        lastLap: String?,
        bestLap: String?,
        sectors: [LiveSector]? = nil,
        inPit: Bool? = nil,
        retired: Bool? = nil,
        classId: String? = nil,
        className: String? = nil,
        classPosition: Int? = nil,
        manufacturer: String? = nil,
        tireCompound: String? = nil,
        tireAgeLaps: Int? = nil,
        energyPercent: Double? = nil
    ) {
        self.location = location
        self.telemetry = telemetry
        self.number = number
        self.name = name
        self.team = team
        self.position = position
        self.gap = gap
        self.interval = interval
        self.lapCount = lapCount
        self.lastLap = lastLap
        self.bestLap = bestLap
        self.sectors = sectors
        self.inPit = inPit
        self.retired = retired
        self.classId = classId
        self.className = className
        self.classPosition = classPosition
        self.manufacturer = manufacturer
        self.tireCompound = tireCompound
        self.tireAgeLaps = tireAgeLaps
        self.energyPercent = energyPercent
    }

    public var classLabel: String? {
        guard let classId, !classId.isEmpty else { return nil }
        let name = (className ?? classId).uppercased()
        return classPosition.map { "\(name) P\($0)" } ?? name
    }

    public var tireShortLabel: String? {
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

    public var tireLabel: String? {
        guard let tireShortLabel else { return nil }
        return tireAgeLaps.map { "\(tireShortLabel) \($0)" } ?? tireShortLabel
    }

    public var energyLabel: String? {
        energyPercent.map { "\(Int($0.rounded()))%" }
    }
}
