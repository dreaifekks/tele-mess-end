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
    func deleteToken(profileID: UUID) throws {}
}

private struct InteractionBlockedCredentialStore: CredentialStore {
    func readToken(profileID: UUID, allowAuthenticationUI: Bool) throws -> String? {
        throw KeychainError(status: errSecInteractionNotAllowed)
    }

    func saveToken(_ token: String, profileID: UUID) throws {}
    func deleteToken(profileID: UUID) throws {}
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
