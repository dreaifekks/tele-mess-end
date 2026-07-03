import AppKit
import Foundation
import Observation

struct DashboardState {
    var coreState: CoreState?
    var capabilities: CoreCapabilities?
    var recentMessages: [CoreMessage] = []
    var operationEvents: [CoreOperationEvent] = []
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
    let keychain = KeychainStore()
    let localRunner = LocalCoreProcessController()

    var selectedSection: AppSection = .dashboard
    var dashboard = DashboardState()
    var accounts: [CoreAccount] = []
    var origins: [CoreOrigin] = []
    var messages: [CoreMessage] = []
    var participants: [CoreParticipant] = []
    var cursors: [CoreCaptureCursor] = []
    var mediaFiles: [CoreMediaFile] = []
    var operationEvents: [CoreOperationEvent] = []

    var isLoading = false
    var statusMessage = "Ready"
    var lastError: String?

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

    init(profileStore: CoreProfileStore? = nil) {
        self.profileStore = profileStore ?? CoreProfileStore()
    }

    var selectedProfile: CoreProfile? {
        profileStore.selectedProfile
    }

    var selectedOrigin: CoreOrigin? {
        guard let selectedOriginID else { return nil }
        return origins.first { $0.id == selectedOriginID }
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
        case .diagnostics:
            await loadDiagnostics()
        }
    }

    func validateActiveProfile() async {
        await withLoading("Validating profile") {
            let client = try makeClient()
            _ = try await client.health()
            dashboard.coreState = try await client.fetchSyncState()
            dashboard.capabilities = try await client.fetchCapabilities()
            statusMessage = "Connected to \(selectedProfile?.name ?? "core")"
        }
    }

    func loadDashboard() async {
        await withLoading("Loading dashboard") {
            let client = try makeClient()
            async let state = client.fetchSyncState()
            async let capabilities = client.fetchCapabilities()
            async let messages = client.fetchRecentMessages(limit: 100)
            async let events = client.listOperationEvents(status: "failed", limit: 100)
            dashboard.coreState = try await state
            dashboard.capabilities = try await capabilities
            dashboard.recentMessages = try await messages.items
            dashboard.operationEvents = try await events
            statusMessage = "Dashboard refreshed"
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
            origins = try await makeClient().listOrigins(accountID: originAccountFilter.nilIfEmpty, includeArchived: includeArchivedOrigins)
            if selectedOriginID == nil {
                selectedOriginID = origins.first?.id
            }
            statusMessage = "Loaded \(origins.count) origins"
        }
    }

    func discoverOrigins(accountID: String) async {
        await withLoading("Discovering origins") {
            let result = try await makeClient().discoverOrigins(accountID: accountID, includeTopics: true, includePrivate: false, topicLimit: 500)
            origins = try await makeClient().listOrigins(accountID: accountID, includeArchived: includeArchivedOrigins)
            statusMessage = result.message ?? "Discovery finished"
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
            origins = try await makeClient().listOrigins(accountID: originAccountFilter.nilIfEmpty, includeArchived: includeArchivedOrigins)
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
            origins = try await makeClient().listOrigins(accountID: originAccountFilter.nilIfEmpty, includeArchived: includeArchivedOrigins)
            statusMessage = "Policy saved"
        }
    }

    func loadRecentMessages() async {
        await withLoading("Loading messages") {
            messages = try await makeClient().fetchRecentMessages(limit: 100).items
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
            messages = try await makeClient().searchMessages(query: query, limit: 100)
            statusMessage = "Search returned \(messages.count) messages"
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
        do {
            if let token {
                if token.isEmpty {
                    try keychain.deleteToken(profileID: profile.id)
                } else {
                    try keychain.saveToken(token, profileID: profile.id)
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
        do {
            try keychain.deleteToken(profileID: removed.id)
            statusMessage = "Profile deleted"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed"
        }
    }

    func tokenForSelectedProfile() -> String {
        guard let selectedProfile else { return "" }
        return (try? keychain.readToken(profileID: selectedProfile.id)) ?? ""
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

    private func makeClient() throws -> CoreAPIClient {
        guard let profile = selectedProfile else {
            throw CoreAPIError.missingProfile
        }
        guard let baseURL = profile.baseURL else {
            throw CoreAPIError.invalidBaseURL(profile.baseURLString)
        }
        return CoreAPIClient(
            baseURL: baseURL,
            tokenProvider: KeychainTokenProvider(keychain: keychain, profileID: profile.id),
            authMode: profile.authMode
        )
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
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
