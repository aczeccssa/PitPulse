import Foundation

public struct SeasonAnalysis: Codable, Sendable {
    public let rounds: [AnalysisRound]
    public let warnings: [String]
    public var hasData: Bool { !rounds.isEmpty }

    /// Sprint and race entries share a round; sum them before accumulating.
    /// Stop at missing points so later totals do not silently undercount.
    public var cumulativePointsByRound: [(round: Int, points: Double)] {
        let grouped = Dictionary(grouping: rounds.compactMap { row in row.round.map { ($0, row) } }, by: { $0.0 })
        var total = 0.0
        var result: [(round: Int, points: Double)] = []
        for round in grouped.keys.sorted() {
            let rows = grouped[round]!.map { $0.1 }
            guard rows.allSatisfy({ $0.points != nil }) else { break }
            total += rows.compactMap(\.points).reduce(0, +)
            result.append((round, total))
        }
        return result
    }
}
public struct AnalysisRound: Codable, Sendable {
    public let round: Int?
    public let raceName: String?
    public let date: String?
    public let circuitName: String?
    public let country: String?
    public let sessionType: String?
    public let entries: [AnalysisEntry]
    public var points: Double? {
        guard !entries.isEmpty, entries.allSatisfy({ $0.points != nil }) else { return nil }
        return entries.compactMap(\.points).reduce(0, +)
    }
}
public struct AnalysisEntry: Codable, Sendable {
    public let driverId: String?
    public let driverName: String?
    public let position: Int?
    public let grid: Int?
    public let points: Double?
    public let laps: Int?
    public let status: String?
}
