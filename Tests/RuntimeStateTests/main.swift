import Foundation
import Security

@main
enum RuntimeStateTests {
    static func main() async {
        var runner = RuntimeTestRunner()
        await runner.run("summary settings are isolated by profile") {
            try summarySettingsAreProfileScoped()
        }
        await runner.run("profile selection resolves nil and invalid IDs") {
            try profileSelectionAlwaysResolves()
        }
        await runner.run("delivery fallback distinguishes omitted and null") {
            try deliveryFallbackUsesFieldPresence()
        }
        await runner.run("summary target options follow the active draft") {
            try summaryTargetOptionsFollowDraft()
        }
        await runner.run("auth-disabled local core loads without token") {
            try await localCoreLoadsWithoutToken()
        }
        await runner.run("remote background load requires a token") {
            try await remoteBackgroundLoadRequiresToken()
        }
        await runner.run("protected local token never degrades to no auth") {
            try await protectedLocalTokenDoesNotDegrade()
        }
        await runner.run("legacy token migrates without deletion") {
            try legacyTokenMigratesWithoutDeletion()
        }
        await runner.run("inaccessible managed token rotates on save") {
            try inaccessibleManagedTokenRotatesOnSave()
        }
        await runner.run("managed clear masks a legacy token") {
            try managedClearMasksLegacyToken()
        }
        await runner.run("runtime log buffer is bounded and clearable") {
            try runtimeLogBufferIsBoundedAndClearable()
        }
        await runner.run("runtime log store follows concurrent writers") {
            try await runtimeLogStoreFollowsConcurrentWriters()
        }
        await runner.run("Core output clear keeps later process output") {
            try await coreOutputClearKeepsLaterProcessOutput()
        }
        await runner.run("keychain runtime logs omit credential material") {
            try keychainRuntimeLogsOmitCredentialMaterial()
        }
        await runner.run("app operation failures emit safe runtime logs") {
            try await appOperationFailuresEmitSafeRuntimeLogs()
        }
        await runner.run("API runtime logs omit auth and query values") {
            try await apiRuntimeLogsOmitAuthAndQueryValues()
        }
        await runner.run("saving the same profile advances the session") {
            try sameProfileSaveAdvancesSession()
        }
        await runner.run("successful account mutation survives refresh failure") {
            try await accountMutationSurvivesRefreshFailure()
        }
        await runner.run("partial batch mutation remains visible") {
            try await partialBatchMutationRemainsVisible()
        }
        await runner.run("stale profile request cannot commit") {
            try await staleProfileRequestIsDiscarded()
        }
        await runner.run("newer search wins within one profile") {
            try await newerSearchWins()
        }
        await runner.run("manifest bootstraps before feature loading") {
            try await manifestBootstrapsBeforeFeatureLoad()
        }
        await runner.run("message points follow manifest, filters, item loading, and session reset") {
            try await messagePointsFollowManifestAndSession()
        }
        await runner.run("busy validation waits without false failure") {
            try await busyValidationDoesNotFail()
        }
        runner.finish()
    }

    @MainActor
    private static func summarySettingsAreProfileScoped() throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let store = SummarySettingsStore(defaults: defaults)
        let firstProfileID = UUID()
        let secondProfileID = UUID()

        store.selectProfile(firstProfileID)
        var firstSettings = SummarySettings()
        firstSettings.deliveryEnabled = true
        firstSettings.deliveryAccountID = "first"
        firstSettings.deliveryOriginID = "-1001"
        store.save(firstSettings)

        store.selectProfile(secondProfileID)
        try expectEqual(store.settings.deliveryEnabled, false)
        var secondSettings = SummarySettings()
        secondSettings.deliveryAccountID = "second"
        store.save(secondSettings)

