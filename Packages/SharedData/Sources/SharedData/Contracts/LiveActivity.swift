import Foundation

#if os(iOS)
import ActivityKit

/// The cross-process contract between the iOS app (which owns the live stream)
/// and the Live Activity / Dynamic Island extension (which renders it).
public struct PitPulseActivityAttributes: ActivityAttributes {
    public struct Driver: Codable, Hashable, Sendable {
        public var name: String
        public var position: Int?
        public var asset: String?
        public var gap: String?
        public var interval: String?
        public var speed: Int?
        public var tire: String?
        public var lastLap: String?
        public var positionChange: Int?
        public var sectors: [Sector]
        public init(name: String, position: Int? = nil, asset: String? = nil, gap: String? = nil, interval: String? = nil, speed: Int? = nil, tire: String? = nil, lastLap: String? = nil, sectors: [Sector] = [], positionChange: Int? = nil) {
            self.name = name; self.position = position; self.asset = asset; self.gap = gap
            self.interval = interval; self.speed = speed; self.tire = tire; self.lastLap = lastLap; self.sectors = sectors; self.positionChange = positionChange
        }
    }
    public struct Sector: Codable, Hashable, Sendable {
        public var time: String?
        public var segments: [Int?]
        public var personalFastest: Bool?
        public var overallFastest: Bool?
        public init(time: String? = nil, segments: [Int?] = [], personalFastest: Bool? = nil, overallFastest: Bool? = nil) {
            self.time = time; self.segments = segments
            self.personalFastest = personalFastest; self.overallFastest = overallFastest
        }
    }
    public struct Weather: Codable, Hashable, Sendable {
        public var rainfall: Bool?
        public var airTemperature: Double?
        public var trackTemperature: Double?
        public var visibilityMeters: Int?
        public init(rainfall: Bool? = nil, airTemperature: Double? = nil, trackTemperature: Double? = nil, visibilityMeters: Int? = nil) {
            self.rainfall = rainfall; self.airTemperature = airTemperature
            self.trackTemperature = trackTemperature; self.visibilityMeters = visibilityMeters
        }
    }
    public struct ContentState: Codable, Hashable, Sendable {
        public var sessionName: String
        public var meetingName: String
        public var statusLabel: String
        public var lapLabel: String
        public var leaderName: String?
        public var leaderGap: String?
        public var challengerName: String?
        public var challengerGap: String?
        public var leaderAsset: String?
        public var challengerAsset: String?
        public var trackLabel: String?
        public var driverCount: Int
        public var isStale: Bool
        public var updatedLabel: String?
        public var presentation: String?
        public var favoriteName: String?
        public var favoritePosition: Int?
        public var favoriteGap: String?
        public var favoriteGapLabel: String?
        public var favoriteAsset: String?
        public var podium: [Driver]?
        public var battleDrivers: [Driver]?
        public var trackedDriver: Driver?
        public var battleGap: String?
        public var weather: Weather?
        public var positionDrivers: [Driver]?
        public var positionFocus: String?
        public var positionWindowStart: Int?

        public init(
            sessionName: String,
            meetingName: String,
            statusLabel: String,
            lapLabel: String,
            leaderName: String? = nil,
            leaderGap: String? = nil,
            challengerName: String? = nil,
            challengerGap: String? = nil,
            leaderAsset: String? = nil,
            challengerAsset: String? = nil,
            trackLabel: String? = nil,
            driverCount: Int = 0,
            isStale: Bool = false,
            updatedLabel: String? = nil,
            presentation: String? = nil,
            favoriteName: String? = nil,
            favoritePosition: Int? = nil,
            favoriteGap: String? = nil,
            favoriteGapLabel: String? = nil,
            favoriteAsset: String? = nil,
            podium: [Driver]? = nil,
            battleDrivers: [Driver]? = nil,
            trackedDriver: Driver? = nil,
            battleGap: String? = nil,
            weather: Weather? = nil,
            positionDrivers: [Driver]? = nil,
            positionFocus: String? = nil,
            positionWindowStart: Int? = nil
        ) {
            self.sessionName = sessionName
            self.meetingName = meetingName
            self.statusLabel = statusLabel
            self.lapLabel = lapLabel
            self.leaderName = leaderName
            self.leaderGap = leaderGap
            self.challengerName = challengerName
            self.challengerGap = challengerGap
            self.leaderAsset = leaderAsset
            self.challengerAsset = challengerAsset
            self.trackLabel = trackLabel
            self.driverCount = driverCount
            self.isStale = isStale
            self.updatedLabel = updatedLabel
            self.presentation = presentation
            self.favoriteName = favoriteName
            self.favoritePosition = favoritePosition
            self.favoriteGap = favoriteGap
            self.favoriteGapLabel = favoriteGapLabel
            self.favoriteAsset = favoriteAsset
            self.podium = podium; self.battleDrivers = battleDrivers
            self.trackedDriver = trackedDriver; self.battleGap = battleGap
            self.weather = weather
            self.positionDrivers = positionDrivers; self.positionFocus = positionFocus
            self.positionWindowStart = positionWindowStart
        }
    }

    public var seriesTitle: String

    public init(seriesTitle: String) {
        self.seriesTitle = seriesTitle
    }
}
#endif

#if os(iOS)
import SwiftUI

public extension PitPulseActivityAttributes.ContentState {
    var lapProgress: Double? {
        let values = lapLabel.replacingOccurrences(of: "L", with: "").split(separator: "/")
        guard values.count == 2, let current = Double(values[0]), let total = Double(values[1]),
              current.isFinite, total.isFinite, current >= 0, total > 0, current <= total else { return nil }
        return current / total
    }

    var compactLeadingText: String {
        if presentation == IslandContentMode.positionChanges.rawValue { return "P1 · " + (leaderName.map(MotorsportAssetName.abbreviation) ?? "—") }
        if presentation == IslandContentMode.favorite.rawValue || (presentation == IslandContentMode.battle.rawValue && battleDrivers?.count == 1) {
            return (presentation == IslandContentMode.battle.rawValue ? battleDrivers?.first?.name : trackedDriver?.name ?? favoriteName).map(MotorsportAssetName.abbreviation) ?? "车手"
        }
        if presentation == IslandContentMode.battle.rawValue {
            return battleDrivers.map { $0.map { $0.position.map { "P\($0)" } ?? "—" }.joined(separator: "·") } ?? "P1·P2"
        }
        return sessionName.uppercased()
    }

    var compactTrailingText: String {
        if presentation == IslandContentMode.positionChanges.rawValue { return positionFocus.map(MotorsportAssetName.abbreviation) ?? lapLabel }
        if presentation == IslandContentMode.favorite.rawValue || (presentation == IslandContentMode.battle.rawValue && battleDrivers?.count == 1) { return (presentation == IslandContentMode.battle.rawValue ? battleDrivers?.first?.position : trackedDriver?.position ?? favoritePosition).map { "P\($0)" } ?? "—" }
        if presentation == IslandContentMode.battle.rawValue { return (battleDrivers == nil ? challengerGap : battleGap) ?? "—" }
        return lapLabel
    }

    var trackColor: Color {
        let label = (trackLabel ?? "").lowercased()
        if label.contains("红旗") || label.contains("red flag") { return .red }
        if label.contains("黄旗") || label.contains("安全车") || label.contains("yellow") || label.contains("safety car") { return .yellow }
        if label.contains("绿旗") || label.contains("green") { return .green }
        return .secondary
    }
}
#endif
