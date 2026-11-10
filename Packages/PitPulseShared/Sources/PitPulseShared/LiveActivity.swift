import Foundation

#if os(iOS)
import ActivityKit

/// The cross-process contract between the iOS app (which owns the live stream)
/// and the Live Activity / Dynamic Island extension (which renders it).
public struct PitPulseActivityAttributes: ActivityAttributes {
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
        public var favoriteAsset: String?

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
            favoriteAsset: String? = nil
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
            self.favoriteAsset = favoriteAsset
        }
    }

    public var seriesTitle: String

    public init(seriesTitle: String) {
        self.seriesTitle = seriesTitle
    }
}
#endif
