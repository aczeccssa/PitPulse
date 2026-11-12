import Foundation

public struct LiveRaceControlMessage: Codable, Equatable, Sendable {
    public let message: String?
    public let category: String?
    public let flag: String?
    public let id: String?
    public let utc: String?
    public let lap: Int?
    public let driverNumber: String?
    public let sector: Int?
    public let scope: String?

    public func concernsDriver(_ selected: String?) -> Bool {
        guard let selected, !selected.isEmpty, selected.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        if driverNumber == selected { return true }
        return message?.range(of: "\\bCAR\\s+\(selected)\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case message = "Message"
        case category = "Category"
        case flag = "Flag"
        case id, utc, lap, driverNumber, sector, scope
    }
    private enum LegacyKeys: String, CodingKey {
        case id = "Id", utc = "Utc", lap = "Lap", driverNumber = "RacingNumber", sector = "Sector", scope = "Scope"
    }

    public init(from decoder: Decoder) throws {
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else {
            message = nil
            category = nil
            flag = nil
            id = nil; utc = nil; lap = nil; driverNumber = nil; sector = nil; scope = nil
            return
        }
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        message = try? values.decode(String.self, forKey: .message)
        category = try? values.decode(String.self, forKey: .category)
        flag = try? values.decode(String.self, forKey: .flag)
        id = (try? values.decode(String.self, forKey: .id)) ?? (try? legacy.decode(String.self, forKey: .id))
        utc = (try? values.decode(String.self, forKey: .utc)) ?? (try? legacy.decode(String.self, forKey: .utc))
        lap = (try? values.decode(Int.self, forKey: .lap)) ?? (try? legacy.decode(Int.self, forKey: .lap))
        let currentText = try? values.decode(String.self, forKey: .driverNumber)
        let currentNumber = (try? values.decode(Int.self, forKey: .driverNumber)).map(String.init)
        let legacyText = try? legacy.decode(String.self, forKey: .driverNumber)
        let legacyNumber = (try? legacy.decode(Int.self, forKey: .driverNumber)).map(String.init)
        driverNumber = currentText ?? currentNumber ?? legacyText ?? legacyNumber
        sector = (try? values.decode(Int.self, forKey: .sector)) ?? (try? legacy.decode(Int.self, forKey: .sector))
        scope = (try? values.decode(String.self, forKey: .scope)) ?? (try? legacy.decode(String.self, forKey: .scope))
    }
}
