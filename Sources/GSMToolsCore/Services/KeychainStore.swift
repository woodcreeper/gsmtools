import Foundation
import Security

public final class KeychainStore {
    private let service: String
    private let account: String

    public init(service: String = "com.woodcreeper.gsmtools", account: String = "ctt-personal-access-token") {
        self.service = service
        self.account = account
    }

    public func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try updateToken(token)
        } else if status != errSecSuccess {
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func loadToken() throws -> String? {
        if let token = try loadToken(matching: baseQuery()) {
            return token
        }

        guard let legacyToken = try loadToken(matching: baseQuery(useDataProtectionKeychain: false)) else {
            return nil
        }
        try? saveToken(legacyToken)
        return legacyToken
    }

    private func loadToken(matching baseQuery: [String: Any]) throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return token
    }

    public func deleteToken() throws {
        for query in [baseQuery(), baseQuery(useDataProtectionKeychain: false)] {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw KeychainError.unhandledStatus(status)
            }
        }
    }

    private func updateToken(_ token: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(useDataProtectionKeychain: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}

public enum KeychainError: Error, LocalizedError, Equatable {
    case invalidData
    case unhandledStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Keychain item was not valid UTF-8."
        case let .unhandledStatus(status):
            return "Keychain operation failed with status \(status)."
        }
    }
}
