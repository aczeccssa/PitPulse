import Foundation

public struct HealthResponse: Codable, Equatable, Sendable {
    public let status: String
    public let database: Bool
    public let live: Bool
    public let version: String
}
