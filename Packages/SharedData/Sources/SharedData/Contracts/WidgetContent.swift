import Foundation

/// Compact state written by the host app and read by widget/watch extensions.
public struct WidgetContent: Codable, Equatable, Sendable {
    public var sessionName: String?
    public var meetingName: String?
    public var statusLabel: String?
    public var lapLabel: String?
    public var driverName: String?
    public var driverPosition: Int?
    public var series: String?
    public var updatedAt: String?
    public var isStale: Bool
    public init(sessionName: String? = nil, meetingName: String? = nil,
                statusLabel: String? = nil, lapLabel: String? = nil,
                driverName: String? = nil, driverPosition: Int? = nil,
                series: String? = nil, updatedAt: String? = nil,
                isStale: Bool = true) {
        self.sessionName = sessionName; self.meetingName = meetingName
        self.statusLabel = statusLabel; self.lapLabel = lapLabel
        self.driverName = driverName; self.driverPosition = driverPosition
        self.series = series; self.updatedAt = updatedAt
        self.isStale = isStale
    }
}
