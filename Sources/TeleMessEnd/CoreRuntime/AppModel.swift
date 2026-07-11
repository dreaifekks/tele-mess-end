import AppKit
import Foundation
import Observation

struct DashboardState {
    var coreState: CoreState?
    var capabilities: CoreCapabilities?
    var apiManifest: CoreAPIManifest?
    var recentMessages: [CoreMessage] = []
    var operationEvents: [CoreOperationEvent] = []
}

private struct CachedProfileToken {
    var profileID: UUID
    var token: String?
}

private struct CoreSessionContext {
    var profileID: UUID
    var generation: UInt64
    var client: CoreAPIClient
}

private struct DailySummaryStateSnapshot {
    var records: [DailySummaryRecord]
    var packageRuns: [DailyPackageRun]
    var summaryRuns: [DailySummaryRun]
    var jobs: [DailySummaryJob]
}

private struct PartialMutationError: LocalizedError {
    var action: String
    var completed: Int
    var total: Int
    var underlyingError: Error

    var errorDescription: String? {
        "\(action) completed for \(completed) of \(total) items before failing: \(underlyingError.localizedDescription)"
    }
}

private let recentMessageRefreshIntervalNanoseconds: UInt64 = 5 * 60 * 1_000_000_000
private let dailySummaryProgressRefreshIntervalNanoseconds: UInt64 = 10 * 1_000_000_000

private enum TokenReadMode {
    case promptIfNeeded
    case cacheOnly
}

private enum OperationScope: Hashable {
    case exclusive
    case messages
}

enum CoreValidationStatus {
    case unverified
    case validating
    case verified
    case failed

    var title: String {
        switch self {
        case .unverified:
            "Unverified"
        case .validating:
            "Validating"
        case .verified:
            "Verified"
        case .failed:
            "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .unverified, .failed:
            "xmark.seal"
        case .validating:
            "clock"
        case .verified:
            "checkmark.seal"
        }
    }
}

enum DiagnosticsSection: String, CaseIterable, Identifiable {
    case operationEvents
    case participants
    case cursors
    case media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .operationEvents:
            "Operation Events"
        case .participants:
            "Participants"
        case .cursors:
            "Capture Cursors"
        case .media:
            "Media Files"
        }
    }
}

