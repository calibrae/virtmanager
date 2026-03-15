import Foundation
import Security

public final class CredentialStore: Sendable {
    public static let shared = CredentialStore()

    private let service = "com.virtmanager.connection"

    public init() {}

    public func savePassword(_ password: String, for uri: String) throws {
        let data = Data(password.utf8)

        // Delete existing item first
        try? deletePassword(for: uri)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: uri,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.saveFailed(status: status)
        }
    }

    public func retrievePassword(for uri: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: uri,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialStoreError.retrieveFailed(status: status)
        }

        return String(data: data, encoding: .utf8)
    }

    public func deletePassword(for uri: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: uri,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.deleteFailed(status: status)
        }
    }
}

public enum CredentialStoreError: Error, VirtManagerError {
    case saveFailed(status: OSStatus)
    case retrieveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let s):
            "Failed to save credential (status: \(s))"
        case .retrieveFailed(let s):
            "Failed to retrieve credential (status: \(s))"
        case .deleteFailed(let s):
            "Failed to delete credential (status: \(s))"
        }
    }

    public var recoverySuggestion: String? {
        "Check Keychain access permissions."
    }
}
