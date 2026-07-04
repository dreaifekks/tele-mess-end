import Foundation
import LocalAuthentication
import Security

struct KeychainStore: Sendable {
    private let service = "com.dreaifekks.TeleMessEnd.coreToken"

    func readToken(profileID: UUID, allowAuthenticationUI: Bool = true) throws -> String? {
        let profileSuffix = String(profileID.uuidString.suffix(8))
        AppLog.runtime.info("Keychain read begin profileSuffix=\(profileSuffix, privacy: .public) allowUI=\(allowAuthenticationUI, privacy: .public)")
        var query = baseQuery(profileID: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowAuthenticationUI {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
            // Raw value of kSecUseAuthenticationUIFail. Keep this alongside
            // LAContext because keychain item access prompts are not always
            // covered by LocalAuthentication interaction suppression.
            query[kSecUseAuthenticationUI as String] = "u_AuthUIF"
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        AppLog.runtime.info("Keychain read end profileSuffix=\(profileSuffix, privacy: .public) status=\(status, privacy: .public)")
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
        let profileSuffix = String(profileID.uuidString.suffix(8))
        AppLog.runtime.info("Keychain save begin profileSuffix=\(profileSuffix, privacy: .public)")
        let data = Data(token.utf8)
        var query = baseQuery(profileID: profileID)
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            AppLog.runtime.info("Keychain save add end profileSuffix=\(profileSuffix, privacy: .public) status=\(addStatus, privacy: .public)")
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        } else if status != errSecSuccess {
            AppLog.runtime.info("Keychain save update end profileSuffix=\(profileSuffix, privacy: .public) status=\(status, privacy: .public)")
            throw KeychainError(status: status)
        } else {
            AppLog.runtime.info("Keychain save update end profileSuffix=\(profileSuffix, privacy: .public) status=\(status, privacy: .public)")
        }
    }

    func deleteToken(profileID: UUID) throws {
        let profileSuffix = String(profileID.uuidString.suffix(8))
        AppLog.runtime.info("Keychain delete begin profileSuffix=\(profileSuffix, privacy: .public)")
        let status = SecItemDelete(baseQuery(profileID: profileID) as CFDictionary)
        AppLog.runtime.info("Keychain delete end profileSuffix=\(profileSuffix, privacy: .public) status=\(status, privacy: .public)")
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

    var isInteractionNotAllowed: Bool {
        status == errSecInteractionNotAllowed
    }

    var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "Keychain error \(status)"
    }
}