enum MessagePointOriginImportanceFilter: String, CaseIterable, Identifiable {
    case any
    case important
    case regular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any:
            "Any origin"
        case .important:
            "Important origins"
        case .regular:
            "Regular origins"
        }
    }

    var queryValue: Bool? {
        switch self {
        case .any:
            nil
        case .important:
            true
        case .regular:
            false
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let profileStore: CoreProfileStore
    let summarySettingsStore: SummarySettingsStore
    let keychain: any CredentialStore
    let localRunner: LocalCoreProcessController
    let runtimeLogs: AppRuntimeLogStore
    @ObservationIgnored private let transport: any CoreHTTPTransport
    @ObservationIgnored private let runtimeLogger: AppRuntimeLogger
    @ObservationIgnored private let apiLogger: AppRuntimeLogger
    @ObservationIgnored private var tokenCache: CachedProfileToken?
    @ObservationIgnored private var isRecentMessageRefreshLoopRunning = false
    @ObservationIgnored private var isDailySummaryProgressLoopRunning = false
    @ObservationIgnored private var activeOperations: [UUID: OperationScope] = [:]
    @ObservationIgnored private var latestOperationIDs: [OperationScope: UUID] = [:]
    @ObservationIgnored private var messageRequestRevision: UInt64 = 0
    @ObservationIgnored private var dailySummaryRequestRevision: UInt64 = 0
    @ObservationIgnored private var compatibilityCheckedSessionRevision: UInt64?

    var selectedSection: AppSection = .dashboard
    var settingsSection: SettingsSection = .core
    private(set) var sessionRevision: UInt64 = 0
    var dashboard = DashboardState()
    var accounts: [CoreAccount] = []
    var origins: [CoreOrigin] = []
    var summaryScopeAccounts: [CoreAccount] = []
    var summaryScopeOrigins: [CoreOrigin] = []
    var messages: [CoreMessage] = []
    var dailyMessagePoints: [DailyMessagePoint] = []
    var participants: [CoreParticipant] = []
    var cursors: [CoreCaptureCursor] = []
    var mediaFiles: [CoreMediaFile] = []
    var operationEvents: [CoreOperationEvent] = []
    var dailySummaryRecords: [DailySummaryRecord] = []
    var dailyPackageRuns: [DailyPackageRun] = []
    var dailySummaryRuns: [DailySummaryRun] = []
    var dailySummaryJobs: [DailySummaryJob] = []
    var isLoading = false
    var statusMessage = "Ready"
    var lastError: String?
    var validationStatus: CoreValidationStatus = .unverified

    var originSearch = ""
    var originAccountFilter = ""
    var originTypeFilter = ""
    var originTagFilter = ""
    var originBackupFilter: OriginBackupFilter = .any
    var originSort: OriginSort = .groupTopic
    var originBackupFirst = true
    var includeArchivedOrigins = false
    var selectedOriginID: CoreOrigin.ID?

    var messageSearchQuery = ""
    var messagePointSearchQuery = ""
    var messagePointDateFilter = ""
    var messagePointTagsFilter = ""
    var messagePointAccountFilter = ""
    var messagePointOriginIDFilter = ""
    var messagePointImportanceMin = 1
    var messagePointImportanceMax = 5
    var messagePointOriginImportanceFilter: MessagePointOriginImportanceFilter = .any
    var diagnosticsSelection: DiagnosticsSection = .operationEvents
    var diagnosticsAccountFilter = ""
    var diagnosticsOriginIDFilter = ""
    var diagnosticsStatusFilter = "failed"
    var mediaAccountFilter = ""
    var mediaChatIDFilter = ""
    var mediaMessageIDFilter = ""
    var includeDeletedDailySummaryRecords = false

    init(
        profileStore: CoreProfileStore? = nil,
        summarySettingsStore: SummarySettingsStore? = nil,
        keychain: any CredentialStore = KeychainStore(),
        localRunner: LocalCoreProcessController? = nil,
        transport: any CoreHTTPTransport = URLSession.shared,
        runtimeLogs: AppRuntimeLogStore? = nil,
        runtimeLogger: AppRuntimeLogger = AppLog.runtime,
        apiLogger: AppRuntimeLogger = AppLog.api
    ) {
        let resolvedProfileStore = profileStore ?? CoreProfileStore()
        let resolvedSummarySettingsStore = summarySettingsStore ?? SummarySettingsStore()
        let resolvedRuntimeLogs = runtimeLogs ?? AppRuntimeLogStore()
        self.profileStore = resolvedProfileStore
        self.summarySettingsStore = resolvedSummarySettingsStore
        self.keychain = keychain
        self.localRunner = localRunner ?? LocalCoreProcessController(logger: runtimeLogger)
        self.transport = transport
        self.runtimeLogs = resolvedRuntimeLogs
        self.runtimeLogger = runtimeLogger
        self.apiLogger = apiLogger
        resolvedSummarySettingsStore.selectProfile(resolvedProfileStore.selectedProfileID)
        resolvedRuntimeLogs.startMonitoring()
        let profileSuffix = resolvedProfileStore.selectedProfileID.map { String($0.uuidString.suffix(8)) } ?? "none"
        runtimeLogger.info("App model initialized profileSuffix=\(profileSuffix)")
    }

    var selectedProfile: CoreProfile? {
        profileStore.selectedProfile
    }

    var availableSections: [AppSection] {
        guard let manifest = dashboard.apiManifest else {
            return AppSection.allCases
        }
        let paths = Set(manifest.endpoints.compactMap { endpoint -> String? in
            switch endpoint {
            case .string(let path):
                return path
            case .object(let value):
                guard case .string(let path)? = value["path"] else { return nil }
                return path
            default:
                return nil
            }
        })
        return AppSection.allCases.filter { section in
            guard let requiredEndpointPath = section.requiredEndpointPath else { return true }
            return paths.contains(requiredEndpointPath)
        }
    }

    func selectProfile(_ id: UUID?) {
        let resolvedID: UUID?
        if let id, profileStore.profiles.contains(where: { $0.id == id }) {
            resolvedID = id
        } else {
            resolvedID = profileStore.profiles.first?.id
        }
        guard profileStore.selectedProfileID != resolvedID else { return }
        profileStore.select(resolvedID)
        let profileSuffix = resolvedID.map { String($0.uuidString.suffix(8)) } ?? "none"
        runtimeLogger.info("Profile selected profileSuffix=\(profileSuffix)")
        beginProfileSession()
    }

    @discardableResult
    func addRemoteProfile() -> CoreProfile {
        let profile = profileStore.addRemoteProfile()
        runtimeLogger.info("Remote profile added profileSuffix=\(String(profile.id.uuidString.suffix(8)))")
        beginProfileSession()
        return profile
    }

    @discardableResult
    func addLocalProfile() -> CoreProfile {
        let profile = profileStore.addLocalProfile()
        runtimeLogger.info("Local profile added profileSuffix=\(String(profile.id.uuidString.suffix(8)))")
        beginProfileSession()
        return profile
    }

    var selectedOrigin: CoreOrigin? {
        guard let selectedOriginID else { return nil }
        return origins.first { $0.id == selectedOriginID }
    }

    var activeDailySummaryJob: DailySummaryJob? {
        dailySummaryJobs.first { $0.isActive }
    }

    var latestDailySummaryJob: DailySummaryJob? {
        activeDailySummaryJob ?? dailySummaryJobs.first
    }

    var matchingOrigins: [CoreOrigin] {
        origins.filter { origin in
            if !originAccountFilter.isEmpty && !origin.accountID.localizedCaseInsensitiveContains(originAccountFilter) {
                return false
            }
            if !originTypeFilter.isEmpty && origin.originType != originTypeFilter {
                return false
            }
            switch originBackupFilter {
            case .any:
                break
            case .enabled:
                if origin.backupPolicy?.enabled != true { return false }
            case .disabled:
                if origin.backupPolicy?.enabled == true { return false }
            case .missingPolicy:
                if origin.backupPolicy != nil { return false }
            }
            if !originTagFilter.isEmpty {
                let tags = origin.backupPolicy?.tags ?? ""
                if !tags.localizedCaseInsensitiveContains(originTagFilter) {
                    return false
                }
            }
            if !originSearch.isEmpty {
                let haystack = [
                    origin.displayTitle,
                    origin.username ?? "",
                    "\(origin.originID)",
                    "\(origin.topicID)"
                ].joined(separator: " ")
                if !haystack.localizedCaseInsensitiveContains(originSearch) {
                    return false
                }
            }
            return true
        }
    }

    var filteredOrigins: [CoreOrigin] {
        let filtered = matchingOrigins
        return sortOrigins(filtered)
    }

    func refreshCurrentSection(allowKeychainUI: Bool = true) async {
        switch selectedSection {
        case .dashboard:
            await loadDashboard(allowKeychainUI: allowKeychainUI)
        case .accounts:
            await loadAccounts(allowKeychainUI: allowKeychainUI)
        case .origins:
            await loadOrigins(allowKeychainUI: allowKeychainUI)
        case .messages:
            await loadRecentMessages(allowKeychainUI: allowKeychainUI)
        case .messagePoints:
            await loadDailyMessagePoints(allowKeychainUI: allowKeychainUI)
        case .media:
            await loadMediaFiles(allowKeychainUI: allowKeychainUI)
        case .summaries:
            await refreshDailySummaryProgress(allowKeychainUI: allowKeychainUI)
        case .diagnostics:
            await loadDiagnostics(allowKeychainUI: allowKeychainUI)
        }
    }

    func refreshCurrentSectionWhenIdle(allowKeychainUI: Bool = true) async {
        while isLoading {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        guard await ensureCompatibility(allowKeychainUI: allowKeychainUI),
              !Task.isCancelled else { return }
        await refreshCurrentSection(allowKeychainUI: allowKeychainUI)
    }

    func runRecentMessageRefreshLoop() async {
        guard !isRecentMessageRefreshLoopRunning else { return }
        isRecentMessageRefreshLoopRunning = true
        defer { isRecentMessageRefreshLoopRunning = false }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: recentMessageRefreshIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            await refreshRecentMessagesInBackground()
        }
    }

    func runDailySummaryProgressLoop() async {
        guard !isDailySummaryProgressLoopRunning else { return }
        isDailySummaryProgressLoopRunning = true
        defer { isDailySummaryProgressLoopRunning = false }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: dailySummaryProgressRefreshIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            guard activeDailySummaryJob != nil else { continue }
            await refreshDailySummaryProgressInBackground()
        }
    }

    func validateActiveProfile() async {
        guard validationStatus != .validating else { return }
        let validationRevision = sessionRevision
        validationStatus = .validating
        while isLoading {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                if validationRevision == sessionRevision, validationStatus == .validating {
                    validationStatus = .unverified
                }
                return
            }
        }
        guard validationRevision == sessionRevision else { return }
        guard !Task.isCancelled else {
            validationStatus = .unverified
            return
        }
        let succeeded = await withLoading("Validating profile") { session in
            let messageRevision = beginMessageRequest()
            _ = try await session.client.health()
            let snapshot = try await fetchDashboardSnapshot(using: session.client)
            try ensureCurrent(session)
            applyDashboardSnapshot(snapshot, messageRevision: messageRevision)
            compatibilityCheckedSessionRevision = validationRevision
            validationStatus = .verified
            statusMessage = "Connected to \(selectedProfile?.name ?? "core")"
        }
        if !succeeded, validationStatus == .validating {
            validationStatus = Task.isCancelled ? .unverified : .failed
        } else if succeeded, selectedSection != .dashboard {
            await refreshCurrentSectionWhenIdle(allowKeychainUI: true)
        }
    }

    func loadDashboard(allowKeychainUI: Bool = true) async {
        let tokenReadMode: TokenReadMode = allowKeychainUI ? .promptIfNeeded : .cacheOnly
        await withLoading("Loading dashboard", tokenReadMode: tokenReadMode) { session in
            let messageRevision = beginMessageRequest()
            let snapshot = try await fetchDashboardSnapshot(using: session.client)
            try ensureCurrent(session)
            applyDashboardSnapshot(snapshot, messageRevision: messageRevision)
            statusMessage = "Dashboard refreshed"
        }
    }

    func refreshRecentMessagesInBackground() async {
        guard !isLoading else { return }
        let requestRevision = beginMessageRequest()
        do {
            let session = try makeSession(tokenReadMode: .cacheOnly)
            let loadedMessages = try await session.client.fetchRecentMessages(limit: 100, includeMedia: true).items
            try ensureCurrent(session, messageRevision: requestRevision)
            dashboard.recentMessages = loadedMessages
            if messageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages = loadedMessages
            }
        } catch is CancellationError {
            return
        } catch {
            runtimeLogger.warning("Background recent messages refresh failed error=\(safeRuntimeErrorSummary(error))")
            return
        }
    }

    func loadAccounts(allowKeychainUI: Bool = true) async {
        await withLoading(
            "Loading accounts",
            tokenReadMode: allowKeychainUI ? .promptIfNeeded : .cacheOnly
        ) { session in
            let loadedAccounts = try await session.client.listManagementAccounts()
            try ensureCurrent(session)
            accounts = loadedAccounts
            statusMessage = "Loaded \(accounts.count) accounts"
        }
    }

    @discardableResult
    func createAccount(_ request: CreateAccountRequest) async -> Bool {
        await withLoading("Saving account") { session in
            let createdAccount = try await session.client.createAccount(request)
            try ensureCurrent(session)
            upsertAccount(createdAccount)
            let refreshed = try await refreshAccountsIfAvailable(using: session)
            statusMessage = refreshed ? "Account saved" : "Account saved; refresh pending"
        }
    }

    @discardableResult
    func deleteAccount(_ account: CoreAccount) async -> Bool {
        await withLoading("Deleting account") { session in
            _ = try await session.client.deleteAccount(accountID: account.accountID, source: account.source)
            try ensureCurrent(session)
            accounts.removeAll { $0.id == account.id }
            let refreshed = try await refreshAccountsIfAvailable(using: session)
            statusMessage = refreshed ? "Account metadata deleted" : "Account deleted; refresh pending"
        }
    }

    @discardableResult
    func authStatus(accountID: String) async -> Bool {
        await withLoading("Checking auth") { session in
            let result = try await session.client.authStatus(accountID: accountID)
            try ensureCurrent(session)
            let refreshed = try await refreshAccountsIfAvailable(using: session)
            let message = result.status ?? result.authState ?? "Auth status updated"
            statusMessage = refreshed ? message : "\(message); refresh pending"
        }
    }

    @discardableResult
    func requestCode(accountID: String, phone: String) async -> Bool {
        await withLoading("Requesting code") { session in
            let result = try await session.client.requestCode(accountID: accountID, phone: phone)
            try ensureCurrent(session)
            let refreshed = try await refreshAccountsIfAvailable(using: session)
            let message = result.message ?? result.status ?? "Code requested"
            statusMessage = refreshed ? message : "\(message); refresh pending"
        }
    }

    @discardableResult
    func submitCode(accountID: String, phone: String, code: String, password: String?) async -> Bool {
        await withLoading("Submitting code") { session in
            let result = try await session.client.submitCode(accountID: accountID, phone: phone, code: code, password: password?.nilIfEmpty)
            try ensureCurrent(session)
            let refreshed = try await refreshAccountsIfAvailable(using: session)
            let message = result.message ?? result.status ?? result.authState ?? "Code submitted"
            statusMessage = refreshed ? message : "\(message); refresh pending"
        }
    }

    func loadOrigins(allowKeychainUI: Bool = true) async {
        await withLoading(
            "Loading origins",
            tokenReadMode: allowKeychainUI ? .promptIfNeeded : .cacheOnly
        ) { session in
            let loadedOrigins = try await session.client.listOrigins(
                accountID: originAccountFilter.nilIfEmpty,
                includeArchived: includeArchivedOrigins
            )
            try ensureCurrent(session)
            origins = loadedOrigins
            if selectedOriginID == nil {
                selectedOriginID = origins.first?.id
            }
            statusMessage = "Loaded \(origins.count) origins"
        }
    }

    func discoverOrigins(accountID: String) async {
        await withLoading("Discovering origins") { session in
            let result = try await session.client.discoverOrigins(accountID: accountID, includeTopics: true, includePrivate: false, topicLimit: 500)
            try ensureCurrent(session)
            let refreshed = try await refreshOriginsIfAvailable(using: session)
            let message = result.message ?? "Discovery finished"
            statusMessage = refreshed ? message : "\(message); refresh pending"
        }
    }

    func loadSummaryScopeOptions() async {
        await withLoading("Loading summary scope options") { session in
            async let accountsRequest = session.client.listManagementAccounts()
            async let originsRequest = session.client.listOrigins(accountID: nil, includeArchived: false)
            let snapshot = try await (accountsRequest, originsRequest)
            try ensureCurrent(session)
            summaryScopeAccounts = snapshot.0
            summaryScopeOrigins = snapshot.1
            statusMessage = "Loaded summary scope options"
        }
    }

    func discoverSummaryScopeOptions(accountID: String) async {
        await withLoading("Discovering summary delivery targets") { session in
            let result = try await session.client.discoverOrigins(accountID: accountID, includeTopics: true, includePrivate: false, topicLimit: 500)
            try ensureCurrent(session)
            let refreshed = try await refreshSummaryScopeIfAvailable(using: session)
            let message = result.message ?? "Summary delivery targets refreshed"
            statusMessage = refreshed ? message : "\(message); refresh pending"
        }
    }

    @discardableResult
    func archiveOrigins(_ selectedOrigins: [CoreOrigin], archived: Bool) async -> Bool {
        let targets = affectedOrigins(for: selectedOrigins)
        guard !targets.isEmpty else { return false }
        return await withLoading(archived ? "Archiving origin" : "Restoring origin") { session in
            var completed = 0
            do {
                for origin in targets {
                    _ = try await session.client.archiveOrigin(
                        ArchiveOriginRequest(
                            accountID: origin.accountID,
                            originID: origin.originID,
                            topicID: origin.topicID,
                            archived: archived,
                            source: origin.source
                        )
                    )
                    try ensureCurrent(session)
                    applyArchiveLocally(origin, archived: archived)
                    completed += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if completed > 0 {
                    _ = try? await refreshOriginsIfAvailable(using: session)
                    throw PartialMutationError(
                        action: archived ? "Archive" : "Restore",
                        completed: completed,
                        total: targets.count,
                        underlyingError: error
                    )
                }
                throw error
            }
            try ensureCurrent(session)
            let refreshed = try await refreshOriginsIfAvailable(using: session)
            let message = archived ? "Origin archived" : "Origin restored"
            statusMessage = refreshed ? message : "\(message); refresh pending"
        }
    }

    @discardableResult
    func savePolicy(for origin: CoreOrigin, policy: CoreBackupPolicy) async -> Bool {
        let targets = affectedOrigins(for: [origin])
        return await withLoading("Saving policy") { session in
            var completed = 0
            do {
                for target in targets {
                    let updatedPolicy = try await session.client.setBackupPolicy(
                        BackupPolicyRequest(
                            accountID: target.accountID,
                            originID: target.originID,
                            topicID: target.topicID,
                            enabled: policy.enabled,
                            captureText: policy.captureText,
                            captureMediaMetadata: policy.captureMediaMetadata,
                            downloadMedia: policy.downloadMedia,
                            tags: policy.tags,
                            source: target.source
                        )
                    )
                    try ensureCurrent(session)
                    if let index = origins.firstIndex(where: { $0.id == target.id }) {
                        origins[index].backupPolicy = updatedPolicy
                    }
                    completed += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if completed > 0 {
                    _ = try? await refreshOriginsIfAvailable(using: session)
                    throw PartialMutationError(
                        action: "Policy save",
                        completed: completed,
                        total: targets.count,
                        underlyingError: error
                    )
                }
                throw error
            }
            try ensureCurrent(session)
            let refreshed = try await refreshOriginsIfAvailable(using: session)
            statusMessage = refreshed ? "Policy saved" : "Policy saved; refresh pending"
        }
    }

    @discardableResult
    func setOriginImportant(_ origin: CoreOrigin, important: Bool) async -> Bool {
        await withLoading(important ? "Marking important" : "Clearing important") { session in
            let updated = try await session.client.setOriginImportant(
                OriginImportantRequest(
                    accountID: origin.accountID,
                    originID: origin.originID,
                    topicID: origin.topicID,
                    important: important,
                    source: origin.source
                )
            )
            try ensureCurrent(session)
            replaceOrigin(updated)
            statusMessage = important ? "Origin marked important" : "Origin unmarked"
        }
    }

    func loadRecentMessages(allowKeychainUI: Bool = true) async {
        await withLoading(
            "Loading messages",
            tokenReadMode: allowKeychainUI ? .promptIfNeeded : .cacheOnly,
            scope: .messages
        ) { session in
            let requestRevision = beginMessageRequest()
            let loadedMessages = try await session.client.fetchRecentMessages(limit: 100, includeMedia: true).items
            try ensureCurrent(session, messageRevision: requestRevision)
            messages = loadedMessages
            dashboard.recentMessages = loadedMessages
            statusMessage = "Loaded recent messages"
        }
    }

    func searchMessages() async {
        let query = messageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            await loadRecentMessages()
            return
        }
        await withLoading("Searching messages", scope: .messages) { session in
            let requestRevision = beginMessageRequest()
            let loadedMessages = try await session.client.searchMessages(query: query, limit: 100, includeMedia: true)
            try ensureCurrent(session, messageRevision: requestRevision)
            messages = loadedMessages
            statusMessage = "Search returned \(messages.count) messages"
        }
    }

    func loadDailyMessagePoints(allowKeychainUI: Bool = true) async {
        await withLoading(
            "Loading message points",
            tokenReadMode: allowKeychainUI ? .promptIfNeeded : .cacheOnly
        ) { session in
            let minimumImportance = min(messagePointImportanceMin, messagePointImportanceMax)
            let maximumImportance = max(messagePointImportanceMin, messagePointImportanceMax)
            let tags = messagePointTagsFilter
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let loadedPoints = try await session.client.listDailyMessagePoints(
                date: messagePointDateFilter.nilIfEmpty,
                accountID: messagePointAccountFilter.nilIfEmpty,
                originID: Int(messagePointOriginIDFilter),
                tags: tags,
                importanceMin: minimumImportance,
                importanceMax: maximumImportance,
                originImportant: messagePointOriginImportanceFilter.queryValue,
                query: messagePointSearchQuery.nilIfEmpty,
                includeIncomplete: false,
                limit: 1_000
            )
            try ensureCurrent(session)
            dailyMessagePoints = sortDailyMessagePoints(loadedPoints)
            statusMessage = dailyMessagePoints.count == 1_000
                ? "Loaded 1,000 completed message points (limit reached)"
                : "Loaded \(dailyMessagePoints.count) completed message points"
        }
    }

    @discardableResult
    func loadDailyMessagePoint(_ point: DailyMessagePoint) async -> Bool {
        await withLoading("Loading message point") { session in
            let loaded = try await session.client.fetchDailyMessagePoint(pointID: point.pointID)
            try ensureCurrent(session)
            if let index = dailyMessagePoints.firstIndex(where: { $0.pointID == loaded.pointID }) {
                dailyMessagePoints[index] = loaded
            } else {
                dailyMessagePoints.append(loaded)
                dailyMessagePoints = sortDailyMessagePoints(dailyMessagePoints)
            }
            statusMessage = "Loaded message point"
        }
    }

    func clearDailyMessagePointFilters() {
        messagePointSearchQuery = ""
        messagePointDateFilter = ""
        messagePointTagsFilter = ""
        messagePointAccountFilter = ""
        messagePointOriginIDFilter = ""
        messagePointImportanceMin = 1
        messagePointImportanceMax = 5
        messagePointOriginImportanceFilter = .any
    }

    func loadMediaFiles(allowKeychainUI: Bool = true) async {
        await withLoading(
            "Loading media",
            tokenReadMode: allowKeychainUI ? .promptIfNeeded : .cacheOnly
        ) { session in
            let loadedMediaFiles = try await session.client.listMediaFiles(
                accountID: mediaAccountFilter.nilIfEmpty,
                chatID: Int(mediaChatIDFilter),
                messageID: Int(mediaMessageIDFilter),
                limit: 500
            )
            try ensureCurrent(session)
            mediaFiles = loadedMediaFiles
            statusMessage = "Loaded \(mediaFiles.count) media files"
        }
    }

    func showMedia(for message: CoreMessage) {
        mediaAccountFilter = message.accountID
        mediaChatIDFilter = String(message.chatID)
        mediaMessageIDFilter = String(message.messageID)
        selectedSection = .media
    }

    func openMediaFile(_ file: CoreMediaFile) async {
        await withLoading("Opening media") { session in
            let data = try await session.client.downloadMediaContent(for: file)
            try ensureCurrent(session)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TeleMessEndMedia", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file.suggestedFilename)
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
            statusMessage = "Opened \(file.suggestedFilename)"
        }
    }

    func fetchMediaContent(_ file: CoreMediaFile) async throws -> Data {
        let session = try makeSession()
        let data = try await session.client.downloadMediaContent(for: file)
        try ensureCurrent(session)
        return data
    }

    @discardableResult
    func loadSummarySchedule() async -> Bool {
        await withLoading("Loading summary schedule") { session in
            let requestRevision = beginDailySummaryRequest()
            let fallback = summarySettingsStore.settings
            let schedule = try await session.client.fetchDailyPackageSchedule()
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            summarySettingsStore.save(SummarySettings(schedule: schedule, preservingDeliveryFrom: fallback))
            statusMessage = schedule.enabled ? "Summary schedule enabled" : "Summary schedule loaded"
        }
    }

    @discardableResult
    func saveSummarySchedule(_ settings: SummarySettings) async -> Bool {
        await withLoading("Saving summary schedule") { session in
            let requestRevision = beginDailySummaryRequest()
            let schedule = try await session.client.updateDailyPackageSchedule(settings.scheduleInput)
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            summarySettingsStore.save(SummarySettings(schedule: schedule, preservingDeliveryFrom: settings))
            statusMessage = "Summary schedule saved"
        }
    }

    func loadDailySummaries() async {
        await withLoading("Loading daily summaries") { session in
            let requestRevision = beginDailySummaryRequest()
            let snapshot = try await fetchDailySummarySnapshot(using: session.client)
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            applyDailySummarySnapshot(snapshot)
            statusMessage = "Loaded \(dailySummaryRecords.count) summary records"
        }
    }

    @discardableResult
    func runDailyPackageAndSummary() async -> Bool {
        await withLoading("Starting daily analysis") { session in
            let requestRevision = beginDailySummaryRequest()
            let settings = summarySettingsStore.settings
            let job = try await session.client.runDailySummaryJob(settings.summaryRunInput)
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            dailySummaryJobs = upsertDailySummaryJob(job, into: dailySummaryJobs)
            let refreshed = try await refreshDailySummarySnapshotIfAvailable(
                using: session,
                requestRevision: requestRevision
            )
            if !refreshed || !dailySummaryJobs.contains(where: { $0.jobID == job.jobID }) {
                dailySummaryJobs = upsertDailySummaryJob(job, into: dailySummaryJobs)
            }
            statusMessage = refreshed ? "Daily analysis \(job.status)" : "Daily analysis \(job.status); refresh pending"
        }
    }

    func refreshDailySummaryProgress(allowKeychainUI: Bool = true) async {
        await withLoading(
            "Refreshing daily analysis",
            tokenReadMode: allowKeychainUI ? .promptIfNeeded : .cacheOnly
        ) { session in
            let requestRevision = beginDailySummaryRequest()
            let snapshot = try await fetchDailySummarySnapshot(using: session.client)
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            applyDailySummarySnapshot(snapshot)
            if let job = latestDailySummaryJob {
                statusMessage = "Daily analysis \(job.status)"
            } else {
                statusMessage = "Daily analysis refreshed"
            }
        }
    }

    func refreshDailySummaryProgressInBackground() async {
        guard !isLoading else { return }
        let requestRevision = beginDailySummaryRequest()

        do {
            let session = try makeSession(tokenReadMode: .cacheOnly)
            let snapshot = try await fetchDailySummarySnapshot(using: session.client)
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            applyDailySummarySnapshot(snapshot)
        } catch is CancellationError {
            return
        } catch {
            runtimeLogger.warning("Background daily summary refresh failed error=\(safeRuntimeErrorSummary(error))")
            return
        }
    }

    func cancelDailySummaryJob(_ job: DailySummaryJob? = nil) async {
        guard let target = job ?? activeDailySummaryJob ?? latestDailySummaryJob else {
            statusMessage = "No daily analysis job to cancel"
            lastError = nil
            return
        }

        await withLoading("Cancelling daily analysis") { session in
            let requestRevision = beginDailySummaryRequest()
            let cancelled = try await session.client.cancelDailySummaryJob(jobID: target.jobID)
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            dailySummaryJobs = upsertDailySummaryJob(cancelled, into: dailySummaryJobs)
            let refreshed = try await refreshDailySummarySnapshotIfAvailable(
                using: session,
                requestRevision: requestRevision
            )
            if !refreshed || !dailySummaryJobs.contains(where: { $0.jobID == cancelled.jobID }) {
                dailySummaryJobs = upsertDailySummaryJob(cancelled, into: dailySummaryJobs)
            }
            statusMessage = refreshed ? "Daily analysis \(cancelled.status)" : "Daily analysis \(cancelled.status); refresh pending"
        }
    }

    func loadDailySummaryRecordContent(_ record: DailySummaryRecord) async {
        await withLoading("Loading summary content") { session in
            let loaded = try await session.client.fetchDailySummaryRecord(
                summaryID: record.summaryID,
                recordType: record.recordType,
                includeDeleted: includeDeletedDailySummaryRecords || record.deleted == true
            )
            try ensureCurrent(session)
            if let index = dailySummaryRecords.firstIndex(where: { $0.summaryID == loaded.summaryID }) {
                dailySummaryRecords[index] = loaded
            } else {
                dailySummaryRecords.insert(loaded, at: 0)
            }
            statusMessage = "Loaded summary content"
        }
    }

    @discardableResult
    func deleteDailySummaryRecords(_ records: [DailySummaryRecord]) async -> Bool {
        let summaryIDs = records.map(\.summaryID)
        guard !summaryIDs.isEmpty else { return false }

        return await withLoading("Deleting summary records") { session in
            let requestRevision = beginDailySummaryRequest()
            let includeDeleted = includeDeletedDailySummaryRecords
            let result = try await session.client.deleteDailySummaryRecords(summaryIDs: summaryIDs)
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            if includeDeleted {
                for index in dailySummaryRecords.indices where summaryIDs.contains(dailySummaryRecords[index].summaryID) {
                    dailySummaryRecords[index].deleted = true
                }
            } else {
                dailySummaryRecords.removeAll { summaryIDs.contains($0.summaryID) }
            }
            let refreshed = try await refreshDailySummarySnapshotIfAvailable(
                using: session,
                requestRevision: requestRevision
            )
            let message = "Deleted \(result.changedRows) summary records"
            statusMessage = refreshed ? message : "\(message); refresh pending"
        }
    }

    @discardableResult
    func restoreDailySummaryRecords(_ records: [DailySummaryRecord]) async -> Bool {
        let summaryIDs = records.map(\.summaryID)
        guard !summaryIDs.isEmpty else { return false }

        return await withLoading("Restoring summary records") { session in
            let requestRevision = beginDailySummaryRequest()
            let result = try await session.client.restoreDailySummaryRecords(summaryIDs: summaryIDs)
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            for index in dailySummaryRecords.indices where summaryIDs.contains(dailySummaryRecords[index].summaryID) {
                dailySummaryRecords[index].deleted = false
                dailySummaryRecords[index].deletedAt = nil
            }
            let refreshed = try await refreshDailySummarySnapshotIfAvailable(
                using: session,
                requestRevision: requestRevision
            )
            let message = "Restored \(result.changedRows) summary records"
            statusMessage = refreshed ? message : "\(message); refresh pending"
        }
    }

    func loadDiagnostics(allowKeychainUI: Bool = true) async {
        await withLoading(
            "Loading diagnostics",
            tokenReadMode: allowKeychainUI ? .promptIfNeeded : .cacheOnly
        ) { session in
            let selection = diagnosticsSelection
            switch selection {
            case .operationEvents:
                let loadedEvents = try await session.client.listOperationEvents(
                    accountID: diagnosticsAccountFilter.nilIfEmpty,
                    status: diagnosticsStatusFilter.nilIfEmpty,
                    limit: 100
                )
                try ensureCurrent(session)
                guard diagnosticsSelection == selection else { throw CancellationError() }
                operationEvents = loadedEvents
            case .participants:
                let loadedParticipants = try await session.client.listParticipants(
                    accountID: diagnosticsAccountFilter.nilIfEmpty,
                    originID: Int(diagnosticsOriginIDFilter)
                )
                try ensureCurrent(session)
                guard diagnosticsSelection == selection else { throw CancellationError() }
                participants = loadedParticipants
            case .cursors:
                let loadedCursors = try await session.client.listCaptureCursors(accountID: diagnosticsAccountFilter.nilIfEmpty)
                try ensureCurrent(session)
                guard diagnosticsSelection == selection else { throw CancellationError() }
                cursors = loadedCursors
            case .media:
                let loadedMediaFiles = try await session.client.listMediaFiles(accountID: diagnosticsAccountFilter.nilIfEmpty, limit: 500)
                try ensureCurrent(session)
                guard diagnosticsSelection == selection else { throw CancellationError() }
                mediaFiles = loadedMediaFiles
            }
            statusMessage = "Diagnostics loaded"
        }
    }

    @discardableResult
    func deleteOperationEvent(_ event: CoreOperationEvent) async -> Bool {
        await withLoading("Deleting operation event") { session in
            _ = try await session.client.deleteOperationEvent(id: event.id)
            try ensureCurrent(session)
            operationEvents.removeAll { $0.id == event.id }
            let refreshed = try await refreshOperationEventsIfAvailable(using: session)
            statusMessage = refreshed ? "Operation event deleted" : "Operation event deleted; refresh pending"
        }
    }

    func refreshParticipants(accountID: String, originID: Int) async {
        var needsReload = false
        let selectionWillChange = diagnosticsSelection != .participants
        let succeeded = await withLoading("Refreshing participants") { session in
            _ = try await session.client.refreshParticipants(accountID: accountID, originID: originID, limit: 500)
            try ensureCurrent(session)
            let refreshed = try await refreshParticipantsIfAvailable(
                using: session,
                accountID: accountID,
                originID: originID
            )
            diagnosticsSelection = .participants
            needsReload = !refreshed
            statusMessage = refreshed ? "Participants refreshed" : "Participants refreshed; list reload pending"
        }
        if succeeded, needsReload, !selectionWillChange {
            await loadDiagnostics()
        }
    }

    @discardableResult
    func saveProfile(_ profile: CoreProfile, token: String?) -> Bool {
        let profileSuffix = String(profile.id.uuidString.suffix(8))
        let credentialAction: String
        if let token {
            credentialAction = token.isEmpty ? "clear" : "replace"
        } else {
            credentialAction = "unchanged"
        }
        runtimeLogger.info("Profile save begin profileSuffix=\(profileSuffix) credential=\(credentialAction)")
        do {
            if let token {
                if token.isEmpty {
                    try keychain.clearToken(profileID: profile.id)
                } else {
                    try keychain.saveToken(token, profileID: profile.id)
                }
            }
            profileStore.upsert(profile)
            beginProfileSession()
            if let savedToken = token?.nilIfEmpty {
                tokenCache = CachedProfileToken(profileID: profile.id, token: savedToken)
            } else if profile.kind == .local, token != nil {
                tokenCache = CachedProfileToken(profileID: profile.id, token: nil)
            }
            statusMessage = "Profile saved"
            lastError = nil
            runtimeLogger.info("Profile save end profileSuffix=\(profileSuffix) result=success")
            return true
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed"
            runtimeLogger.error("Profile save end profileSuffix=\(profileSuffix) result=failure error=\(safeRuntimeErrorSummary(error))")
            return false
        }
    }

    @discardableResult
    func deleteSelectedProfile() -> Bool {
        guard let removed = profileStore.deleteSelected() else { return false }
        let profileSuffix = String(removed.id.uuidString.suffix(8))
        runtimeLogger.info("Profile delete begin profileSuffix=\(profileSuffix)")
        beginProfileSession()
        summarySettingsStore.removeProfile(removed.id)
        do {
            try keychain.deleteToken(profileID: removed.id)
            statusMessage = "Profile deleted"
            lastError = nil
            runtimeLogger.info("Profile delete end profileSuffix=\(profileSuffix) result=success")
            return true
        } catch {
            lastError = "Profile deleted, but its saved token could not be removed: \(error.localizedDescription)"
            statusMessage = "Profile deleted"
            runtimeLogger.warning("Profile delete end profileSuffix=\(profileSuffix) result=credential_cleanup_failed error=\(safeRuntimeErrorSummary(error))")
            return true
        }
    }

    func openConsole() {
        guard let url = selectedProfile?.baseURL?.appendingPathComponent("console") else { return }
        NSWorkspace.shared.open(url)
    }

    func startLocalCore() {
        guard let profile = selectedProfile else { return }
        localRunner.start(profile: profile)
    }

    func stopLocalCore() {
        localRunner.stop()
    }

    private func beginProfileSession() {
        sessionRevision &+= 1
        messageRequestRevision &+= 1
        dailySummaryRequestRevision &+= 1
        compatibilityCheckedSessionRevision = nil
        tokenCache = nil
        activeOperations.removeAll()
        latestOperationIDs.removeAll()
        summarySettingsStore.selectProfile(selectedProfile?.id)
        resetCoreState()
    }

    private func resetCoreState() {
        dashboard = DashboardState()
        accounts = []
        origins = []
        summaryScopeAccounts = []
        summaryScopeOrigins = []
        messages = []
        dailyMessagePoints = []
        participants = []
        cursors = []
        mediaFiles = []
        operationEvents = []
        dailySummaryRecords = []
        dailyPackageRuns = []
        dailySummaryRuns = []
        dailySummaryJobs = []

        isLoading = false
        statusMessage = "Ready"
        lastError = nil
        validationStatus = .unverified

        originSearch = ""
        originAccountFilter = ""
        originTypeFilter = ""
        originTagFilter = ""
        selectedOriginID = nil
        messageSearchQuery = ""
        clearDailyMessagePointFilters()
        diagnosticsSelection = .operationEvents
        diagnosticsAccountFilter = ""
        diagnosticsOriginIDFilter = ""
        diagnosticsStatusFilter = "failed"
        mediaAccountFilter = ""
        mediaChatIDFilter = ""
        mediaMessageIDFilter = ""
        includeDeletedDailySummaryRecords = false
    }

    private func makeSession(tokenReadMode: TokenReadMode = .promptIfNeeded) throws -> CoreSessionContext {
        guard let profile = selectedProfile else {
            throw CoreAPIError.missingProfile
        }
        guard let baseURL = profile.baseURL else {
            throw CoreAPIError.invalidBaseURL(profile.baseURLString)
        }
        let token = try token(for: profile, tokenReadMode: tokenReadMode)
        return CoreSessionContext(
            profileID: profile.id,
            generation: sessionRevision,
            client: CoreAPIClient(
                baseURL: baseURL,
                tokenProvider: FixedTokenProvider(value: token),
                authMode: profile.authMode,
                transport: transport,
                logger: apiLogger
            )
        )
    }

    private func token(for profile: CoreProfile, tokenReadMode: TokenReadMode) throws -> String? {
        if let tokenCache, tokenCache.profileID == profile.id {
            if let token = tokenCache.token?.nilIfEmpty {
                return token
            }
            if profile.kind == .local {
                return nil
            }
            self.tokenCache = nil
        }

        let profileSuffix = String(profile.id.uuidString.suffix(8))
        runtimeLogger.info("Reading Keychain token profileSuffix=\(profileSuffix) allowUI=\(tokenReadMode == .promptIfNeeded)")
        do {
            let token = try keychain.readToken(
                profileID: profile.id,
                allowAuthenticationUI: tokenReadMode == .promptIfNeeded
            )
            if let token = token?.nilIfEmpty {
                tokenCache = CachedProfileToken(profileID: profile.id, token: token)
                return token
            }
            if profile.kind == .local {
                tokenCache = CachedProfileToken(profileID: profile.id, token: nil)
                return nil
            }
            throw CoreAPIError.missingToken
        } catch let error as KeychainError where tokenReadMode == .cacheOnly && error.isInteractionNotAllowed {
            throw error
        }
    }

    private func ensureCurrent(_ session: CoreSessionContext) throws {
        guard session.generation == sessionRevision,
              session.profileID == selectedProfile?.id else {
            throw CancellationError()
        }
    }

    private func beginMessageRequest() -> UInt64 {
        messageRequestRevision &+= 1
        return messageRequestRevision
    }

    private func ensureCurrent(_ session: CoreSessionContext, messageRevision: UInt64) throws {
        try ensureCurrent(session)
        guard messageRevision == messageRequestRevision else {
            throw CancellationError()
        }
    }

    private func beginDailySummaryRequest() -> UInt64 {
        dailySummaryRequestRevision &+= 1
        return dailySummaryRequestRevision
    }

    private func ensureCurrent(_ session: CoreSessionContext, dailySummaryRevision: UInt64) throws {
        try ensureCurrent(session)
        guard dailySummaryRevision == dailySummaryRequestRevision else {
            throw CancellationError()
        }
    }

    private func fetchDashboardSnapshot(using client: CoreAPIClient) async throws -> DashboardState {
        async let state = client.fetchSyncState()
        async let capabilities = client.fetchCapabilities()
        async let apiManifest = fetchAPIManifestIfAvailable(using: client)
        async let messages = client.fetchRecentMessages(limit: 100, includeMedia: true)
        async let events = client.listOperationEvents(status: "failed", limit: 100)
        let snapshot = try await (state, capabilities, apiManifest, messages, events)
        return DashboardState(
            coreState: snapshot.0,
            capabilities: snapshot.1,
            apiManifest: snapshot.2,
            recentMessages: snapshot.3.items,
            operationEvents: snapshot.4
        )
    }

    private func ensureCompatibility(allowKeychainUI: Bool) async -> Bool {
        guard compatibilityCheckedSessionRevision != sessionRevision else { return true }
        let revision = sessionRevision
        return await withLoading(
            "Checking core compatibility",
            tokenReadMode: allowKeychainUI ? .promptIfNeeded : .cacheOnly
        ) { session in
            let manifest = try await fetchAPIManifestIfAvailable(using: session.client)
            let capabilities = try await fetchCapabilitiesIfAvailable(using: session.client)
            try ensureCurrent(session)
            dashboard.apiManifest = manifest
            if let capabilities {
                dashboard.capabilities = capabilities
            }
            compatibilityCheckedSessionRevision = revision
            if !availableSections.contains(selectedSection) {
                selectedSection = .dashboard
            }
        }
    }

    private func refreshAccountsIfAvailable(using session: CoreSessionContext) async throws -> Bool {
        do {
            let loadedAccounts = try await session.client.listManagementAccounts()
            try ensureCurrent(session)
            accounts = loadedAccounts
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try ensureCurrent(session)
            return false
        }
    }

    private func refreshOriginsIfAvailable(using session: CoreSessionContext) async throws -> Bool {
        do {
            let loadedOrigins = try await session.client.listOrigins(
                accountID: originAccountFilter.nilIfEmpty,
                includeArchived: includeArchivedOrigins
            )
            try ensureCurrent(session)
            origins = loadedOrigins
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try ensureCurrent(session)
            return false
        }
    }

    private func applyArchiveLocally(_ origin: CoreOrigin, archived: Bool) {
        if archived, !includeArchivedOrigins {
            origins.removeAll { $0.id == origin.id }
            return
        }
        guard let index = origins.firstIndex(where: { $0.id == origin.id }) else { return }
        origins[index].archivedAt = archived ? ISO8601DateFormatter().string(from: Date()) : nil
    }

    private func refreshSummaryScopeIfAvailable(using session: CoreSessionContext) async throws -> Bool {
        do {
            async let accountsRequest = session.client.listManagementAccounts()
            async let originsRequest = session.client.listOrigins(accountID: nil, includeArchived: false)
            let snapshot = try await (accountsRequest, originsRequest)
            try ensureCurrent(session)
            summaryScopeAccounts = snapshot.0
            summaryScopeOrigins = snapshot.1
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try ensureCurrent(session)
            return false
        }
    }

    private func refreshOperationEventsIfAvailable(using session: CoreSessionContext) async throws -> Bool {
        do {
            let loadedEvents = try await session.client.listOperationEvents(
                accountID: diagnosticsAccountFilter.nilIfEmpty,
                status: diagnosticsStatusFilter.nilIfEmpty,
                limit: 100
            )
            try ensureCurrent(session)
            operationEvents = loadedEvents
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try ensureCurrent(session)
            return false
        }
    }

    private func refreshParticipantsIfAvailable(
        using session: CoreSessionContext,
        accountID: String,
        originID: Int
    ) async throws -> Bool {
        do {
            let loadedParticipants = try await session.client.listParticipants(accountID: accountID, originID: originID)
            try ensureCurrent(session)
            participants = loadedParticipants
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try ensureCurrent(session)
            return false
        }
    }

    private func upsertAccount(_ account: CoreAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
    }

    private func fetchAPIManifestIfAvailable(using client: CoreAPIClient) async throws -> CoreAPIManifest? {
        do {
            return try await client.fetchAPIManifest()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func fetchCapabilitiesIfAvailable(using client: CoreAPIClient) async throws -> CoreCapabilities? {
        do {
            return try await client.fetchCapabilities()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func applyDashboardSnapshot(_ snapshot: DashboardState, messageRevision: UInt64) {
        var currentSnapshot = snapshot
        currentSnapshot.apiManifest = snapshot.apiManifest ?? dashboard.apiManifest
        if messageRevision != messageRequestRevision {
            currentSnapshot.recentMessages = dashboard.recentMessages
        }
        dashboard = currentSnapshot
        if !availableSections.contains(selectedSection) {
            selectedSection = .dashboard
        }
        if messageRevision == messageRequestRevision,
           messageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages = snapshot.recentMessages
        }
    }

    private func fetchDailySummarySnapshot(using client: CoreAPIClient) async throws -> DailySummaryStateSnapshot {
        let includeDeleted = includeDeletedDailySummaryRecords
        async let summaryRecords = client.listDailySummaryRecords(
            includeDeleted: includeDeleted,
            includeContent: false,
            limit: 500
        )
        async let packageRuns = client.listDailyPackageRuns(limit: 50)
        async let summaryRuns = client.listDailySummaryRuns(limit: 50)
        async let summaryJobs = client.listDailySummaryJobs(limit: 50)
        let snapshot = try await (summaryRecords, packageRuns, summaryRuns, summaryJobs)
        return DailySummaryStateSnapshot(
            records: visibleDailySummaryRecords(snapshot.0),
            packageRuns: sortDailyPackageRuns(snapshot.1),
            summaryRuns: sortDailySummaryRuns(snapshot.2),
            jobs: sortDailySummaryJobs(snapshot.3)
        )
    }

    private func refreshDailySummarySnapshotIfAvailable(
        using session: CoreSessionContext,
        requestRevision: UInt64
    ) async throws -> Bool {
        do {
            let snapshot = try await fetchDailySummarySnapshot(using: session.client)
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            applyDailySummarySnapshot(snapshot)
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try ensureCurrent(session, dailySummaryRevision: requestRevision)
            return false
        }
    }

    private func applyDailySummarySnapshot(_ snapshot: DailySummaryStateSnapshot) {
        dailySummaryRecords = snapshot.records.map { record in
            guard record.contentMD == nil,
                  let existing = dailySummaryRecords.first(where: { $0.summaryID == record.summaryID }),
                  existing.contentMD != nil else {
                return record
            }
            var merged = record
            merged.contentMD = existing.contentMD
            merged.contentJSON = existing.contentJSON
            return merged
        }
        dailyPackageRuns = snapshot.packageRuns
        dailySummaryRuns = snapshot.summaryRuns
        dailySummaryJobs = snapshot.jobs
    }

    @discardableResult
    private func withLoading(
        _ action: String,
        tokenReadMode: TokenReadMode = .promptIfNeeded,
        scope: OperationScope = .exclusive,
        operation: (CoreSessionContext) async throws -> Void
    ) async -> Bool {
        let operationID = UUID()
        let startingGeneration = sessionRevision
        if !activeOperations.isEmpty {
            guard scope == .messages,
                  activeOperations.values.allSatisfy({ $0 == .messages }) else {
                runtimeLogger.debug("Operation skipped action=\(action) reason=busy")
                return false
            }
        }
        let scopeLabel = scope == .messages ? "messages" : "exclusive"
        runtimeLogger.info("Operation begin action=\(action) scope=\(scopeLabel)")
        activeOperations[operationID] = scope
        latestOperationIDs[scope] = operationID
        isLoading = !activeOperations.isEmpty
        lastError = nil
        statusMessage = action
        defer {
            activeOperations.removeValue(forKey: operationID)
            if latestOperationIDs[scope] == operationID {
                latestOperationIDs.removeValue(forKey: scope)
            }
            isLoading = !activeOperations.isEmpty
        }

        do {
            let session = try makeSession(tokenReadMode: tokenReadMode)
            try await operation(session)
            try ensureCurrent(session)
            runtimeLogger.info("Operation end action=\(action) result=success")
            return true
        } catch is CancellationError {
            runtimeLogger.debug("Operation end action=\(action) result=cancelled")
            return false
        } catch {
            runtimeLogger.error("Operation end action=\(action) result=failure error=\(safeRuntimeErrorSummary(error))")
            if startingGeneration == sessionRevision,
               latestOperationIDs[scope] == operationID {
                lastError = error.localizedDescription
                statusMessage = "Failed"
            }
            return false
        }
    }

    private func safeRuntimeErrorSummary(_ error: Error) -> String {
        if let error = error as? KeychainError {
            return "keychain_status_\(error.status)"
        }
        if let error = error as? CoreAPIError {
            switch error {
            case .invalidBaseURL:
                return "invalid_base_url"
            case .invalidResponse:
                return "invalid_response"
            case .httpStatus(let status, _):
                return "http_status_\(status)"
            case .missingProfile:
                return "missing_profile"
            case .missingToken:
                return "missing_token"
            case .transport:
                return "transport_error"
            }
        }
        if let error = error as? PartialMutationError {
            return "partial_mutation_\(error.completed)_of_\(error.total)"
        }
        if let error = error as? URLError {
            return "url_error_\(error.code.rawValue)"
        }
        if error is DecodingError {
            return "decoding_error"
        }
        return String(describing: type(of: error))
    }

    private func sortDailySummaryRecords(_ records: [DailySummaryRecord]) -> [DailySummaryRecord] {
        records.sorted { lhs, rhs in
            let leftTime = lhs.updatedSortValue
            let rightTime = rhs.updatedSortValue
            if leftTime != rightTime {
                return leftTime > rightTime
            }
            if lhs.dateSortValue != rhs.dateSortValue {
                return lhs.dateSortValue > rhs.dateSortValue
            }
            if lhs.titleSortValue != rhs.titleSortValue {
                return lhs.titleSortValue.localizedCaseInsensitiveCompare(rhs.titleSortValue) == .orderedAscending
            }
            return lhs.summaryID.localizedCaseInsensitiveCompare(rhs.summaryID) == .orderedAscending
        }
    }

    private func sortDailyMessagePoints(_ points: [DailyMessagePoint]) -> [DailyMessagePoint] {
        points.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt > rhs.occurredAt
            }
            return lhs.pointID.localizedCaseInsensitiveCompare(rhs.pointID) == .orderedAscending
        }
    }

    private func sortDailyPackageRuns(_ runs: [DailyPackageRun]) -> [DailyPackageRun] {
        runs.sorted { lhs, rhs in
            let leftTime = lhs.startedAt ?? lhs.finishedAt ?? lhs.date
            let rightTime = rhs.startedAt ?? rhs.finishedAt ?? rhs.date
            if leftTime != rightTime {
                return leftTime > rightTime
            }
            return lhs.runID.localizedCaseInsensitiveCompare(rhs.runID) == .orderedAscending
        }
    }

    private func sortDailySummaryRuns(_ runs: [DailySummaryRun]) -> [DailySummaryRun] {
        runs.sorted { lhs, rhs in
            let leftTime = lhs.startedAt ?? lhs.finishedAt ?? lhs.date ?? ""
            let rightTime = rhs.startedAt ?? rhs.finishedAt ?? rhs.date ?? ""
            if leftTime != rightTime {
                return leftTime > rightTime
            }
            return lhs.runID.localizedCaseInsensitiveCompare(rhs.runID) == .orderedAscending
        }
    }

    private func sortDailySummaryJobs(_ jobs: [DailySummaryJob]) -> [DailySummaryJob] {
        jobs.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            let leftTime = lhs.updatedAt ?? lhs.startedAt ?? lhs.finishedAt ?? lhs.date ?? ""
            let rightTime = rhs.updatedAt ?? rhs.startedAt ?? rhs.finishedAt ?? rhs.date ?? ""
            if leftTime != rightTime {
                return leftTime > rightTime
            }
            return lhs.jobID.localizedCaseInsensitiveCompare(rhs.jobID) == .orderedAscending
        }
    }

    private func upsertDailySummaryJob(_ job: DailySummaryJob, into jobs: [DailySummaryJob]) -> [DailySummaryJob] {
        var updated = jobs
        if let index = updated.firstIndex(where: { $0.jobID == job.jobID }) {
            updated[index] = job
        } else {
            updated.insert(job, at: 0)
        }
        return sortDailySummaryJobs(updated)
    }

    private func visibleDailySummaryRecords(_ records: [DailySummaryRecord]) -> [DailySummaryRecord] {
        sortDailySummaryRecords(records)
    }

    private func sortOrigins(_ origins: [CoreOrigin]) -> [CoreOrigin] {
        origins.sorted { lhs, rhs in
            if originBackupFirst {
                let left = lhs.backupPolicy?.enabled == true
                let right = rhs.backupPolicy?.enabled == true
                if left != right {
                    return left && !right
                }
            }
            switch originSort {
            case .groupTopic:
                return compareOriginHierarchy(lhs, rhs)
            case .lastMessageDesc:
                return (lhs.lastMessageAt ?? "") > (rhs.lastMessageAt ?? "")
            case .lastMessageAsc:
                return (lhs.lastMessageAt ?? "") < (rhs.lastMessageAt ?? "")
            case .titleAsc:
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            case .accountAsc:
                if lhs.accountID == rhs.accountID {
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
                return lhs.accountID.localizedCaseInsensitiveCompare(rhs.accountID) == .orderedAscending
            case .typeAsc:
                if lhs.originType == rhs.originType {
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
                return lhs.originType.localizedCaseInsensitiveCompare(rhs.originType) == .orderedAscending
            case .backupDesc:
                let left = lhs.backupPolicy?.enabled == true
                let right = rhs.backupPolicy?.enabled == true
                if left == right {
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
                return left && !right
            }
        }
    }

    private func compareOriginHierarchy(_ lhs: CoreOrigin, _ rhs: CoreOrigin) -> Bool {
        if lhs.accountID != rhs.accountID {
            return lhs.accountID.localizedCaseInsensitiveCompare(rhs.accountID) == .orderedAscending
        }
        if lhs.originID != rhs.originID {
            return lhs.originID < rhs.originID
        }
        if lhs.topicID != rhs.topicID {
            if lhs.topicID == 0 { return true }
            if rhs.topicID == 0 { return false }
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }
        return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }

    private func affectedOrigins(for selectedOrigins: [CoreOrigin]) -> [CoreOrigin] {
        var seen = Set<CoreOrigin.ID>()
        var targets: [CoreOrigin] = []
        for origin in selectedOrigins {
            let affected: [CoreOrigin]
            if origin.topicID == 0 {
                affected = origins.filter {
                    $0.source == origin.source &&
                    $0.accountID == origin.accountID &&
                    $0.originID == origin.originID
                }
            } else {
                affected = [origin]
            }
            for target in affected where seen.insert(target.id).inserted {
                targets.append(target)
            }
        }
        return targets
    }

    private func replaceOrigin(_ origin: CoreOrigin) {
        if let index = origins.firstIndex(where: { $0.id == origin.id }) {
            origins[index] = origin
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