        store.selectProfile(firstProfileID)
        try expectEqual(store.settings.deliveryEnabled, true)
        try expectEqual(store.settings.deliveryAccountID, "first")
        try expectEqual(store.settings.deliveryOriginID, "-1001")
    }

    @MainActor
    private static func profileSelectionAlwaysResolves() throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let store = CoreProfileStore(defaults: defaults)
        let firstID = store.selectedProfile?.id

        store.select(nil)
        try expectEqual(store.selectedProfileID, firstID)
        store.select(UUID())
        try expectEqual(store.selectedProfileID, firstID)
    }

    @MainActor
    private static func deliveryFallbackUsesFieldPresence() throws {
        var fallback = SummarySettings()
        fallback.deliveryEnabled = true
        fallback.deliveryAccountID = "main"
        fallback.deliveryOriginID = "-1001"
        fallback.deliveryTopicID = "42"

        let omitted = try decodeSchedule(deliveryJSON: nil)
        try expectEqual(omitted.deliveryWasProvided, false)
        let preserved = SummarySettings(schedule: omitted, preservingDeliveryFrom: fallback)
        try expectEqual(preserved.deliveryEnabled, true)
        try expectEqual(preserved.deliveryAccountID, "main")

        let explicitNull = try decodeSchedule(deliveryJSON: "null")
        try expectEqual(explicitNull.deliveryWasProvided, true)
        try expectNil(explicitNull.delivery)
        let cleared = SummarySettings(schedule: explicitNull, preservingDeliveryFrom: fallback)
        try expectEqual(cleared.deliveryEnabled, false)
        try expectEqual(cleared.deliveryAccountID, "")
        try expectEqual(cleared.deliveryOriginID, "")
        try expectEqual(cleared.deliveryTopicID, "")
    }

    private static func summaryTargetOptionsFollowDraft() throws {
        let accounts = try JSONDecoder.core.decode(
            [CoreAccount].self,
            from: Data(
                """
                [
                  {"source":"telegram","account_id":"a","display_name":"Primary"},
                  {"source":"telegram","account_id":"b","display_name":"Backup"}
                ]
                """.utf8
            )
        )
        let origins = try JSONDecoder.core.decode(
            [CoreOrigin].self,
            from: Data(
                """
                [
                  {"source":"telegram","account_id":"a","origin_id":100,"origin_type":"group","title":"Alpha","backup_policy":{"enabled":true,"capture_text":true,"capture_media_metadata":true,"download_media":false,"tags":"ops, daily"}},
                  {"source":"telegram","account_id":"a","origin_id":100,"topic_id":10,"origin_type":"topic","title":"Alpha / News"},
                  {"source":"telegram","account_id":"a","origin_id":100,"topic_id":11,"origin_type":"topic","title":"Alpha / Ops"},
                  {"source":"telegram","account_id":"b","origin_id":200,"origin_type":"channel","title":"Beta"}
                ]
                """.utf8
            )
        )
        var draft = SummarySettings()
        draft.accountID = "a"
        draft.originID = "100"
        draft.deliveryAccountID = "a"
        draft.deliveryOriginID = "100"

        let options = SummaryTargetOptions(accounts: accounts, origins: origins, draft: draft)
        try expectEqual(options.scopeAccountIDs, ["a", "b"])
        try expectEqual(options.scopeOrigins.map(\.value), ["100"])
        try expectEqual(options.scopeTopics.map(\.value), ["10", "11"])
        try expectEqual(options.deliveryOrigins.map(\.value), ["100"])
        try expectEqual(options.deliveryTopics.map(\.value), ["10", "11"])
        try expectEqual(options.scopeTags, ["daily", "ops"])
    }

    @MainActor
    private static func localCoreLoadsWithoutToken() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let profileStore = CoreProfileStore(defaults: defaults)
        let model = AppModel(
            profileStore: profileStore,
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: DashboardTransport()
        )

        await model.loadDashboard(allowKeychainUI: false)

        try expectEqual(model.dashboard.coreState?.databaseID, "db")
        try expectEqual(model.dashboard.recentMessages.count, 0)
        try expectNil(model.lastError)
    }

    @MainActor
    private static func remoteBackgroundLoadRequiresToken() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let profileStore = CoreProfileStore(defaults: defaults)
        let model = AppModel(
            profileStore: profileStore,
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: FailIfCalledTransport()
        )
        var remote = model.addRemoteProfile()
        remote.baseURLString = "http://core.example"
        try expectEqual(model.saveProfile(remote, token: nil), true)

        await model.loadDashboard(allowKeychainUI: false)

        try expectNil(model.dashboard.coreState)
        try expectEqual(model.lastError, CoreAPIError.missingToken.localizedDescription)
    }

    @MainActor
    private static func protectedLocalTokenDoesNotDegrade() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: InteractionBlockedCredentialStore(),
            transport: FailIfCalledTransport()
        )

        await model.loadDashboard(allowKeychainUI: false)

        try expectNil(model.dashboard.coreState)
        try expectEqual(
            model.lastError,
            KeychainError(status: errSecInteractionNotAllowed).localizedDescription
        )
    }

    private static func legacyTokenMigratesWithoutDeletion() throws {
        let profileID = UUID()
        let backend = MemoryKeychainItemBackend()
        let namespaces = MemoryCredentialNamespaceStore()
        let legacyService = "com.dreaifekks.TeleMessEnd.coreToken"
        backend.values[legacyService] = "legacy-token"
        let store = KeychainStore(backend: backend, namespaceStore: namespaces)

        let token = try store.readToken(profileID: profileID, allowAuthenticationUI: false)

        try expectEqual(token, "legacy-token")
        guard let managedService = namespaces.service(profileID: profileID) else {
            throw RuntimeTestError.failure("Expected a managed credential namespace")
        }
        try expectEqual(backend.values[managedService], "legacy-token")
        try expectEqual(backend.values[legacyService], "legacy-token")
    }

    private static func inaccessibleManagedTokenRotatesOnSave() throws {
        let profileID = UUID()
        let backend = MemoryKeychainItemBackend()
        let namespaces = MemoryCredentialNamespaceStore()
        let inaccessibleService = "managed-inaccessible"
        namespaces.selectService(inaccessibleService, profileID: profileID)
        backend.values[inaccessibleService] = "old-token"
        backend.upsertFailures[inaccessibleService] = KeychainError(status: errSecAuthFailed)
        let store = KeychainStore(backend: backend, namespaceStore: namespaces)

        try store.saveToken("replacement-token", profileID: profileID)

        guard let replacementService = namespaces.service(profileID: profileID) else {
            throw RuntimeTestError.failure("Expected a replacement credential namespace")
        }
        try expectEqual(replacementService == inaccessibleService, false)
        try expectEqual(backend.values[inaccessibleService], "old-token")
        try expectEqual(backend.values[replacementService], "replacement-token")
        try expectEqual(
            store.readToken(profileID: profileID, allowAuthenticationUI: false),
            "replacement-token"
        )
    }

    private static func managedClearMasksLegacyToken() throws {
        let profileID = UUID()
        let backend = MemoryKeychainItemBackend()
        let namespaces = MemoryCredentialNamespaceStore()
        let legacyService = "com.dreaifekks.TeleMessEnd.coreToken"
        backend.values[legacyService] = "legacy-token"
        let store = KeychainStore(backend: backend, namespaceStore: namespaces)

        try store.clearToken(profileID: profileID)

        try expectNil(store.readToken(profileID: profileID, allowAuthenticationUI: false))
        try expectEqual(backend.values[legacyService], "legacy-token")
        guard let managedService = namespaces.service(profileID: profileID) else {
            throw RuntimeTestError.failure("Expected a managed credential tombstone")
        }
        try expectEqual(backend.values[managedService], "")
    }

    private static func runtimeLogBufferIsBoundedAndClearable() throws {
        let buffer = AppRuntimeLogBuffer(maximumEntries: 2, maximumCharacters: 1_000)
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )

        logger.info("first")
        logger.warning("second")
        logger.error("third")

        try expectEqual(buffer.snapshot().entries.map(\.event.message), ["second", "third"])
        try expectEqual(buffer.clear().entries.isEmpty, true)
        try expectEqual(buffer.snapshot().entries.isEmpty, true)
    }

    @MainActor
    private static func runtimeLogStoreFollowsConcurrentWriters() async throws {
        let buffer = AppRuntimeLogBuffer(maximumEntries: 200, maximumCharacters: 20_000)
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let store = AppRuntimeLogStore(buffer: buffer)
        store.startMonitoring()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    logger.info("concurrent entry \(index)")
                }
            }
        }

        for _ in 0..<100 where store.entries.count < 100 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        try expectEqual(store.entries.count, 100)
        try expectEqual(store.entries.map(\.id), (1...100).map(UInt64.init))
    }

    @MainActor
    private static func coreOutputClearKeepsLaterProcessOutput() async throws {
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let runner = LocalCoreProcessController(logger: logger)
        var profile = CoreProfile.defaultLocal
        profile.localCommand = "printf before-clear; sleep 0.15; printf after-clear"
        runner.start(profile: profile)
        defer { runner.stop() }

        for _ in 0..<100 where !runner.lastOutput.contains("before-clear") {
            try? await Task.sleep(for: .milliseconds(5))
        }
        try expectEqual(runner.lastOutput.contains("before-clear"), true)
        runner.clearOutput()

        for _ in 0..<200 where runner.isRunning || runner.lastOutput != "after-clear" {
            try? await Task.sleep(for: .milliseconds(5))
        }
        try expectEqual(runner.lastOutput, "after-clear")
    }

    private static func keychainRuntimeLogsOmitCredentialMaterial() throws {
        let profileID = UUID(uuidString: "11111111-2222-3333-4444-555566667777")!
        let token = "super-secret-token"
        let legacyService = "com.dreaifekks.TeleMessEnd.coreToken"
        let backend = MemoryKeychainItemBackend()
        backend.values[legacyService] = token
        let namespaces = MemoryCredentialNamespaceStore()
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let store = KeychainStore(backend: backend, namespaceStore: namespaces, logger: logger)

        try expectEqual(store.readToken(profileID: profileID, allowAuthenticationUI: false), token)

        let rendered = buffer.snapshot().entries.map(\.renderedLine).joined(separator: "\n")
        try expectEqual(rendered.contains(String(profileID.uuidString.suffix(8))), true)
        try expectEqual(rendered.contains(profileID.uuidString), false)
        try expectEqual(rendered.contains(token), false)
        try expectEqual(rendered.contains(legacyService), false)
    }

    @MainActor
    private static func appOperationFailuresEmitSafeRuntimeLogs() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: FailIfCalledTransport(),
            runtimeLogs: AppRuntimeLogStore(buffer: buffer),
            runtimeLogger: logger,
            apiLogger: logger
        )
        var remote = model.addRemoteProfile()
        remote.baseURLString = "http://core.example"
        try expectEqual(model.saveProfile(remote, token: nil), true)
        buffer.clear()

        await model.loadDashboard(allowKeychainUI: false)

        let rendered = buffer.snapshot().entries.map(\.renderedLine).joined(separator: "\n")
        try expectEqual(
            rendered.contains("Operation end action=Loading dashboard result=failure error=missing_token"),
            true
        )
        try expectEqual(rendered.contains(remote.id.uuidString), false)
    }

    private static func apiRuntimeLogsOmitAuthAndQueryValues() async throws {
        let token = "top-secret-api-token"
        let query = "private-search-phrase"
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "api",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let client = CoreAPIClient(
            baseURL: URL(string: "http://core.example")!,
            tokenProvider: FixedTokenProvider(value: token),
            authMode: .bearer,
            transport: PrivateSearchTransport(expectedToken: token, expectedQuery: query),
            logger: logger
        )

        _ = try await client.searchMessages(query: query)

        let rendered = buffer.snapshot().entries.map(\.renderedLine).joined(separator: "\n")
        try expectEqual(rendered.contains("method=GET path=/sync/search status=200"), true)
        try expectEqual(rendered.contains(token), false)
        try expectEqual(rendered.contains(query), false)
        try expectEqual(rendered.localizedCaseInsensitiveContains("authorization"), false)
    }

    @MainActor
    private static func sameProfileSaveAdvancesSession() throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: FailIfCalledTransport()
        )
        let initialRevision = model.sessionRevision
        guard let profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected a selected profile")
        }

        try expectEqual(model.saveProfile(profile, token: nil), true)
        try expectEqual(model.sessionRevision, initialRevision + 1)
    }

    @MainActor
    private static func accountMutationSurvivesRefreshFailure() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: AccountMutationThenRefreshFailureTransport()
        )

        let succeeded = await model.createAccount(
            CreateAccountRequest(
                accountID: "created",
                displayName: nil,
                phone: nil,
                sessionName: nil,
                sessionDir: nil
            )
        )

        try expectEqual(succeeded, true)
        try expectEqual(model.accounts.map(\.accountID), ["created"])
        try expectNil(model.lastError)
        try expectEqual(model.statusMessage, "Account saved; refresh pending")
    }

    @MainActor
    private static func partialBatchMutationRemainsVisible() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: PartialArchiveTransport()
        )
        model.includeArchivedOrigins = true
        model.origins = try JSONDecoder.core.decode(
            [CoreOrigin].self,
            from: Data(
                """
                [
                  {"source":"telegram","account_id":"main","origin_id":100,"origin_type":"group","title":"First"},
                  {"source":"telegram","account_id":"main","origin_id":200,"origin_type":"group","title":"Second"}
                ]
                """.utf8
            )
        )

        let succeeded = await model.archiveOrigins(model.origins, archived: true)

        try expectEqual(succeeded, false)
        try expectEqual(model.origins.first { $0.originID == 100 }?.isArchived, true)
        try expectEqual(model.origins.first { $0.originID == 200 }?.isArchived, false)
        try expectEqual(model.lastError?.contains("1 of 2 items"), true)
    }

    @MainActor
    private static func staleProfileRequestIsDiscarded() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let profileStore = CoreProfileStore(defaults: defaults)
        let model = AppModel(
            profileStore: profileStore,
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: DelayedAccountsTransport()
        )

        let loadTask = Task { await model.loadAccounts(allowKeychainUI: false) }
        try await Task.sleep(for: .milliseconds(20))
        let newProfile = model.addRemoteProfile()
        await loadTask.value

        try expectEqual(model.selectedProfile?.id, newProfile.id)
        try expectEqual(model.accounts.count, 0)
        try expectNil(model.lastError)
    }

    @MainActor
    private static func newerSearchWins() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: ReorderedSearchTransport()
        )

        model.messageSearchQuery = "slow"
        let slowSearch = Task { await model.searchMessages() }
        try await Task.sleep(for: .milliseconds(10))
        model.messageSearchQuery = "fast"
        let fastSearch = Task { await model.searchMessages() }
        await fastSearch.value
        await slowSearch.value

        try expectEqual(model.messages.first?.text, "fast")
        try expectNil(model.lastError)
    }

    @MainActor
    private static func manifestBootstrapsBeforeFeatureLoad() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: CapabilityBootstrapTransport()
        )
        model.selectedSection = .summaries

        await model.refreshCurrentSectionWhenIdle(allowKeychainUI: false)

        try expectEqual(model.selectedSection, .dashboard)
        try expectEqual(model.availableSections, [.dashboard, .accounts])
        try expectEqual(model.dashboard.coreState?.databaseID, "db")
    }

    @MainActor
    private static func messagePointsFollowManifestAndSession() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: MessagePointRuntimeTransport()
        )
        model.selectedSection = .messagePoints
        model.messagePointSearchQuery = "needle"
        model.messagePointDateFilter = "2026-07-11"
        model.messagePointTagsFilter = "ops, ai"
        model.messagePointAccountFilter = "main"
        model.messagePointOriginIDFilter = "-1001"
        model.messagePointImportanceMin = 3
        model.messagePointImportanceMax = 5
        model.messagePointOriginImportanceFilter = .important

        await model.refreshCurrentSectionWhenIdle(allowKeychainUI: false)

        try expectEqual(model.selectedSection, .messagePoints)
        try expectEqual(model.availableSections, [.dashboard, .messagePoints])
        try expectEqual(model.dailyMessagePoints.map(\.pointID), ["point-1"])
        try expectEqual(model.dailyMessagePoints.first?.content, "List content")
        try expectNil(model.lastError)

        guard let point = model.dailyMessagePoints.first else {
            throw RuntimeTestError.failure("Expected a loaded message point")
        }
        try expectEqual(await model.loadDailyMessagePoint(point), true)
        try expectEqual(model.dailyMessagePoints.first?.content, "Detailed content")

        _ = model.addRemoteProfile()
        try expectEqual(model.dailyMessagePoints.count, 0)
        try expectEqual(model.messagePointSearchQuery, "")
        try expectEqual(model.messagePointImportanceMin, 1)
        try expectEqual(model.messagePointImportanceMax, 5)
        try expectEqual(model.messagePointOriginImportanceFilter, .any)
    }

    @MainActor
    private static func busyValidationDoesNotFail() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: DelayedAccountsTransport()
        )

        let loadTask = Task { await model.loadAccounts(allowKeychainUI: false) }
        try await Task.sleep(for: .milliseconds(20))
        let validationTask = Task { await model.validateActiveProfile() }
        try await Task.sleep(for: .milliseconds(20))
        try expectEqual(model.validationStatus.title, "Validating")
        validationTask.cancel()
        await validationTask.value
        try expectEqual(model.validationStatus.title, "Unverified")
        await loadTask.value
    }

    @MainActor
    private static func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }

    private static func decodeSchedule(deliveryJSON: String?) throws -> DailyPackageSchedule {
        let deliveryMember = deliveryJSON.map { ", \"delivery\": \($0)" } ?? ""
        let json =
            """
            {
              "enabled": true,
              "time_of_day": "08:00",
              "timezone": "Asia/Tokyo",
              "scope": {},
              "system_manager": "systemd-user",
              "installed": false
              \(deliveryMember)
            }
            """
        return try JSONDecoder.core.decode(DailyPackageSchedule.self, from: Data(json.utf8))
    }
}

