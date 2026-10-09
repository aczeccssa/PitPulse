import Foundation

protocol CredentialStore: Sendable {
    func token(for server: URL) throws -> String?
    func save(token: String, for server: URL) throws
    func deleteToken(for server: URL) throws
}

enum CredentialError: Error, Equatable, LocalizedError {
    case invalidService
    case emptyToken
    case unavailable(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidService:
            "Keychain 服务名称无效。"
        case .emptyToken:
            "Token 不能为空。"
        case .unavailable:
            "无法读取或写入 Keychain。"
        case .invalidData:
            "Keychain 中的数据无效。"
        }
    }
}
