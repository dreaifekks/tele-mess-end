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

    func fetchRecentMessages(limit: Int = 100) async throws -> CorePage<CoreMessage> {
        try await send("GET", path: "/sync/messages", query: [
            URLQueryItem(name: "latest", value: "true"),
            URLQueryItem(name: "limit", value: String(limit))
        ])
    }

    func fetchMessages(after cursor: Int, limit: Int = 500) async throws -> CorePage<CoreMessage> {
        try await send("GET", path: "/sync/messages", query: [
            URLQueryItem(name: "after", value: String(cursor)),
            URLQueryItem(name: "limit", value: String(limit))
        ])
    }

    func searchMessages(query: String, limit: Int = 50) async throws -> [CoreMessage] {
        let response: CoreItemsResponse<CoreMessage> = try await send("GET", path: "/sync/search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ])
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

    func archiveOrigin(_ request: ArchiveOriginRequest) async throws -> ArchiveOriginResult {
        let response: CoreWriteResponse<ArchiveOriginResult> = try await send("PATCH", path: "/manage/origins/archive", body: request)
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
        let response: CoreWriteResponse<CoreBackupPolicy> = try await send("PATCH", path: "/manage/backup-policies", body: request)
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

    private func send<Response: Decodable>(_ method: String, path: String, query: [URLQueryItem] = []) async throws -> Response {
        try await send(method, path: path, query: query, body: Optional<String>.none)
    }

    private func send<Response: Decodable, Body: Encodable>(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Body?
    ) async throws -> Response {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try tokenProvider.token(), !token.isEmpty {
            switch authMode {
            case .bearer:
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            case .apiToken:
                request.setValue(token, forHTTPHeaderField: "X-Api-Token")
            }
        }
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
        } catch let error as CoreAPIError {
            throw error
        } catch let error as DecodingError {
            throw CoreAPIError.transport("Could not decode core response: \(error)")
        } catch {
            throw CoreAPIError.transport(error.localizedDescription)
        }
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
