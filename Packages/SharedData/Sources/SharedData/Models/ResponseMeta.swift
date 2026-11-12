import Foundation

public struct ResponseMeta: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: Int
    public var stale: Bool
    public let quality: DataQuality
    public let source: String?
    public let fetchedAt: Date?
    public let sourceUpdatedAt: Date?
    public var analysisStatus: String? = nil
    public var analysisError: String? = nil
    public var analysisIsLoading: Bool { analysisStatus == "loading" || analysisStatus == "pending" }
    public var analysisCanBeCached: Bool { analysisStatus == nil || analysisStatus == "ready" }

    public init(
        schemaVersion: Int,
        revision: Int,
        stale: Bool,
        quality: DataQuality,
        source: String?,
        fetchedAt: Date?,
        sourceUpdatedAt: Date?,
        analysisStatus: String? = nil,
        analysisError: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.stale = stale
        self.quality = quality
        self.source = source
        self.fetchedAt = fetchedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.analysisStatus = analysisStatus
        self.analysisError = analysisError
    }
}

public enum DataQuality: String, Codable, Sendable {
    case pending
    case partial
    case provisional
    case final
    case stale

    public var displayName: String {
        switch self {
        case .pending: "待同步"
        case .partial: "部分数据"
        case .provisional: "暂定"
        case .final: "最终"
        case .stale: "已过期"
        }
    }
}
