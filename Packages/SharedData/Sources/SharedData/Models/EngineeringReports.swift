import Foundation

public struct EngineeringReport<Value: Codable & Sendable>: Codable, Sendable {
    public let data: Value
    public let meta: EngineeringMetadata?
}

public struct EngineeringMetadata: Codable, Sendable {
    public let source: String?
    public let stale: Bool?
    public let unavailable: Bool?
    public let quality: DataQuality?
    public let sections: [String: EngineeringSectionMetadata]?
}

public struct EngineeringSectionMetadata: Codable, Sendable {
    public let source: String?
    public let stale: Bool?
    public let unavailable: Bool?
    public let quality: DataQuality?
    public let coverage: EngineeringCoverage?
}

public struct EngineeringCoverage: Codable, Sendable {
    public let complete: Bool?
}

public struct SeasonFeatures: Codable, Sendable {
    public let powerUnit: Bool
    public let destructors: Bool
}

public struct TechnicalUpdate: Codable, Sendable {
    public let major: Bool?
    public let round: Int?
    public let country: String?
    public let team: String?
    public let component: String?
    public let type: String?
    public let reason: String?
}

public struct PowerUnitReport: Codable, Sendable {
    public let usage: [Usage]
    public let elements: [Element]
    public let penalties: [Penalty]

    public struct Usage: Codable, Sendable {
        public let driverCode: String?
        public let driverName: String?
        public let engineManufacturer: String?
        public let team: String?
        public let used: [String: Int?]?

        public func count(for code: String) -> Int? {
            (used?[code] ?? nil) ?? (used?[code.lowercased()] ?? nil)
        }
    }

    public struct Element: Codable, Sendable {
        public let code: String
        public let name: String
        public let quota: Int?
    }

    public struct Penalty: Codable, Sendable {
        public let driverCode: String?
        public let constructorName: String?
        public let elements: [String]?
        public let driverName: String?
        public let grandPrixName: String?
        public let gridPositions: Int?
        public let startsFromPitLane: Bool?
        public let round: Int?
        public let startingPosition: Int?
        public let allocationDriverName: String?
        public let pitLaneReason: String?
        public let penaltyItems: [Item]?
        public let sourceDocuments: [SourceDocument]?

        public struct Item: Codable, Sendable {
            public let elementCode: String?
            public let elementNumber: Int?
            public let gridPositions: Int?
        }

        public struct SourceDocument: Codable, Sendable {
            public let url: String?
        }
    }
}

public struct DamageReport: Codable, Sendable {
    public let rows: [Incident]
    public let corrections: [Correction]?

    public struct Correction: Codable, Sendable {
        public let round: Int?
        public let diff: String?
        public let quantity: Int?
        public let note: String?
        public let driverSeason: DriverSeason?
        public let components: Component?

        public struct DriverSeason: Codable, Sendable {
            public let driver: Driver?

            public struct Driver: Codable, Sendable {
                public let name: String?
            }
        }
    }

    public struct Incident: Codable, Sendable {
        public let driverName: String?
        public let round: Int?
        public let country: String?
        public let team: String?
        public let components: [Component]

        public var estimate: Double? {
            guard !components.isEmpty,
                  components.allSatisfy({ $0.price != nil && $0.quantity != nil }) else { return nil }
            return components.reduce(0) { $0 + ($1.price ?? 0) * Double($1.quantity ?? 0) }
        }
    }

    public struct Component: Codable, Sendable {
        public let name: String?
        public let price: Double?
        public let quantity: Int?
    }
}

public struct HomeFeatures: Codable, Sendable {
    public let pitStop: [PitStop]?
    public let tech: Count?
    public let pu: Count?
    public let crashes: Damage?

    public struct Count: Codable, Sendable {
        public let total: Int?
    }

    public struct Damage: Codable, Sendable {
        public let seasonTotal: Double?
    }

    public struct PitStop: Codable, Sendable {
        public let time: Double
        public let driverName: String?
        public let country: String?
        public let round: Int?
    }
}
