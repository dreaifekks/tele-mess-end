import AppKit
import Foundation
import Observation

struct DashboardState {
    var coreState: CoreState?
    var capabilities: CoreCapabilities?
    var recentMessages: [CoreMessage] = []
    var operationEvents: [CoreOperationEvent] = []
}

private struct CachedProfileToken {
    var profileID: UUID
    var token: String?
}

private let recentMessageRefreshIntervalNanoseconds: UInt64 = 5 * 60 * 1_000_000_000
private let dailySummaryProgressRefreshIntervalNanoseconds: UInt64 = 10 * 1_000_000_000

private enum TokenReadMode {
    case promptIfNeeded
    case cacheOnly
}

private let hiddenDailySummaryIDsKey = "TeleMessEnd.hiddenDailySummaryIDs"

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

@MainActor
@Observable
final class AppModel {
    let profileStore: CoreProfileStore
    let summarySettingsStore: SummarySettingsStore
    let originImportanceStore: OriginImportanceStore
    let keychain = KeychainStore()
    let localRunner = LocalCoreProcessController()
    @ObservationIgnored private var tokenCache: CachedProfileToken?
    @ObservationIgnored private var isRecentMessageRefreshLoopRunning = false
    @ObservationIgnored private var isDailySummaryProgressLoopRunning = false