private let defaultsSuiteName = "TeleMessEndTests.RuntimeSession"

private struct EmptyCredentialStore: CredentialStore {
    func readToken(profileID: UUID, allowAuthenticationUI: Bool) throws -> String? { nil }
    func saveToken(_ token: String, profileID: UUID) throws {}
    func clearToken(profileID: UUID) throws {}
    func deleteToken(profileID: UUID) throws {}
}

private struct InteractionBlockedCredentialStore: CredentialStore {
    func readToken(profileID: UUID, allowAuthenticationUI: Bool) throws -> String? {
        throw KeychainError(status: errSecInteractionNotAllowed)
    }

    func saveToken(_ token: String, profileID: UUID) throws {}
    func clearToken(profileID: UUID) throws {}
    func deleteToken(profileID: UUID) throws {}
}

private final class MemoryKeychainItemBackend: KeychainItemBackend, @unchecked Sendable {
    var values: [String: String] = [:]
    var readFailures: [String: KeychainError] = [:]
    var upsertFailures: [String: KeychainError] = [:]
    var deleteFailures: [String: KeychainError] = [:]

    func read(service: String, profileID: UUID, allowAuthenticationUI: Bool) throws -> String? {
        if let failure = readFailures[service] {
            throw failure
        }
        return values[service]
    }

