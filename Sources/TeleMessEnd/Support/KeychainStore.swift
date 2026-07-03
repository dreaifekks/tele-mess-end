import Foundation
import Security

struct KeychainStore: Sendable {
    private let service = "com.dreaifekks.TeleMessEnd.coreToken"

    func readToken(profileID: UUID) throws -> String? {
        var query = baseQuery(profileID: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveToken(_ token: String, profileID: UUID) throws {
        let data = Data(token.utf8)
        var query = baseQuery(profileID: profileID)
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func deleteToken(profileID: UUID) throws {
        let status = SecItemDelete(baseQuery(profileID: profileID) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }
}

struct KeychainError: LocalizedError, Equatable {
    var status: OSStatus

    var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "Keychain error \(status)"
    }
}