    var selectedSection: AppSection = .dashboard
    var dashboard = DashboardState()
    var accounts: [CoreAccount] = []
    var origins: [CoreOrigin] = []
    var messages: [CoreMessage] = []
    var participants: [CoreParticipant] = []
    var cursors: [CoreCaptureCursor] = []
    var mediaFiles: [CoreMediaFile] = []
    var operationEvents: [CoreOperationEvent] = []
    var dailySummaries: [DailyGroupSummary] = []
    var dailySummaryRecords: [DailySummaryRecord] = []
    var dailyPackageRuns: [DailyPackageRun] = []
    var dailySummaryRuns: [DailySummaryRun] = []
    var dailySummaryJobs: [DailySummaryJob] = []
    var hiddenDailySummaryIDs: Set<String> = []

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
        originImportanceStore: OriginImportanceStore? = nil
    ) {
        self.profileStore = profileStore ?? CoreProfileStore()
        self.summarySettingsStore = summarySettingsStore ?? SummarySettingsStore()
        self.originImportanceStore = originImportanceStore ?? OriginImportanceStore()
        self.hiddenDailySummaryIDs = Set(UserDefaults.standard.stringArray(forKey: hiddenDailySummaryIDsKey) ?? [])
    }

    var selectedProfile: CoreProfile? {
        profileStore.selectedProfile
    }

    func selectProfile(_ id: UUID?) {
        profileStore.select(id)
        tokenCache = nil
        validationStatus = .unverified
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

    func refreshCurrentSection() async {
        switch selectedSection {
        case .dashboard:
            await loadDashboard()
        case .accounts:
            await loadAccounts()
        case .origins:
            await loadOrigins()
        case .messages:
            await loadRecentMessages()
        case .media:
            await loadMediaFiles()
        case .summaries:
            await refreshDailySummaryProgress()
        case .diagnostics:
            await loadDiagnostics()
        }
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
        validationStatus = .validating
        await withLoading("Validating profile") {
            let client = try makeClient()
            _ = try await client.health()
            try await reloadDashboard(using: client)
            validationStatus = .verified
            statusMessage = "Connected to \(selectedProfile?.name ?? "core")"
        }
        if lastError != nil {
            validationStatus = .failed
        }
    }

    func loadDashboard(allowKeychainUI: Bool = true) async {
        let tokenReadMode: TokenReadMode = allowKeychainUI ? .promptIfNeeded : .cacheOnly
        if tokenReadMode == .cacheOnly && !hasCachedTokenForSelectedProfile {
            return
        }

        await withLoading("Loading dashboard") {
            let client = try makeClient(tokenReadMode: tokenReadMode)
            try await reloadDashboard(using: client)
            statusMessage = "Dashboard refreshed"
        }
    }

    func refreshRecentMessagesInBackground() async {
        guard !isLoading else { return }
        guard hasCachedTokenForSelectedProfile else { return }
        do {
            let messages = try await fetchRecentMessages(tokenReadMode: .cacheOnly)
            dashboard.recentMessages = messages
            if messageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.messages = messages
            }
        } catch {
            return
        }
    }

    func loadAccounts() async {
        await withLoading("Loading accounts") {
            accounts = try await makeClient().listManagementAccounts()
            statusMessage = "Loaded \(accounts.count) accounts"
        }
    }

    func createAccount(_ request: CreateAccountRequest) async {
        await withLoading("Saving account") {
            _ = try await makeClient().createAccount(request)
            accounts = try await makeClient().listManagementAccounts()
            statusMessage = "Account saved"
        }
    }

    func deleteAccount(_ account: CoreAccount) async {
        await withLoading("Deleting account") {
            _ = try await makeClient().deleteAccount(accountID: account.accountID, source: account.source)
            accounts = try await makeClient().listManagementAccounts()
            statusMessage = "Account metadata deleted"
        }
    }

    func authStatus(accountID: String) async {
        await withLoading("Checking auth") {
            let result = try await makeClient().authStatus(accountID: accountID)
            accounts = try await makeClient().listManagementAccounts()
            statusMessage = result.status ?? result.authState ?? "Auth status updated"
        }
    }

    func requestCode(accountID: String, phone: String) async {
        await withLoading("Requesting code") {
            let result = try await makeClient().requestCode(accountID: accountID, phone: phone)
            accounts = try await makeClient().listManagementAccounts()
            statusMessage = result.message ?? result.status ?? "Code requested"
        }
    }

    func submitCode(accountID: String, phone: String, code: String, password: String?) async {
        await withLoading("Submitting code") {
            let result = try await makeClient().submitCode(accountID: accountID, phone: phone, code: code, password: password?.nilIfEmpty)
            accounts = try await makeClient().listManagementAccounts()
            statusMessage = result.message ?? result.status ?? result.authState ?? "Code submitted"
        }
    }

    func loadOrigins() async {
        await withLoading("Loading origins") {
            origins = originImportanceStore.apply(to: try await makeClient().listOrigins(accountID: originAccountFilter.nilIfEmpty, includeArchived: includeArchivedOrigins))
            if selectedOriginID == nil {
                selectedOriginID = origins.first?.id
            }
            statusMessage = "Loaded \(origins.count) origins"
        }
    }

    func discoverOrigins(accountID: String) async {
        await withLoading("Discovering origins") {
            let result = try await makeClient().discoverOrigins(accountID: accountID, includeTopics: true, includePrivate: false, topicLimit: 500)
            origins = originImportanceStore.apply(to: try await makeClient().listOrigins(accountID: accountID, includeArchived: includeArchivedOrigins))
            statusMessage = result.message ?? "Discovery finished"
        }
    }

    func loadSummaryScopeOptions() async {
        await withLoading("Loading summary scope options") {
            let client = try makeClient()
            async let loadedAccounts = client.listManagementAccounts()
            async let loadedOrigins = client.listOrigins(accountID: nil, includeArchived: false)
            accounts = try await loadedAccounts
            origins = originImportanceStore.apply(to: try await loadedOrigins)
            statusMessage = "Loaded summary scope options"
        }
    }

    func discoverSummaryScopeOptions(accountID: String) async {
        await withLoading("Discovering summary delivery targets") {
            let client = try makeClient()
            let result = try await client.discoverOrigins(accountID: accountID, includeTopics: true, includePrivate: false, topicLimit: 500)
            async let loadedAccounts = client.listManagementAccounts()
            async let loadedOrigins = client.listOrigins(accountID: nil, includeArchived: false)
            accounts = try await loadedAccounts
            origins = originImportanceStore.apply(to: try await loadedOrigins)
            statusMessage = result.message ?? "Summary delivery targets refreshed"
        }
    }

    func archiveSelectedOrigin(_ archived: Bool) async {
        guard let origin = selectedOrigin else { return }
        await archiveOrigins([origin], archived: archived)
    }

    func archiveOrigins(_ selectedOrigins: [CoreOrigin], archived: Bool) async {
        let targets = affectedOrigins(for: selectedOrigins)
        guard !targets.isEmpty else { return }
        await withLoading(archived ? "Archiving origin" : "Restoring origin") {
            let client = try makeClient()
            for origin in targets {
                _ = try await client.archiveOrigin(
                    ArchiveOriginRequest(
                        accountID: origin.accountID,
                        originID: origin.originID,
                        topicID: origin.topicID,
                        archived: archived,
                        source: origin.source
                    )
                )
            }
            origins = originImportanceStore.apply(to: try await makeClient().listOrigins(accountID: originAccountFilter.nilIfEmpty, includeArchived: includeArchivedOrigins))
            statusMessage = archived ? "Origin archived" : "Origin restored"
        }
    }

    func deleteSelectedOrigin() async {
        guard let origin = selectedOrigin else { return }
        await deleteOrigins([origin])
    }

    func deleteOrigins(_ selectedOrigins: [CoreOrigin]) async {
        await archiveOrigins(selectedOrigins, archived: true)
    }

    func savePolicy(for origin: CoreOrigin, policy: CoreBackupPolicy) async {
        let targets = affectedOrigins(for: [origin])
        await withLoading("Saving policy") {
            let client = try makeClient()
            for target in targets {
                _ = try await client.setBackupPolicy(
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
            }
            origins = originImportanceStore.apply(to: try await makeClient().listOrigins(accountID: originAccountFilter.nilIfEmpty, includeArchived: includeArchivedOrigins))
            statusMessage = "Policy saved"
        }
    }

    func setOriginImportant(_ origin: CoreOrigin, important: Bool) async {
        let previousImportant = origin.important
        updateOriginImportantLocally(origin, important: important)
        isLoading = true
        lastError = nil
        statusMessage = important ? "Marking important" : "Clearing important"
        do {
            let updated = try await makeClient().setOriginImportant(
                OriginImportantRequest(
                    accountID: origin.accountID,
                    originID: origin.originID,
                    topicID: origin.topicID,
                    important: important,
                    source: origin.source
                )
            )
            originImportanceStore.set(nil, for: origin)
            replaceOrigin(updated)
            statusMessage = important ? "Origin marked important" : "Origin unmarked"
        } catch {
            lastError = error.localizedDescription
            updateOriginImportantLocally(origin, important: previousImportant)
            statusMessage = "Failed"
        }
        isLoading = false
    }

    func loadRecentMessages() async {
        await withLoading("Loading messages") {
            let recentMessages = try await fetchRecentMessages()
            messages = recentMessages
            dashboard.recentMessages = recentMessages
            statusMessage = "Loaded recent messages"
        }
    }

    func searchMessages() async {
        let query = messageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            await loadRecentMessages()
            return
        }
        await withLoading("Searching messages") {
            messages = try await makeClient().searchMessages(query: query, limit: 100, includeMedia: true)
            statusMessage = "Search returned \(messages.count) messages"
        }
    }

    func loadMediaFiles() async {
        await withLoading("Loading media") {
            mediaFiles = try await makeClient().listMediaFiles(
                accountID: mediaAccountFilter.nilIfEmpty,
                chatID: Int(mediaChatIDFilter),
                messageID: Int(mediaMessageIDFilter),
                limit: 500
            )
            statusMessage = "Loaded \(mediaFiles.count) media files"
        }
    }

    func showMedia(for message: CoreMessage) async {
        mediaAccountFilter = message.accountID
        mediaChatIDFilter = String(message.chatID)
        mediaMessageIDFilter = String(message.messageID)
        selectedSection = .media
        await loadMediaFiles()
    }

    func openMediaFile(_ file: CoreMediaFile) async {
        await withLoading("Opening media") {
            let data = try await makeClient().downloadMediaContent(for: file)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TeleMessEndMedia", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file.suggestedFilename)
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
            statusMessage = "Opened \(file.suggestedFilename)"
        }
    }

    func fetchMediaContent(_ file: CoreMediaFile) async throws -> Data {
        try await makeClient().downloadMediaContent(for: file)
    }

    func saveSummarySettings(_ settings: SummarySettings) {
        summarySettingsStore.save(settings)
        statusMessage = "Summary settings saved"
        lastError = nil
    }

    func loadSummarySchedule() async {
        await withLoading("Loading summary schedule") {
            let schedule = try await makeClient().fetchDailyPackageSchedule()
            summarySettingsStore.save(SummarySettings(schedule: schedule, preservingDeliveryFrom: summarySettingsStore.settings))
            statusMessage = schedule.enabled ? "Summary schedule enabled" : "Summary schedule loaded"
        }
    }

    func saveSummarySchedule(_ settings: SummarySettings) async {
        await withLoading("Saving summary schedule") {
            let schedule = try await makeClient().updateDailyPackageSchedule(settings.scheduleInput)
            summarySettingsStore.save(SummarySettings(schedule: schedule, preservingDeliveryFrom: settings))
            statusMessage = "Summary schedule saved"
        }
    }

    func loadDailySummaries() async {
        await withLoading("Loading daily summaries") {
            let settings = summarySettingsStore.settings
            let client = try makeClient()
            try await reloadDailySummaryState(using: client, settings: settings)
            statusMessage = "Loaded \(dailySummaryRecords.count) summary records"
        }
    }

    func runDailyPackageAndSummary() async {
        lastError = nil
        statusMessage = "Starting daily analysis"
        do {
            let client = try makeClient()
            let job = try await client.runDailySummaryJob(summarySettingsStore.settings.summaryRunInput)
            dailySummaryJobs = upsertDailySummaryJob(job, into: dailySummaryJobs)
            try await reloadDailySummaryState(using: client, settings: summarySettingsStore.settings)
            statusMessage = "Daily analysis \(job.status)"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed"
        }
    }

    func refreshDailySummaryProgress() async {
        await withLoading("Refreshing daily analysis") {
            let client = try makeClient()
            try await reloadDailySummaryState(using: client, settings: summarySettingsStore.settings)
            if let job = latestDailySummaryJob {
                statusMessage = "Daily analysis \(job.status)"
            } else {
                statusMessage = "Daily analysis refreshed"
            }
        }
    }

    func refreshDailySummaryProgressInBackground() async {
        guard !isLoading else { return }

        do {
            let client = try makeClient(tokenReadMode: .cacheOnly)
            try await reloadDailySummaryState(using: client, settings: summarySettingsStore.settings)
            if let job = latestDailySummaryJob {
                statusMessage = "Daily analysis \(job.status)"
            }
        } catch {
            return
        }
    }

    func cancelDailySummaryJob(_ job: DailySummaryJob? = nil) async {
        guard let target = job ?? activeDailySummaryJob ?? latestDailySummaryJob else {
            statusMessage = "No daily analysis job to cancel"
            lastError = nil
            return
        }

        await withLoading("Cancelling daily analysis") {
            let client = try makeClient()
            let cancelled = try await client.cancelDailySummaryJob(jobID: target.jobID)
            dailySummaryJobs = upsertDailySummaryJob(cancelled, into: dailySummaryJobs)
            try await reloadDailySummaryState(using: client, settings: summarySettingsStore.settings)
            statusMessage = "Daily analysis \(cancelled.status)"
        }
    }

    func runDailyPackage() async {
        await withLoading("Generating daily package") {
            let run = try await makeClient().runDailyPackage(summarySettingsStore.settings.packageRunInput)
            dailyPackageRuns.insert(run, at: 0)
            statusMessage = "Daily package \(run.status)"
        }
    }

    func runDailySummary() async {
        await withLoading("Running daily summary") {
            let run = try await makeClient().runDailySummary(summarySettingsStore.settings.summaryRunInput)
            dailySummaryRuns.insert(run, at: 0)
            let records = try await makeClient().listDailySummaryRecords(
                important: summarySettingsStore.settings.importantOnly ? true : nil,
                tags: summarySettingsStore.settings.tags.nilIfEmpty,
                includeContent: false,
                limit: 500
            )
            dailySummaryRecords = visibleDailySummaryRecords(records)
            statusMessage = "Daily summary \(run.status)"
        }
    }

    func hideDailySummaryRecord(_ record: DailySummaryRecord) {
        hiddenDailySummaryIDs.insert(record.summaryID)
        saveHiddenDailySummaryIDs()
        dailySummaryRecords.removeAll { $0.summaryID == record.summaryID }
        statusMessage = "Summary hidden"
        lastError = nil
    }

    func restoreHiddenDailySummaries() async {
        hiddenDailySummaryIDs.removeAll()
        saveHiddenDailySummaryIDs()
        await loadDailySummaries()
    }

    func loadDailySummaryRecordContent(_ record: DailySummaryRecord) async {
        await withLoading("Loading summary content") {
            let loaded = try await makeClient().fetchDailySummaryRecord(
                summaryID: record.summaryID,
                includeDeleted: includeDeletedDailySummaryRecords || record.deleted == true
            )
            if let index = dailySummaryRecords.firstIndex(where: { $0.summaryID == loaded.summaryID }) {
                dailySummaryRecords[index] = loaded
            } else {
                dailySummaryRecords.insert(loaded, at: 0)
            }
            statusMessage = "Loaded summary content"
        }
    }

    func deleteDailySummaryRecords(_ records: [DailySummaryRecord]) async {
        let summaryIDs = records.map(\.summaryID)
        guard !summaryIDs.isEmpty else { return }

        await withLoading("Deleting summary records") {
            let client = try makeClient()
            let result = try await client.deleteDailySummaryRecords(summaryIDs: summaryIDs)
            if includeDeletedDailySummaryRecords {
                try await reloadDailySummaryState(using: client, settings: summarySettingsStore.settings)
            } else {
                dailySummaryRecords.removeAll { summaryIDs.contains($0.summaryID) }
            }
            statusMessage = "Deleted \(result.changedRows) summary records"
        }
    }

    func restoreDailySummaryRecords(_ records: [DailySummaryRecord]) async {
        let summaryIDs = records.map(\.summaryID)
        guard !summaryIDs.isEmpty else { return }

        await withLoading("Restoring summary records") {
            let client = try makeClient()
            let result = try await client.restoreDailySummaryRecords(summaryIDs: summaryIDs)
            try await reloadDailySummaryState(using: client, settings: summarySettingsStore.settings)
            statusMessage = "Restored \(result.changedRows) summary records"
        }
    }

    func loadDiagnostics() async {
        await withLoading("Loading diagnostics") {
            let client = try makeClient()
            switch diagnosticsSelection {
            case .operationEvents:
                operationEvents = try await client.listOperationEvents(
                    accountID: diagnosticsAccountFilter.nilIfEmpty,
                    status: diagnosticsStatusFilter.nilIfEmpty,
                    limit: 100
                )
            case .participants:
                participants = try await client.listParticipants(
                    accountID: diagnosticsAccountFilter.nilIfEmpty,
                    originID: Int(diagnosticsOriginIDFilter)
                )
            case .cursors:
                cursors = try await client.listCaptureCursors(accountID: diagnosticsAccountFilter.nilIfEmpty)
            case .media:
                mediaFiles = try await client.listMediaFiles(accountID: diagnosticsAccountFilter.nilIfEmpty, limit: 500)
            }
            statusMessage = "Diagnostics loaded"
        }
    }

    func deleteOperationEvent(_ event: CoreOperationEvent) async {
        await withLoading("Deleting operation event") {
            let client = try makeClient()
            _ = try await client.deleteOperationEvent(id: event.id)
            operationEvents = try await client.listOperationEvents(
                accountID: diagnosticsAccountFilter.nilIfEmpty,
                status: diagnosticsStatusFilter.nilIfEmpty,
                limit: 100
            )
            statusMessage = "Operation event deleted"
        }
    }

    func refreshParticipants(accountID: String, originID: Int) async {
        await withLoading("Refreshing participants") {
            _ = try await makeClient().refreshParticipants(accountID: accountID, originID: originID, limit: 500)
            participants = try await makeClient().listParticipants(accountID: accountID, originID: originID)
            diagnosticsSelection = .participants
            statusMessage = "Participants refreshed"
        }
    }

    func saveProfile(_ profile: CoreProfile, token: String?) {
        profileStore.upsert(profile)
        validationStatus = .unverified
        do {
            if let token {
                if token.isEmpty {
                    try keychain.deleteToken(profileID: profile.id)
                    tokenCache = CachedProfileToken(profileID: profile.id, token: nil)
                } else {
                    try keychain.saveToken(token, profileID: profile.id)
                    tokenCache = CachedProfileToken(profileID: profile.id, token: token)
                }
            }
            statusMessage = "Profile saved"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteSelectedProfile() {
        guard let removed = profileStore.deleteSelected() else { return }
        validationStatus = .unverified
        do {
            try keychain.deleteToken(profileID: removed.id)
            if tokenCache?.profileID == removed.id {
                tokenCache = nil
            }
            statusMessage = "Profile deleted"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed"
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

    private var hasCachedTokenForSelectedProfile: Bool {
        guard let selectedProfile,
              let tokenCache,
              tokenCache.profileID == selectedProfile.id,
              let token = tokenCache.token,
              !token.isEmpty else {
            return false
        }
        return true
    }

    private func makeClient(tokenReadMode: TokenReadMode = .promptIfNeeded) throws -> CoreAPIClient {
        guard let profile = selectedProfile else {
            throw CoreAPIError.missingProfile
        }
        guard let baseURL = profile.baseURL else {
            throw CoreAPIError.invalidBaseURL(profile.baseURLString)
        }
        let token = try token(for: profile, tokenReadMode: tokenReadMode)
        return CoreAPIClient(
            baseURL: baseURL,
            tokenProvider: FixedTokenProvider(value: token),
            authMode: profile.authMode
        )
    }

    private func token(for profile: CoreProfile, tokenReadMode: TokenReadMode) throws -> String? {
        if let tokenCache, tokenCache.profileID == profile.id {
            return tokenCache.token
        }

        guard tokenReadMode == .promptIfNeeded else {
            return nil
        }

        AppLog.runtime.info("Reading Keychain token for profile \(profile.id.uuidString, privacy: .public)")
        let token = try keychain.readToken(profileID: profile.id)
        tokenCache = CachedProfileToken(profileID: profile.id, token: token)
        return token
    }

    private func fetchRecentMessages(tokenReadMode: TokenReadMode = .promptIfNeeded) async throws -> [CoreMessage] {
        try await makeClient(tokenReadMode: tokenReadMode).fetchRecentMessages(limit: 100, includeMedia: true).items
    }

    private func reloadDashboard(using client: CoreAPIClient) async throws {
        async let state = client.fetchSyncState()
        async let capabilities = client.fetchCapabilities()
        async let messages = client.fetchRecentMessages(limit: 100, includeMedia: true)
        async let events = client.listOperationEvents(status: "failed", limit: 100)
        dashboard.coreState = try await state
        dashboard.capabilities = try await capabilities
        dashboard.recentMessages = try await messages.items
        dashboard.operationEvents = try await events
        if messageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.messages = dashboard.recentMessages
        }
    }

    private func reloadDailySummaryState(using client: CoreAPIClient, settings: SummarySettings) async throws {
        async let summaryRecords = client.listDailySummaryRecords(
            important: settings.importantOnly ? true : nil,
            tags: settings.tags.nilIfEmpty,
            includeDeleted: includeDeletedDailySummaryRecords,
            includeContent: false,
            limit: 500
        )
        async let packageRuns = client.listDailyPackageRuns(limit: 50)
        async let summaryRuns = client.listDailySummaryRuns(limit: 50)
        async let summaryJobs = client.listDailySummaryJobs(limit: 50)

        dailySummaryRecords = visibleDailySummaryRecords(try await summaryRecords)
        dailyPackageRuns = sortDailyPackageRuns(try await packageRuns)
        dailySummaryRuns = sortDailySummaryRuns(try await summaryRuns)
        dailySummaryJobs = sortDailySummaryJobs(try await summaryJobs)
        dailySummaries = []
    }

    private func withLoading(_ action: String, operation: () async throws -> Void) async {
        isLoading = true
        lastError = nil
        statusMessage = action
        do {
            try await operation()
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed"
        }
        isLoading = false
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

    private func saveHiddenDailySummaryIDs() {
        UserDefaults.standard.set(Array(hiddenDailySummaryIDs).sorted(), forKey: hiddenDailySummaryIDsKey)
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

    private func updateOriginImportantLocally(_ origin: CoreOrigin, important: Bool) {
        origins = origins.map { current in
            guard current.id == origin.id else { return current }
            var updated = current
            updated.important = important
            return updated
        }
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
