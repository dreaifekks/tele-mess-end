import Foundation

protocol CoreHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request, delegate: nil)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoreAPIError.invalidResponse
        }
        return (data, httpResponse)
    }
}

struct CoreAPIClient: Sendable {
    var baseURL: URL
    var tokenProvider: any AuthTokenProvider
    var authMode: CoreAuthMode
    var transport: any CoreHTTPTransport

    init(
        baseURL: URL,
        tokenProvider: any AuthTokenProvider = EmptyTokenProvider(),
        authMode: CoreAuthMode = .bearer,
        transport: any CoreHTTPTransport = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.authMode = authMode
        self.transport = transport
    }

    func health() async throws -> CoreState {
        try await send("GET", path: "/healthz")
    }

    func fetchSyncState() async throws -> CoreState {
        try await send("GET", path: "/sync/state")
    }

    func fetchCapabilities() async throws -> CoreCapabilities {
        try await send("GET", path: "/manage/capabilities")
    }

    func fetchAPIManifest() async throws -> CoreAPIManifest {
        try await send("GET", path: "/manage/api-manifest")
    }

    func fetchEvents(after cursor: Int = 0, limit: Int = 500) async throws -> CorePage<CoreEvent> {
        try await send("GET", path: "/sync/events", query: [
            URLQueryItem(name: "after", value: String(cursor)),
            URLQueryItem(name: "limit", value: String(limit))
        ])
    }

