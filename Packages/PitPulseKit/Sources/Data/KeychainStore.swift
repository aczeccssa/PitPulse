import Foundation
import Security

public struct KeychainStore: CredentialStore {
    public let service: String

    public init(service: String = "com.pitpulse.F1Companion") {
        self.service = service
    }

    public func token(for server: URL) throws -> String? {
        guard !service.isEmpty else { throw CredentialError.invalidService }
        var query = baseQuery(for: server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialError.unavailable(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else {
            throw CredentialError.invalidData
        }
        return token
    }

    public func save(token: String, for server: URL) throws {
        guard !service.isEmpty else { throw CredentialError.invalidService }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CredentialError.emptyToken }
        guard let data = trimmed.data(using: .utf8) else {
            throw CredentialError.invalidData
        }

        let query = baseQuery(for: server)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialError.unavailable(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw CredentialError.unavailable(insertStatus)
        }
    }

    public func deleteToken(for server: URL) throws {
        guard !service.isEmpty else { throw CredentialError.invalidService }
        let status = SecItemDelete(baseQuery(for: server) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.unavailable(status)
        }
    }

    private func baseQuery(for server: URL) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: (try? ServerAddress(rawValue: server.absoluteString).identity) ?? server.absoluteString
        ]
    }
}