    func upsert(_ value: String, service: String, profileID: UUID) throws {
        if let failure = upsertFailures[service] {
            throw failure
        }
        values[service] = value
    }

    func delete(service: String, profileID: UUID) throws {
        if let failure = deleteFailures[service] {
            throw failure
        }
        values.removeValue(forKey: service)
    }
}

private final class MemoryCredentialNamespaceStore: CredentialNamespaceStore, @unchecked Sendable {
    private var services: [UUID: String] = [:]

    func service(profileID: UUID) -> String? {
        services[profileID]
    }

    func selectService(_ service: String?, profileID: UUID) {
        services[profileID] = service
    }
}

private struct DashboardTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.value(forHTTPHeaderField: "Authorization") == nil,
              request.value(forHTTPHeaderField: "X-Api-Token") == nil else {
            throw RuntimeTestError.failure("Unexpected authentication header")
        }

        let json: String
        switch request.url?.path {
        case "/sync/state":
            json = #"{"database_id":"db","schema_version":1,"last_event_seq":0,"message_count":0}"#
        case "/manage/capabilities":
            json = #"{"mode":"single_user","management":[]}"#
        case "/sync/messages":
            json = #"{"items":[]}"#
        case "/manage/operation-events":
            json = #"{"items":[]}"#
        default:
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        return try response(for: request, json: json)
    }
}