    func fetchRecentMessages(limit: Int = 100, includeMedia: Bool = false) async throws -> CorePage<CoreMessage> {
        var query = [
            URLQueryItem(name: "latest", value: "true"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if includeMedia {
            query.append(URLQueryItem(name: "include_media", value: "true"))
        }
        return try await send("GET", path: "/sync/messages", query: query)
    }

    func fetchMessages(after cursor: Int, limit: Int = 500, includeMedia: Bool = false) async throws -> CorePage<CoreMessage> {
        var query = [
            URLQueryItem(name: "after", value: String(cursor)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if includeMedia {
            query.append(URLQueryItem(name: "include_media", value: "true"))
        }
        return try await send("GET", path: "/sync/messages", query: query)
    }

    func listSyncAccounts() async throws -> [CoreAccount] {
        let response: CoreItemsResponse<CoreAccount> = try await send("GET", path: "/sync/accounts")
        return response.items
    }

    func listChats() async throws -> [CoreChat] {
        let response: CoreItemsResponse<CoreChat> = try await send("GET", path: "/sync/chats")
        return response.items
    }

    func searchMessages(query: String, limit: Int = 50, includeMedia: Bool = false) async throws -> [CoreMessage] {
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if includeMedia {
            queryItems.append(URLQueryItem(name: "include_media", value: "true"))
        }
        let response: CoreItemsResponse<CoreMessage> = try await send("GET", path: "/sync/search", query: queryItems)
        return response.items
    }

    func listManagementAccounts() async throws -> [CoreAccount] {
        let response: CoreItemsResponse<CoreAccount> = try await send("GET", path: "/manage/accounts")
        return response.items
    }

    func createAccount(_ request: CreateAccountRequest) async throws -> CoreAccount {
        let response: CoreWriteResponse<CoreAccount> = try await send("POST", path: "/manage/accounts", body: request)
        return response.item
    }

    func updateAccountAuth(_ request: AccountAuthUpdateRequest, patch: Bool = true) async throws -> CoreAccount {
        let response: CoreWriteResponse<CoreAccount> = try await send(patch ? "PATCH" : "POST", path: "/manage/accounts/auth", body: request)
        return response.item
    }

    func deleteAccount(accountID: String, source: String = "telegram") async throws -> DeleteResult {
        let response: CoreWriteResponse<DeleteResult> = try await send(
            "DELETE",
            path: "/manage/accounts",
            body: DeleteAccountRequest(accountID: accountID, source: source)
        )
        return response.item
    }

    func authStatus(accountID: String, source: String = "telegram") async throws -> AuthOperationResult {
        let response: CoreWriteResponse<AuthOperationResult> = try await send(
            "POST",
            path: "/manage/accounts/auth/status",
            body: AccountAuthStatusRequest(accountID: accountID, source: source)
        )
        return response.item
    }

    func requestCode(accountID: String, phone: String, source: String = "telegram") async throws -> AuthOperationResult {
        let response: CoreWriteResponse<AuthOperationResult> = try await send(
            "POST",
            path: "/manage/accounts/auth/request-code",
            body: RequestCodeRequest(accountID: accountID, phone: phone, source: source)
        )
        return response.item
    }

    func submitCode(accountID: String, phone: String, code: String, password: String?, source: String = "telegram") async throws -> AuthOperationResult {
        let response: CoreWriteResponse<AuthOperationResult> = try await send(
            "POST",
            path: "/manage/accounts/auth/submit-code",
            body: SubmitCodeRequest(accountID: accountID, phone: phone, code: code, password: password, source: source)
        )
        return response.item
    }

    func listOrigins(accountID: String? = nil, includeArchived: Bool = false) async throws -> [CoreOrigin] {
        var query = [URLQueryItem(name: "include_archived", value: includeArchived ? "true" : "false")]
        if let accountID, !accountID.isEmpty {
            query.append(URLQueryItem(name: "account_id", value: accountID))
        }
        let response: CoreItemsResponse<CoreOrigin> = try await send("GET", path: "/manage/origins", query: query)
        return response.items
    }

    func discoverOrigins(accountID: String, includeTopics: Bool = true, includePrivate: Bool = false, topicLimit: Int = 500) async throws -> DiscoveryResult {
        let response: CoreWriteResponse<DiscoveryResult> = try await send(
            "POST",
            path: "/manage/discover-origins",
            body: DiscoverOriginsRequest(
                accountID: accountID,
                includeTopics: includeTopics,
                includePrivate: includePrivate,
                topicLimit: topicLimit
            )
        )
        return response.item
    }

    func updateOrigin(_ request: OriginUpdateRequest) async throws -> CoreOrigin {
        let response: CoreWriteResponse<CoreOrigin> = try await send("POST", path: "/manage/origins", body: request)
        return response.item
    }

    func archiveOrigin(_ request: ArchiveOriginRequest) async throws -> ArchiveOriginResult {
        let response: CoreWriteResponse<ArchiveOriginResult> = try await send("PATCH", path: "/manage/origins/archive", body: request)
        return response.item
    }

    func setOriginImportant(_ request: OriginImportantRequest) async throws -> CoreOrigin {
        let response: CoreWriteResponse<CoreOrigin> = try await send("PATCH", path: "/manage/origins/important", body: request)
        return response.item
    }

    func deleteOrigin(_ request: DeleteOriginRequest) async throws -> DeleteResult {
        let response: CoreWriteResponse<DeleteResult> = try await send("DELETE", path: "/manage/origins", body: request)
        return response.item
    }

    func listBackupPolicies(accountID: String? = nil) async throws -> [CoreBackupPolicy] {
        var query: [URLQueryItem] = []
        if let accountID, !accountID.isEmpty {
            query.append(URLQueryItem(name: "account_id", value: accountID))
        }
        let response: CoreItemsResponse<CoreBackupPolicy> = try await send("GET", path: "/manage/backup-policies", query: query)
        return response.items
    }

    func setBackupPolicy(_ request: BackupPolicyRequest) async throws -> CoreBackupPolicy {
        let response: CoreWriteResponse<CoreBackupPolicy> = try await send("POST", path: "/manage/backup-policies", body: request)
        return response.item
    }

    func deleteBackupPolicy(_ request: DeleteBackupPolicyRequest) async throws -> DeleteResult {
        let response: CoreWriteResponse<DeleteResult> = try await send("DELETE", path: "/manage/backup-policies", body: request)
        return response.item
    }

    func listParticipants(accountID: String? = nil, originID: Int? = nil) async throws -> [CoreParticipant] {
        var query: [URLQueryItem] = []
        if let accountID, !accountID.isEmpty {
            query.append(URLQueryItem(name: "account_id", value: accountID))
        }
        if let originID {
            query.append(URLQueryItem(name: "origin_id", value: String(originID)))
        }
        let response: CoreItemsResponse<CoreParticipant> = try await send("GET", path: "/manage/participants", query: query)
        return response.items
    }

    func refreshParticipants(accountID: String, originID: Int, limit: Int = 500) async throws -> ParticipantRefreshResult {
        let response: CoreWriteResponse<ParticipantRefreshResult> = try await send(
            "POST",
            path: "/manage/participants/refresh",
            body: RefreshParticipantsRequest(accountID: accountID, originID: originID, limit: limit)
        )
        return response.item
    }

    func createParticipant(_ request: ParticipantRequest) async throws -> CoreParticipant {
        let response: CoreWriteResponse<CoreParticipant> = try await send("POST", path: "/manage/participants", body: request)
        return response.item
    }

    func deleteParticipant(_ request: ParticipantRequest) async throws -> DeleteResult {
        let response: CoreWriteResponse<DeleteResult> = try await send("DELETE", path: "/manage/participants", body: request)
        return response.item
    }

    func listCaptureCursors(accountID: String? = nil) async throws -> [CoreCaptureCursor] {
        var query: [URLQueryItem] = []
        if let accountID, !accountID.isEmpty {
            query.append(URLQueryItem(name: "account_id", value: accountID))
        }
        let response: CoreItemsResponse<CoreCaptureCursor> = try await send("GET", path: "/manage/capture-cursors", query: query)
        return response.items
    }

    func listOperationEvents(accountID: String? = nil, status: String? = nil, limit: Int = 100) async throws -> [CoreOperationEvent] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let accountID, !accountID.isEmpty {
            query.append(URLQueryItem(name: "account_id", value: accountID))
        }
        if let status, !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        let response: CoreItemsResponse<CoreOperationEvent> = try await send("GET", path: "/manage/operation-events", query: query)
        return response.items
    }

    func deleteOperationEvent(id: Int) async throws -> OperationEventDeleteResult {
        let response: CoreWriteResponse<OperationEventDeleteResult> = try await send(
            "DELETE",
            path: "/manage/operation-events",
            body: DeleteOperationEventRequest(id: id)
        )
        return response.item
    }

    func deleteOperationEvents(ids: [Int]) async throws -> OperationEventDeleteResult {
        let response: CoreWriteResponse<OperationEventDeleteResult> = try await send(
            "DELETE",
            path: "/manage/operation-events",
            body: DeleteOperationEventRequest(id: nil, ids: ids)
        )
        return response.item
    }

    func fetchDailyPackageSchedule() async throws -> DailyPackageSchedule {
        let response: CoreWriteResponse<DailyPackageSchedule> = try await send("GET", path: "/manage/daily-package-schedule")
        return response.item
    }

    func updateDailyPackageSchedule(_ request: DailyPackageScheduleInput) async throws -> DailyPackageSchedule {
        let response: CoreWriteResponse<DailyPackageSchedule> = try await send("PATCH", path: "/manage/daily-package-schedule", body: request)
        return response.item
    }

    func runDailyPackage(_ request: DailyPackageRunInput) async throws -> DailyPackageRun {
        let response: CoreWriteResponse<DailyPackageRun> = try await send("POST", path: "/manage/daily-packages", body: request)
        return response.item
    }

    func listDailyPackageRuns(status: String? = nil, limit: Int = 100) async throws -> [DailyPackageRun] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let status, !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        let response: CoreItemsResponse<DailyPackageRun> = try await send("GET", path: "/manage/daily-package-runs", query: query)
        return response.items
    }

    func fetchDailyPackageRunContent(runID: String, format: String = "md") async throws -> String {
        try await text("GET", path: "/manage/daily-package-runs/content", query: [
            URLQueryItem(name: "run_id", value: runID),
            URLQueryItem(name: "format", value: format)
        ])
    }

    func runDailySummary(_ request: DailySummaryRunInput) async throws -> DailySummaryRun {
        let response: CoreWriteResponse<DailySummaryRun> = try await send("POST", path: "/manage/daily-summaries", body: request)
        return response.item
    }

    func listDailySummaryRuns(packageRunID: String? = nil, status: String? = nil, limit: Int = 100) async throws -> [DailySummaryRun] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let packageRunID, !packageRunID.isEmpty {
            query.append(URLQueryItem(name: "package_run_id", value: packageRunID))
        }
        if let status, !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        let response: CoreItemsResponse<DailySummaryRun> = try await send("GET", path: "/manage/daily-summary-runs", query: query)
        return response.items
    }

    func fetchDailySummaryRunContent(runID: String) async throws -> String {
        try await text("GET", path: "/manage/daily-summary-runs/content", query: [
            URLQueryItem(name: "run_id", value: runID)
        ])
    }

    func runDailySummaryJob(_ request: DailySummaryRunInput) async throws -> DailySummaryJob {
        let response: CoreWriteResponse<DailySummaryJob> = try await send("POST", path: "/manage/daily-summary-jobs", body: request)
        return response.item
    }

    func listDailySummaryJobs(jobID: String? = nil, status: String? = nil, limit: Int = 100) async throws -> [DailySummaryJob] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let jobID, !jobID.isEmpty {
            query.append(URLQueryItem(name: "job_id", value: jobID))
        }
        if let status, !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        let response: CoreItemsResponse<DailySummaryJob> = try await send("GET", path: "/manage/daily-summary-jobs", query: query)
        return response.items
    }

