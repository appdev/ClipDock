import Foundation
import Security

enum SyncCredentialStoreError: Error, Equatable {
    case keychainStatus(OSStatus)
    case invalidTokenData
}

struct SyncCredentialStore: Sendable {
    private let service = "com.clipdock.sync.device-token"

    func save(token: String, deviceID: String) throws {
        let account = normalizedDeviceID(deviceID)
        let data = Data(token.utf8)

        try delete(deviceID: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SyncCredentialStoreError.keychainStatus(status)
        }
    }

    func token(deviceID: String?) throws -> String? {
        guard let account = normalizedOptionalDeviceID(deviceID) else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SyncCredentialStoreError.keychainStatus(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw SyncCredentialStoreError.invalidTokenData
        }
        return token
    }

    func delete(deviceID: String?) throws {
        guard let account = normalizedOptionalDeviceID(deviceID) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SyncCredentialStoreError.keychainStatus(status)
        }
    }

    private func normalizedOptionalDeviceID(_ deviceID: String?) -> String? {
        guard let deviceID else { return nil }
        let normalized = normalizedDeviceID(deviceID)
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
