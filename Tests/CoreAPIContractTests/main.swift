import Foundation

@main
enum CoreAPIContractTests {
    static func main() async {
        var runner = ContractRunner()
        await runner.run("health decodes state") { try await testHealthDecodesState() }
        await runner.run("state uses bearer token") { try await testStateUsesBearerToken() }
        await runner.run("capabilities uses api token") { try await testCapabilitiesUsesAPIToken() }
        await runner.run("messages and search decode") { try await testMessagesAndSearchDecode() }
        await runner.run("accounts and auth flow") { try await testAccountsAndAuthFlow() }
        await runner.run("origins and policies") { try await testOriginsAndPolicies() }
        await runner.run("diagnostics endpoints") { try await testDiagnosticsEndpoints() }
        await runner.run("http errors map detail") { try await testHTTPErrorMapping() }
        runner.finish()
    }

    static func testHealthDecodesState() async throws {
        let client = makeClient(
            expectedPath: "/healthz",
            responseJSON:
            """
            {
              "ok": true,
              "database_id": "db",
              "schema_version": "2",
              "last_event_seq": 12,
              "message_count": 34,
              "operation_error_count": 0,
              "server_time": "2026-07-03T00:00:00+00:00"
            }
            """
        )

        let state = try await client.health()

        try expectEqual(state.ok, true)
        try expectEqual(state.databaseID, "db")
        try expectEqual(state.schemaVersion, "2")
    }

    static func testStateUsesBearerToken() async throws {
        let client = makeClient(
            expectedPath: "/sync/state",
            responseJSON:
            """
            {
              "database_id": "db",
              "schema_version": "2",
              "last_event_seq": 12,
              "message_count": 34,
              "operation_error_count": 1,
              "server_time": "2026-07-03T00:00:00+00:00"
            }
            """,
            tokenProvider: FixedTokenProvider(value: "secret"),
            verify: { request in
                try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
                try expectNil(request.value(forHTTPHeaderField: "X-Api-Token"))
            }
        )

        let state = try await client.fetchSyncState()

        try expectEqual(state.databaseID, "db")
        try expectEqual(state.lastEventSeq, 12)
        try expectEqual(state.operationErrorCount, 1)
    }

    static func testCapabilitiesUsesAPIToken() async throws {
        let client = makeClient(
            expectedPath: "/manage/capabilities",
            responseJSON:
            """
            {
              "mode": "single_user",
              "sync": ["messages", "media_files"],
              "management": ["accounts", "origins"],
              "auth_flow": {"request_code": true}
            }
            """,
            tokenProvider: FixedTokenProvider(value: "secret"),
            authMode: .apiToken,
            verify: { request in
                try expectEqual(request.value(forHTTPHeaderField: "X-Api-Token"), "secret")
                try expectNil(request.value(forHTTPHeaderField: "Authorization"))
            }
        )

        let capabilities = try await client.fetchCapabilities()

        try expectEqual(capabilities.mode, "single_user")
        try expectEqual(capabilities.sync ?? [], ["messages", "media_files"])
    }

    static func testMessagesAndSearchDecode() async throws {
        let recentClient = makeClient(
            expectedPath: "/sync/messages",
            expectedQueryItems: ["latest=true", "limit=100"],
            responseJSON:
            """
            {
              "items": [
                {
                  "event_seq": 7,
                  "source": "telegram",
                  "account_id": "main",
                  "chat_id": -1001,
                  "message_id": 99,
                  "chat_title": "Source",
                  "sent_at": "2026-07-03T00:00:00+00:00",
                  "text": "hello",
                  "has_media": 1,
                  "version": 1
                }
              ],
              "next_cursor": 7,
              "has_more": false
            }
            """
        )

        let page = try await recentClient.fetchRecentMessages(limit: 100)
        try expectEqual(page.items.first?.displayChat, "Source")
        try expectEqual(page.items.first?.hasMedia, true)
        try expectEqual(page.nextCursor, 7)

        let searchClient = makeClient(
            expectedPath: "/sync/search",
            expectedQueryItems: ["q=needle", "limit=50"],
            responseJSON:
            """
            {
              "items": [
                {
                  "source": "telegram",
                  "account_id": "main",
                  "chat_id": -1001,
                  "message_id": 100,
                  "chat_title": "Ops",
                  "sender_name": "Ada",
                  "sent_at": "2026-07-03T00:00:00+00:00",
                  "deleted_at": "2026-07-03T00:05:00+00:00",
                  "text": "needle",
                  "has_media": false,
                  "permalink": "https://t.me/c/1/100"
                }
              ]
            }
            """
        )

        let messages = try await searchClient.searchMessages(query: "needle", limit: 50)
        try expectEqual(messages.count, 1)
        try expectEqual(messages.first?.displaySender, "Ada")
        try expectEqual(messages.first?.isDeleted, true)
        try expectEqual(messages.first?.permalink, "https://t.me/c/1/100")
    }