    func cancelDailySummaryJob(jobID: String) async throws -> DailySummaryJob {
        let response: CoreWriteResponse<DailySummaryJob> = try await send(
            "PATCH",
            path: "/manage/daily-summary-jobs/cancel",
            body: DailySummaryJobCancelInput(jobID: jobID)
        )
        return response.item
    }

    func listDailySummaryRecords(
        summaryID: String? = nil,
        runID: String? = nil,
        packageRunID: String? = nil,
        date: String? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        provider: String? = nil,
        recordType: String? = nil,
        important: Bool? = nil,
        tag: String? = nil,
        tags: String? = nil,
        query searchText: String? = nil,
        includeDeleted: Bool = false,
        deleted: Bool? = nil,
        includeContent: Bool = false,
        limit: Int = 100
    ) async throws -> [DailySummaryRecord] {
        var query = [
            URLQueryItem(name: "include_deleted", value: includeDeleted ? "true" : "false"),
            URLQueryItem(name: "include_content", value: includeContent ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let summaryID, !summaryID.isEmpty {
            query.append(URLQueryItem(name: "summary_id", value: summaryID))
        }
        if let runID, !runID.isEmpty {
            query.append(URLQueryItem(name: "run_id", value: runID))
        }
        if let packageRunID, !packageRunID.isEmpty {
            query.append(URLQueryItem(name: "package_run_id", value: packageRunID))
        }
        if let date, !date.isEmpty {
            query.append(URLQueryItem(name: "date", value: date))
        }
        if let dateFrom, !dateFrom.isEmpty {
            query.append(URLQueryItem(name: "date_from", value: dateFrom))
        }
        if let dateTo, !dateTo.isEmpty {
            query.append(URLQueryItem(name: "date_to", value: dateTo))
        }
        if let provider, !provider.isEmpty {
            query.append(URLQueryItem(name: "provider", value: provider))
        }
        if let recordType, !recordType.isEmpty {
            query.append(URLQueryItem(name: "record_type", value: recordType))
        }
        if let important {
            query.append(URLQueryItem(name: "important", value: important ? "true" : "false"))
        }
        if let tag, !tag.isEmpty {
            query.append(URLQueryItem(name: "tag", value: tag))
        }
        if let tags, !tags.isEmpty {
            query.append(URLQueryItem(name: "tags", value: tags))
        }
        if let searchText, !searchText.isEmpty {
            query.append(URLQueryItem(name: "q", value: searchText))
        }
        if let deleted {
            query.append(URLQueryItem(name: "deleted", value: deleted ? "true" : "false"))
        }
        let response: CoreItemsResponse<DailySummaryRecord> = try await send("GET", path: "/manage/daily-summary-records", query: query)
        return response.items
    }

    func fetchDailySummaryRecord(
        summaryID: String? = nil,
        runID: String? = nil,
        recordType: String? = nil,
        includeDeleted: Bool = false
    ) async throws -> DailySummaryRecord {
        var query = [URLQueryItem(name: "include_deleted", value: includeDeleted ? "true" : "false")]
        if let summaryID, !summaryID.isEmpty {
            query.append(URLQueryItem(name: "summary_id", value: summaryID))
        }
        if let runID, !runID.isEmpty {
            query.append(URLQueryItem(name: "run_id", value: runID))
        }
        if let recordType, !recordType.isEmpty {
            query.append(URLQueryItem(name: "record_type", value: recordType))
        }
        let response: CoreWriteResponse<DailySummaryRecord> = try await send("GET", path: "/manage/daily-summary-records/item", query: query)
        return response.item
    }

    func listDailyMessagePoints(
        pointID: String? = nil,
        runID: String? = nil,
        packageRunID: String? = nil,
        date: String? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        source: String? = nil,
        accountID: String? = nil,
        originID: Int? = nil,
        topicID: Int? = nil,
        messageID: Int? = nil,
        tags: [String] = [],
        tagsCSV: String? = nil,
        importanceMin: Int? = nil,
        importanceMax: Int? = nil,
        originImportant: Bool? = nil,
        query searchText: String? = nil,
        includeIncomplete: Bool = false,
        limit: Int = 100
    ) async throws -> [DailyMessagePoint] {
        var query = [
            URLQueryItem(name: "include_incomplete", value: includeIncomplete ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let pointID, !pointID.isEmpty {
            query.append(URLQueryItem(name: "point_id", value: pointID))
        }
        if let runID, !runID.isEmpty {
            query.append(URLQueryItem(name: "run_id", value: runID))
        }
        if let packageRunID, !packageRunID.isEmpty {
            query.append(URLQueryItem(name: "package_run_id", value: packageRunID))
        }
        if let date, !date.isEmpty {
            query.append(URLQueryItem(name: "date", value: date))
        }
        if let dateFrom, !dateFrom.isEmpty {
            query.append(URLQueryItem(name: "date_from", value: dateFrom))
        }
        if let dateTo, !dateTo.isEmpty {
            query.append(URLQueryItem(name: "date_to", value: dateTo))
        }
        if let source, !source.isEmpty {
            query.append(URLQueryItem(name: "source", value: source))
        }
        if let accountID, !accountID.isEmpty {
            query.append(URLQueryItem(name: "account_id", value: accountID))
        }
        if let originID {
            query.append(URLQueryItem(name: "origin_id", value: String(originID)))
        }
        if let topicID {
            query.append(URLQueryItem(name: "topic_id", value: String(topicID)))
        }
        if let messageID {
            query.append(URLQueryItem(name: "message_id", value: String(messageID)))
        }
        for tag in tags where !tag.isEmpty {
            query.append(URLQueryItem(name: "tag", value: tag))
        }
        if let tagsCSV, !tagsCSV.isEmpty {
            query.append(URLQueryItem(name: "tags", value: tagsCSV))
        }
        if let importanceMin {
            query.append(URLQueryItem(name: "importance_min", value: String(importanceMin)))
        }
        if let importanceMax {
            query.append(URLQueryItem(name: "importance_max", value: String(importanceMax)))
        }
        if let originImportant {
            query.append(URLQueryItem(name: "origin_important", value: originImportant ? "true" : "false"))
        }
        if let searchText, !searchText.isEmpty {
            query.append(URLQueryItem(name: "q", value: searchText))
        }
        let response: CoreItemsResponse<DailyMessagePoint> = try await send(
            "GET",
            path: "/manage/daily-message-points",
            query: query
        )
        return response.items
    }

    func fetchDailyMessagePoint(pointID: String) async throws -> DailyMessagePoint {
        let response: CoreWriteResponse<DailyMessagePoint> = try await send(
            "GET",
            path: "/manage/daily-message-points/item",
            query: [URLQueryItem(name: "point_id", value: pointID)]
        )
        return response.item
    }

    func deleteDailySummaryRecords(summaryIDs: [String]) async throws -> DailySummaryRecordDeleteResult {
        let response: CoreWriteResponse<DailySummaryRecordDeleteResult> = try await send(
            "DELETE",
            path: "/manage/daily-summary-records",
            body: DailySummaryRecordDeleteInput(summaryID: nil, ids: nil, summaryIDs: summaryIDs, deleted: true)
        )
        return response.item
    }

    func restoreDailySummaryRecords(summaryIDs: [String]) async throws -> DailySummaryRecordDeleteResult {
        let response: CoreWriteResponse<DailySummaryRecordDeleteResult> = try await send(
            "PATCH",
            path: "/manage/daily-summary-records",
            body: DailySummaryRecordDeleteInput(summaryID: nil, ids: nil, summaryIDs: summaryIDs, deleted: false)
        )
        return response.item
    }

    func listMediaFiles(accountID: String? = nil, chatID: Int? = nil, messageID: Int? = nil, limit: Int = 500) async throws -> [CoreMediaFile] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let accountID, !accountID.isEmpty {
            query.append(URLQueryItem(name: "account_id", value: accountID))
        }
        if let chatID {
            query.append(URLQueryItem(name: "chat_id", value: String(chatID)))
        }
        if let messageID {
            query.append(URLQueryItem(name: "message_id", value: String(messageID)))
        }
        let response: CoreItemsResponse<CoreMediaFile> = try await send("GET", path: "/sync/media-files", query: query)
        return response.items
    }

    func downloadMediaContent(source: String = "telegram", accountID: String, chatID: Int, messageID: Int, fileIndex: Int = 0) async throws -> Data {
        try await data("GET", path: "/sync/media-files/content", query: [
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "account_id", value: accountID),
            URLQueryItem(name: "chat_id", value: String(chatID)),
            URLQueryItem(name: "message_id", value: String(messageID)),
            URLQueryItem(name: "file_index", value: String(fileIndex))
        ])
    }

    func downloadMediaContent(for file: CoreMediaFile) async throws -> Data {
        try await downloadMediaContent(
            source: file.source,
            accountID: file.accountID,
            chatID: file.chatID,
            messageID: file.messageID,
            fileIndex: file.fileIndex
        )
    }

    private func send<Response: Decodable>(_ method: String, path: String, query: [URLQueryItem] = []) async throws -> Response {
        try await send(method, path: path, query: query, body: Optional<String>.none)
    }

    private func send<Response: Decodable, Body: Encodable>(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Body?
    ) async throws -> Response {
        var request = try makeRequest(method, path: path, query: query)
        if let body {
            request.httpBody = try JSONEncoder.core.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await transport.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                let payload = try? JSONDecoder.core.decode(CoreAPIErrorPayload.self, from: data)
                let detail = payload?.detail ?? payload?.message ?? payload?.error ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
                throw CoreAPIError.httpStatus(response.statusCode, detail)
            }
            return try JSONDecoder.core.decode(Response.self, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as CoreAPIError {
            throw error
        } catch let error as DecodingError {
            throw CoreAPIError.transport("Could not decode core response: \(error)")
        } catch {
            throw CoreAPIError.transport(error.localizedDescription)
        }
    }

    private func data(_ method: String, path: String, query: [URLQueryItem] = []) async throws -> Data {
        let request = try makeRequest(method, path: path, query: query, accept: "application/octet-stream")
        do {
            let (data, response) = try await transport.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                let payload = try? JSONDecoder.core.decode(CoreAPIErrorPayload.self, from: data)
                let detail = payload?.detail ?? payload?.message ?? payload?.error ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
                throw CoreAPIError.httpStatus(response.statusCode, detail)
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as CoreAPIError {
            throw error
        } catch {
            throw CoreAPIError.transport(error.localizedDescription)
        }
    }

    private func text(_ method: String, path: String, query: [URLQueryItem] = []) async throws -> String {
        let request = try makeRequest(method, path: path, query: query, accept: "text/markdown")
        do {
            let (data, response) = try await transport.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                let payload = try? JSONDecoder.core.decode(CoreAPIErrorPayload.self, from: data)
                let detail = payload?.detail ?? payload?.message ?? payload?.error ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
                throw CoreAPIError.httpStatus(response.statusCode, detail)
            }
            guard let value = String(data: data, encoding: .utf8) else {
                throw CoreAPIError.invalidResponse
            }
            return value
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as CoreAPIError {
            throw error
        } catch {
            throw CoreAPIError.transport(error.localizedDescription)
        }
    }

    private func makeRequest(_ method: String, path: String, query: [URLQueryItem], accept: String = "application/json") throws -> URLRequest {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let token = try tokenProvider.token(), !token.isEmpty {
            switch authMode {
            case .bearer:
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            case .apiToken:
                request.setValue(token, forHTTPHeaderField: "X-Api-Token")
            }
        }
        return request
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = baseURL
        for component in cleanPath.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw CoreAPIError.invalidBaseURL(baseURL.absoluteString)
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let finalURL = components.url else {
            throw CoreAPIError.invalidBaseURL(baseURL.absoluteString)
        }
        return finalURL
    }
}
