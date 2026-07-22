import Foundation
import LocalAuthentication
import Security

protocol CredentialStore: Sendable {
    func readToken(profileID: UUID, allowAuthenticationUI: Bool) throws -> String?
    func requestAuthorization(profileID: UUID, forceResetDefaultKeychain: Bool) throws
    func saveToken(_ token: String, profileID: UUID) throws
    func clearToken(profileID: UUID) throws
    func deleteToken(profileID: UUID) throws
}

extension CredentialStore {
    func requestAuthorization(profileID: UUID, forceResetDefaultKeychain: Bool) throws {
        _ = try readToken(profileID: profileID, allowAuthenticationUI: true)
    }
}

protocol KeychainItemBackend: Sendable {
    func read(service: String, profileID: UUID, allowAuthenticationUI: Bool) throws -> String?
    func upsert(_ value: String, service: String, profileID: UUID) throws
    func delete(service: String, profileID: UUID) throws
}

protocol CredentialNamespaceStore: Sendable {
    func service(profileID: UUID) -> String?
    func selectService(_ service: String?, profileID: UUID)
}

protocol DefaultKeychainAuthorizer: Sendable {
    func requestUnlock(forceReset: Bool) throws
}

struct SystemDefaultKeychainAuthorizer: DefaultKeychainAuthorizer, Sendable {
    // SecItem APIs still store generic-password items in the legacy default
    // Keychain on macOS. When that Keychain is locked, SecItemAdd can return
    // errSecAuthFailed without presenting UI. This legacy API is the system's
    // remaining way to explicitly present the Unlock Keychain dialog.
    @available(macOS, deprecated: 10.10, message: "Required to unlock the legacy default macOS Keychain")
    func requestUnlock(forceReset: Bool) throws {
        var defaultKeychain: SecKeychain?
        let copyStatus = SecKeychainCopyDefault(&defaultKeychain)
        guard copyStatus == errSecSuccess, let defaultKeychain else {
            throw KeychainError(status: copyStatus)
        }
        if forceReset {
            let lockStatus = SecKeychainLock(defaultKeychain)
            guard lockStatus == errSecSuccess else {
                throw KeychainError(status: lockStatus)
            }
        }
        let unlockStatus = SecKeychainUnlock(defaultKeychain, 0, nil, false)
        guard unlockStatus == errSecSuccess else {
            throw KeychainError(status: unlockStatus)
        }
    }
}