private struct FailIfCalledTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw RuntimeTestError.failure("Transport should not be called without a remote profile token")
    }
}

private struct PrivateSearchTransport: CoreHTTPTransport {
    var expectedToken: String
    var expectedQuery: String

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expectedToken)" else {
            throw RuntimeTestError.failure("Expected bearer authentication header")
        }
        guard request.url?.path == "/sync/search",
              queryValues(request)["q"] == [expectedQuery] else {
            throw RuntimeTestError.failure("Expected private search query")
        }
        return try response(for: request, json: #"{"items":[]}"#)
    }
}

private struct AccountMutationThenRefreshFailureTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.path == "/manage/accounts" else {
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        if request.httpMethod == "POST" {
            return try response(
                for: request,
                json: #"{"item":{"source":"telegram","account_id":"created","display_name":"Created"}}"#
            )
        }
        throw RuntimeTestError.failure("Synthetic account refresh failure")
    }
}

private actor PartialArchiveTransport: CoreHTTPTransport {
    private var archiveRequests = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.path == "/manage/origins" || request.url?.path == "/manage/origins/archive" else {
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        if request.url?.path == "/manage/origins/archive" {
            archiveRequests += 1
            if archiveRequests == 1 {
                return try response(
                    for: request,
                    json: #"{"item":{"source":"telegram","account_id":"main","origin_id":100,"topic_id":0,"archived":true,"changed_rows":1}}"#
                )
            }
            throw RuntimeTestError.failure("Synthetic second archive failure")
        }
        throw RuntimeTestError.failure("Synthetic partial refresh failure")
    }
}