    static func testAccountsAndAuthFlow() async throws {
        let accountsClient = makeClient(
            expectedPath: "/manage/accounts",
            responseJSON:
            """
            {
              "items": [
                {
                  "source": "telegram",
                  "account_id": "main",
                  "display_name": "Main",
                  "auth_state": "signed_in",
                  "session_name": "main",
                  "last_error": "previous failure"
                }
              ]
            }
            """
        )
        let accounts = try await accountsClient.listManagementAccounts()
        try expectEqual(accounts.first?.title, "Main")
        try expectEqual(accounts.first?.lastError, "previous failure")

        let createClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/accounts",
            responseJSON:
            """
            {"item": {"source": "telegram", "account_id": "main", "display_name": "Main"}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["account_id"] as? String, "main")
                try expectEqual(body["session_dir"] as? String, "/tmp/session")
            }
        )
        let created = try await createClient.createAccount(
            CreateAccountRequest(accountID: "main", displayName: "Main", phone: "+100", sessionName: "main", sessionDir: "/tmp/session")
        )
        try expectEqual(created.accountID, "main")

        let statusClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/accounts/auth/status",
            responseJSON: #"{"item": {"account_id": "main", "status": "signed_in"}}"#,
            verify: { request in
                try expectEqual(try requestJSONObject(request)["account_id"] as? String, "main")
            }
        )
        try expectEqual(try await statusClient.authStatus(accountID: "main").status, "signed_in")

        let requestCodeClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/accounts/auth/request-code",
            responseJSON: #"{"item": {"account_id": "main", "phone": "+100", "message": "sent"}}"#,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["account_id"] as? String, "main")
                try expectEqual(body["phone"] as? String, "+100")
            }
        )
        try expectEqual(try await requestCodeClient.requestCode(accountID: "main", phone: "+100").message, "sent")

        let submitCodeClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/accounts/auth/submit-code",
            responseJSON: #"{"item": {"account_id": "main", "status": "signed_in"}}"#,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["code"] as? String, "12345")
                try expectEqual(body["password"] as? String, "2fa")
            }
        )
        try expectEqual(
            try await submitCodeClient.submitCode(accountID: "main", phone: "+100", code: "12345", password: "2fa").status,
            "signed_in"
        )
    }

    static func testOriginsAndPolicies() async throws {
        let originsClient = makeClient(
            expectedPath: "/manage/origins",
            expectedQueryItems: ["account_id=main", "include_archived=true"],
            responseJSON:
            """
            {
              "items": [
                {
                  "source": "telegram",
                  "account_id": "main",
                  "origin_id": -1001,
                  "topic_id": 0,
                  "origin_type": "group",
                  "title": "Group",
                  "is_forum": true,
                  "backup_policy": {
                    "source": "telegram",
                    "account_id": "main",
                    "origin_id": -1001,
                    "topic_id": 0,
                    "enabled": 1,
                    "capture_text": true,
                    "capture_media_metadata": true,
                    "download_media": false,
                    "tags": "prod,ops"
                  }
                },
                {
                  "source": "telegram",
                  "account_id": "main",
                  "origin_id": -1001,
                  "topic_id": 5,
                  "origin_type": "topic",
                  "title": "Deploys",
                  "is_forum": false
                }
              ]
            }
            """
        )
        let origins = try await originsClient.listOrigins(accountID: "main", includeArchived: true)
        try expectEqual(origins.count, 2)
        try expectEqual(origins.first?.backupPolicy?.enabled, true)
        try expectEqual(origins.last?.isTopic, true)

        let discoverClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/discover-origins",
            responseJSON: #"{"item": {"account_id": "main", "origins": 2, "topics": 1, "skipped_private": 3}}"#,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["account_id"] as? String, "main")
                try expectEqual(body["include_topics"] as? Bool, true)
                try expectEqual(body["include_private"] as? Bool, false)
                try expectEqual(body["topic_limit"] as? Int, 500)
            }
        )
        try expectEqual(try await discoverClient.discoverOrigins(accountID: "main").topics, 1)

        let archiveClient = makeClient(
            expectedMethod: "PATCH",
            expectedPath: "/manage/origins/archive",
            responseJSON:
            """
            {"item": {"source": "telegram", "account_id": "main", "origin_id": -1001, "topic_id": 0, "archived": true, "changed_rows": 1}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["archived"] as? Bool, true)
                try expectEqual(body["origin_id"] as? Int, -1001)
            }
        )
        try expectEqual(
            try await archiveClient.archiveOrigin(ArchiveOriginRequest(accountID: "main", originID: -1001, archived: true)).archived,
            true
        )

        let policyClient = makeClient(
            expectedMethod: "PATCH",
            expectedPath: "/manage/backup-policies",
            responseJSON:
            """
            {"item": {"source": "telegram", "account_id": "main", "origin_id": -1001, "topic_id": 0, "enabled": true, "capture_text": true, "capture_media_metadata": true, "download_media": true, "tags": "prod"}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["download_media"] as? Bool, true)
                try expectEqual(body["tags"] as? String, "prod")
            }
        )
        let policy = try await policyClient.setBackupPolicy(
            BackupPolicyRequest(
                accountID: "main",
                originID: -1001,
                enabled: true,
                captureText: true,
                captureMediaMetadata: true,
                downloadMedia: true,
                tags: "prod"
            )
        )
        try expectEqual(policy.downloadMedia, true)
    }

    static func testDiagnosticsEndpoints() async throws {
        let participantsClient = makeClient(
            expectedPath: "/manage/participants",
            expectedQueryItems: ["account_id=main", "origin_id=-1001"],
            responseJSON:
            """
            {
              "items": [
                {
                  "source": "telegram",
                  "account_id": "main",
                  "origin_id": -1001,
                  "user_id": 42,
                  "username": "ada",
                  "is_bot": 0,
                  "role": "admin",
                  "raw_json": {"rank": "owner"}
                }
              ]
            }
            """
        )
        let participants = try await participantsClient.listParticipants(accountID: "main", originID: -1001)
        try expectEqual(participants.first?.username, "ada")
        try expectEqual(participants.first?.isBot, false)

        let refreshClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/participants/refresh",
            responseJSON: #"{"item": {"account_id": "main", "origin_id": -1001, "refreshed": 12}}"#,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["origin_id"] as? Int, -1001)
                try expectEqual(body["limit"] as? Int, 500)
            }
        )
        try expectEqual(try await refreshClient.refreshParticipants(accountID: "main", originID: -1001).refreshed, 12)

        let cursorsClient = makeClient(
            expectedPath: "/manage/capture-cursors",
            expectedQueryItems: ["account_id=main"],
            responseJSON:
            """
            {
              "items": [
                {
                  "source": "telegram",
                  "account_id": "main",
                  "origin_id": -1001,
                  "topic_id": 0,
                  "last_message_id": 99,
                  "origin_title": "Group"
                }
              ]
            }
            """
        )
        try expectEqual(try await cursorsClient.listCaptureCursors(accountID: "main").first?.lastMessageID, 99)

        let eventsClient = makeClient(
            expectedPath: "/manage/operation-events",
            expectedQueryItems: ["account_id=main", "status=failed", "limit=100"],
            responseJSON:
            """
            {
              "items": [
                {
                  "id": 1,
                  "source": "telegram",
                  "account_id": "main",
                  "operation": "capture",
                  "status": "failed",
                  "error_code": "rate_limited",
                  "raw_json": {"retry_after": 30}
                }
              ]
            }
            """
        )
        try expectEqual(try await eventsClient.listOperationEvents(accountID: "main", status: "failed").first?.errorCode, "rate_limited")

        let deleteEventClient = makeClient(
            expectedMethod: "DELETE",
            expectedPath: "/manage/operation-events",
            responseJSON: #"{"item": {"deleted_rows": 1}}"#,
            verify: { request in
                try expectEqual(try requestJSONObject(request)["id"] as? Int, 1)
            }
        )
        try expectEqual(try await deleteEventClient.deleteOperationEvent(id: 1).deletedRows, 1)

        let mediaClient = makeClient(
            expectedPath: "/sync/media-files",
            expectedQueryItems: ["account_id=main", "chat_id=-1001", "message_id=99", "limit=500"],
            responseJSON:
            """
            {
              "items": [
                {
                  "source": "telegram",
                  "account_id": "main",
                  "chat_id": -1001,
                  "message_id": 99,
                  "file_index": 0,
                  "file_path": "/archive/file.jpg",
                  "media_kind": "photo",
                  "file_size": 123
                }
              ]
            }
            """
        )
        try expectEqual(try await mediaClient.listMediaFiles(accountID: "main", chatID: -1001, messageID: 99).first?.mediaKind, "photo")
    }

    static func testHTTPErrorMapping() async throws {
        let client = makeClient(
            expectedPath: "/sync/state",
            responseJSON: #"{"error": "unauthorized", "detail": "bad token"}"#,
            status: 401
        )

        do {
            let _: CoreState = try await client.fetchSyncState()
            throw ContractError.failure("Expected request failure")
        } catch CoreAPIError.httpStatus(let status, let detail) {
            try expectEqual(status, 401)
            try expectEqual(detail, "bad token")
        }
    }
}

private struct ContractRunner {
    private var failures = 0

    mutating func run(_ name: String, _ block: () async throws -> Void) async {
        do {
            try await block()
            print("PASS \(name)")
        } catch {
            failures += 1
            print("FAIL \(name): \(error)")
        }
    }

    func finish() -> Never {
        if failures == 0 {
            print("Core API contract tests passed")
            exit(0)
        }
        print("Core API contract tests failed: \(failures)")
        exit(1)
    }
}

private func makeClient(
    expectedMethod: String = "GET",
    expectedPath: String,
    expectedQueryItems: [String] = [],
    responseJSON: String,
    status: Int = 200,
    tokenProvider: any AuthTokenProvider = EmptyTokenProvider(),
    authMode: CoreAuthMode = .bearer,
    verify: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
) -> CoreAPIClient {
    let transport = MockTransport { request in
        try expectEqual(request.httpMethod, expectedMethod)
        try expectEqual(request.url?.path, expectedPath)
        let query = request.url?.query ?? ""
        for item in expectedQueryItems {
            try expectTrue(query.contains(item), "Expected query to contain \(item), got \(query)")
        }
        try verify(request)
        return try jsonResponse(responseJSON, status: status)
    }
    return CoreAPIClient(
        baseURL: URL(string: "http://core.local")!,
        tokenProvider: tokenProvider,
        authMode: authMode,
        transport: transport
    )
}

private struct MockTransport: CoreHTTPTransport {
    var handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

private func requestJSONObject(_ request: URLRequest) throws -> [String: Any] {
    guard let data = request.httpBody else {
        throw ContractError.failure("Expected JSON request body")
    }
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any] else {
        throw ContractError.failure("Expected JSON object body")
    }
    return dictionary
}

private func jsonResponse(_ json: String, status: Int = 200) throws -> (Data, HTTPURLResponse) {
    let url = URL(string: "http://core.local")!
    let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    return (Data(json.utf8), response)
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String? = nil) throws {
    guard actual == expected else {
        throw ContractError.failure(message ?? "Expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

private func expectNil<T>(_ value: T?, _ message: String? = nil) throws {
    guard value == nil else {
        throw ContractError.failure(message ?? "Expected nil, got \(String(describing: value))")
    }
}

private func expectTrue(_ value: Bool, _ message: String? = nil) throws {
    guard value else {
        throw ContractError.failure(message ?? "Expected true")
    }
}

private enum ContractError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case .failure(let message):
            message
        }
    }
}
