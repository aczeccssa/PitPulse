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
        public var trackLabel: String?
        public var driverCount: Int
        public var isStale: Bool
        public var updatedLabel: String?

        public init(
            sessionName: String,
            meetingName: String,
            statusLabel: String,
            lapLabel: String,
            leaderName: String? = nil,
            leaderGap: String? = nil,
            trackLabel: String? = nil,
            driverCount: Int = 0,
            isStale: Bool = false,
            updatedLabel: String? = nil
        ) {
            self.sessionName = sessionName
            self.meetingName = meetingName
            self.statusLabel = statusLabel
            self.lapLabel = lapLabel
            self.leaderName = leaderName
            self.leaderGap = leaderGap
            self.trackLabel = trackLabel
            self.driverCount = driverCount
            self.isStale = isStale
            self.updatedLabel = updatedLabel
        }
    }

    public var seriesTitle: String

    public init(seriesTitle: String) {
        self.seriesTitle = seriesTitle
    }
}
#endif