private actor DelayedAccountsTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(100))
        guard request.url?.path == "/manage/accounts" else {
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        return try response(
            for: request,
            json: #"{"items":[{"source":"telegram","account_id":"old","display_name":"Old Core"}]}"#
        )
    }
}

private actor ReorderedSearchTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.path == "/sync/search",
              let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false),
              let query = components.queryItems?.first(where: { $0.name == "q" })?.value else {
            throw RuntimeTestError.failure("Unexpected search request")
        }
        try await Task.sleep(for: query == "slow" ? .milliseconds(100) : .milliseconds(10))
        if query == "slow" {
            throw RuntimeTestError.failure("Synthetic stale search failure")
        }
        return try response(
            for: request,
            json:
                """
                {"items":[{"source":"telegram","account_id":"main","chat_id":-1001,"message_id":2,"text":"\(query)","has_media":false}]}
                """
        )
    }
}

private struct CapabilityBootstrapTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let json: String
        switch request.url?.path {
        case "/manage/api-manifest":
            json = #"{"contract_version":"test","contract_hash":"hash","endpoints":[{"path":"/manage/accounts"}]}"#
        case "/manage/capabilities":
            json = #"{"mode":"single_user","management":["accounts"]}"#
        case "/sync/state":
            json = #"{"database_id":"db","schema_version":1,"last_event_seq":0,"message_count":0}"#
        case "/sync/messages", "/manage/operation-events":
            json = #"{"items":[]}"#
        default:
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        return try response(for: request, json: json)
    }
}

