import Foundation
import Security

/// Opaque credential storage used by native Fish adapters. Secrets are never written to UserDefaults.
final class FishSecureStore {
    static let shared = FishSecureStore()
    private let service = "com.fongmi.ok4k.ios.fish"

    func data(for account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw FishSecureStoreError.status(status) }
        return value as? Data
    }

    func set(_ data: Data, for account: String) throws {
        var attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let query = baseQuery(account)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            attributes.merge(query) { current, _ in current }
            let insertStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw FishSecureStoreError.status(insertStatus) }
        } else if status != errSecSuccess {
            throw FishSecureStoreError.status(status)
        }
    }

    func remove(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FishSecureStoreError.status(status)
        }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum FishSecureStoreError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let value): return "Keychain 操作失败（\(value)）"
        }
    }
}