final class UserDefaultsCredentialNamespaceStore: CredentialNamespaceStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private let keyPrefix = "teleMessEnd.coreTokenService."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func service(profileID: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.string(forKey: key(for: profileID))
    }

    func selectService(_ service: String?, profileID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        let key = key(for: profileID)
        if let service {
            defaults.set(service, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for profileID: UUID) -> String {
        keyPrefix + profileID.uuidString
    }
}

struct KeychainStore: CredentialStore, Sendable {
    private let legacyService = "com.dreaifekks.TeleMessEnd.coreToken"
    private let managedServicePrefix = "com.dreaifekks.TeleMessEnd.coreToken.managed"
    private let backend: any KeychainItemBackend
    private let namespaceStore: any CredentialNamespaceStore
    private let defaultKeychainAuthorizer: any DefaultKeychainAuthorizer
    private let logger: AppRuntimeLogger

    init() {
        backend = SystemKeychainItemBackend()
        namespaceStore = UserDefaultsCredentialNamespaceStore()
        defaultKeychainAuthorizer = SystemDefaultKeychainAuthorizer()
        logger = AppLog.runtime
    }

    init(
        backend: any KeychainItemBackend,
        namespaceStore: any CredentialNamespaceStore,
        defaultKeychainAuthorizer: any DefaultKeychainAuthorizer = SystemDefaultKeychainAuthorizer(),
        logger: AppRuntimeLogger = AppLog.runtime
    ) {
        self.backend = backend
        self.namespaceStore = namespaceStore
        self.defaultKeychainAuthorizer = defaultKeychainAuthorizer
        self.logger = logger
    }

    func readToken(profileID: UUID, allowAuthenticationUI: Bool = true) throws -> String? {
        if let managedService = namespaceStore.service(profileID: profileID) {
            let token = try backend.read(
                service: managedService,
                profileID: profileID,
                allowAuthenticationUI: allowAuthenticationUI
            )
            return token.flatMap { $0.isEmpty ? nil : $0 }
        }

        guard let legacyToken = try backend.read(
            service: legacyService,
            profileID: profileID,
            allowAuthenticationUI: allowAuthenticationUI
        ) else {
            return nil
        }

        // Migration is additive. Keep the legacy item as a rollback source and
        // only select the managed namespace after its write succeeds.
        do {
            try writeManaged(legacyToken, profileID: profileID)
        } catch {
            let suffix = String(profileID.uuidString.suffix(8))
            logger.warning("Legacy Keychain migration deferred profileSuffix=\(suffix)")
        }
        return legacyToken.isEmpty ? nil : legacyToken
    }

    func requestAuthorization(profileID: UUID, forceResetDefaultKeychain: Bool) throws {
        let profileSuffix = String(profileID.uuidString.suffix(8))
        logger.info(
            "Default Keychain unlock begin profileSuffix=\(profileSuffix) forceReset=\(forceResetDefaultKeychain)"
        )
        do {
            try defaultKeychainAuthorizer.requestUnlock(forceReset: forceResetDefaultKeychain)
            logger.info("Default Keychain unlock end profileSuffix=\(profileSuffix) result=success")
        } catch {
            logger.warning(
                "Default Keychain unlock end profileSuffix=\(profileSuffix) result=failure error=\(safeKeychainErrorSummary(error))"
            )
            throw error
        }
        _ = try readToken(profileID: profileID, allowAuthenticationUI: true)
    }

    func saveToken(_ token: String, profileID: UUID) throws {
        try writeManaged(token, profileID: profileID)
    }

    func clearToken(profileID: UUID) throws {
        // An empty managed item is a tombstone. It prevents a cleared profile
        // from falling back to an inaccessible or stale legacy token.
        try writeManaged("", profileID: profileID)
    }

    func deleteToken(profileID: UUID) throws {
        var firstError: Error?

        if let managedService = namespaceStore.service(profileID: profileID) {
            do {
                try backend.delete(service: managedService, profileID: profileID)
            } catch {
                firstError = error
            }
            namespaceStore.selectService(nil, profileID: profileID)
        }

        do {
            try backend.delete(service: legacyService, profileID: profileID)
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private func writeManaged(_ value: String, profileID: UUID) throws {
        if let selectedService = namespaceStore.service(profileID: profileID) {
            do {
                try backend.upsert(value, service: selectedService, profileID: profileID)
                return
            } catch let error as KeychainError where error.isAuthenticationFailure {
                let suffix = String(profileID.uuidString.suffix(8))
                logger.info("Rotating inaccessible Keychain item profileSuffix=\(suffix)")
            }
        }

        let replacementService = managedServicePrefix + "." + UUID().uuidString
        do {
            try backend.upsert(value, service: replacementService, profileID: profileID)
        } catch {
            let suffix = String(profileID.uuidString.suffix(8))
            logger.error("Managed Keychain write failed profileSuffix=\(suffix) error=\(safeKeychainErrorSummary(error))")
            throw error
        }
        namespaceStore.selectService(replacementService, profileID: profileID)
        let suffix = String(profileID.uuidString.suffix(8))
        logger.info("Managed Keychain namespace selected profileSuffix=\(suffix)")
    }
}

struct SystemKeychainItemBackend: KeychainItemBackend, Sendable {
    private let logger: AppRuntimeLogger

    init(logger: AppRuntimeLogger = AppLog.runtime) {
        self.logger = logger
    }

    func read(service: String, profileID: UUID, allowAuthenticationUI: Bool) throws -> String? {
        let profileSuffix = String(profileID.uuidString.suffix(8))
        logger.info("Keychain read begin profileSuffix=\(profileSuffix) allowUI=\(allowAuthenticationUI)")
        var query = matchQuery(service: service, profileID: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.localizedReason = "TeleMessEnd needs access to the saved Core token."
        context.interactionNotAllowed = !allowAuthenticationUI
        query[kSecUseAuthenticationContext as String] = context

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        logger.info("Keychain read end profileSuffix=\(profileSuffix) status=\(status)")
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return token
    }

    func upsert(_ value: String, service: String, profileID: UUID) throws {
        let profileSuffix = String(profileID.uuidString.suffix(8))
        logger.info("Keychain save begin profileSuffix=\(profileSuffix)")
        let data = Data(value.utf8)
        var query = matchQuery(service: service, profileID: profileID)
        let context = LAContext()
        context.localizedReason = "TeleMessEnd needs permission to save the Core token."
        query[kSecUseAuthenticationContext as String] = context
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrLabel as String] = "TeleMessEnd Core token"
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            logger.info("Keychain save add end profileSuffix=\(profileSuffix) status=\(addStatus)")
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        } else if status != errSecSuccess {
            logger.error("Keychain save update end profileSuffix=\(profileSuffix) status=\(status)")
            throw KeychainError(status: status)
        } else {
            logger.info("Keychain save update end profileSuffix=\(profileSuffix) status=\(status)")
        }
    }

    func delete(service: String, profileID: UUID) throws {
        let profileSuffix = String(profileID.uuidString.suffix(8))
        logger.info("Keychain delete begin profileSuffix=\(profileSuffix)")
        let status = SecItemDelete(matchQuery(service: service, profileID: profileID) as CFDictionary)
        logger.info("Keychain delete end profileSuffix=\(profileSuffix) status=\(status)")
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError(status: status)
        }
    }

    private func matchQuery(service: String, profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString
        ]
    }
}

private func safeKeychainErrorSummary(_ error: Error) -> String {
    if let error = error as? KeychainError {
        return "status_\(error.status)"
    }
    return String(describing: type(of: error))
}

struct KeychainError: LocalizedError, Equatable {
    var status: OSStatus

    var isInteractionNotAllowed: Bool {
        status == errSecInteractionNotAllowed
    }

    var isAuthenticationFailure: Bool {
        status == errSecAuthFailed
    }

    var requiresUserAuthorization: Bool {
        status == errSecAuthFailed
            || status == errSecInteractionNotAllowed
            || status == errSecUserCanceled
    }

    var errorDescription: String? {
        switch status {
        case errSecAuthFailed:
            "TeleMessEnd could not access the existing token in macOS Keychain. Enter the token again and choose Save to create a replacement credential."
        case errSecInteractionNotAllowed:
            "The saved token requires Keychain authorization. Open Core Settings and choose Test Connection."
        case errSecMissingEntitlement:
            "This TeleMessEnd build is missing the Keychain signing entitlement required by its credential store."
        default:
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                message
            } else {
                "Keychain error \(status)"
            }
        }
    }
}
