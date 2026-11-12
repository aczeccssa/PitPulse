import Foundation

public struct APIEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    public let data: Value
    public let meta: ResponseMeta

    public init(data: Value, meta: ResponseMeta) {
        self.data = data
        self.meta = meta
    }
}

public enum ManualRefreshTarget: String, Codable, Sendable {
    case calendar, results, standings
}

public struct RefreshRequest: Codable, Sendable {
    public let season: Int
    public let target: ManualRefreshTarget
    public let sessionId: String?
}

public enum DataRefreshStatus: String, Codable, Sendable {
    case inProgress, completed, partial, failed, rateLimited
}

public struct DataRefreshEvent: Codable, Equatable, Sendable {
    public let target: ManualRefreshTarget
    public let season: Int
    public let sessionId: String?
    public let status: DataRefreshStatus
    public let updatedAt: String
    public let retryAfter: String?
}