private actor MessagePointRuntimeTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let json: String
        switch request.url?.path {
        case "/manage/api-manifest":
            json = #"{"contract_version":"test","contract_hash":"hash","endpoints":[{"path":"/manage/daily-message-points"}]}"#
        case "/manage/capabilities":
            json = #"{"mode":"single_user","management":["daily_message_points"]}"#
        case "/manage/daily-message-points":
            let values = queryValues(request)
            try expectEqual(values["q"], ["needle"])
            try expectEqual(values["date"], ["2026-07-11"])
            try expectEqual(values["tag"], ["ops", "ai"])
            try expectEqual(values["account_id"], ["main"])
            try expectEqual(values["origin_id"], ["-1001"])
            try expectEqual(values["importance_min"], ["3"])
            try expectEqual(values["importance_max"], ["5"])
            try expectEqual(values["origin_important"], ["true"])
            try expectEqual(values["include_incomplete"], ["false"])
            try expectEqual(values["limit"], ["1000"])
            json = #"{"items":[{"point_id":"point-1","run_id":"run-1","package_run_id":"package-1","date":"2026-07-11","timezone":"Asia/Tokyo","source":"telegram","account_id":"main","origin_id":-1001,"topic_id":0,"origin_title":"Ops","message_id":42,"occurred_at":"2026-07-11T09:00:00+09:00","tags":["ops","ai"],"content":"List content","telegram_deeplink":"tg://privatepost?channel=1&post=42","permalink":"https://t.me/c/1/42","importance_score":4,"importance_reason":"Operational change","origin_important":true,"source_refs":["telegram:main:-1001:42"]}]}"#
        case "/manage/daily-message-points/item":
            try expectEqual(queryValues(request)["point_id"], ["point-1"])
            json = #"{"item":{"point_id":"point-1","run_id":"run-1","package_run_id":"package-1","date":"2026-07-11","timezone":"Asia/Tokyo","source":"telegram","account_id":"main","origin_id":-1001,"topic_id":0,"origin_title":"Ops","message_id":42,"occurred_at":"2026-07-11T09:00:00+09:00","tags":["ops","ai"],"content":"Detailed content","telegram_deeplink":"tg://privatepost?channel=1&post=42","permalink":"https://t.me/c/1/42","importance_score":4,"importance_reason":"Operational change","origin_important":true,"source_refs":[{"message_id":42}]}}"#
        default:
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        return try response(for: request, json: json)
    }
}

private func queryValues(_ request: URLRequest) -> [String: [String]] {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return [:]
    }
    return Dictionary(grouping: components.queryItems ?? [], by: \.name)
        .mapValues { items in items.compactMap(\.value) }
}

private func response(for request: URLRequest, json: String) throws -> (Data, HTTPURLResponse) {
    guard let url = request.url,
          let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
        throw RuntimeTestError.failure("Could not build HTTP response")
    }
    return (Data(json.utf8), response)
}

private struct RuntimeTestRunner {
    private var failures = 0

    mutating func run(_ name: String, operation: () async throws -> Void) async {
        do {
            try await operation()
            print("PASS \(name)")
        } catch {
            failures += 1
            print("FAIL \(name): \(error)")
        }
    }

    func finish() -> Never {
        if failures == 0 {
            print("Runtime state tests passed")
            exit(0)
        }
        print("Runtime state tests failed: \(failures)")
        exit(1)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    guard actual == expected else {
        throw RuntimeTestError.failure("Expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

private func expectNil<T>(_ value: T?) throws {
    guard value == nil else {
        throw RuntimeTestError.failure("Expected nil, got \(String(describing: value))")
    }
}

private enum RuntimeTestError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case .failure(let message):
            message
        }
    }
}
