import Foundation
import XCTest
@testable import TeleMessEnd

final class CoreAPIClientTests: XCTestCase {
    func testAddsBearerTokenAndDecodesState() async throws {
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
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
                XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Token"))
            }
        )

        let state = try await client.fetchSyncState()

        XCTAssertEqual(state.databaseID, "db")
        XCTAssertEqual(state.lastEventSeq, 12)
        XCTAssertEqual(state.operationErrorCount, 1)
    }

    func testAddsApiTokenHeaderAndDecodesCapabilities() async throws {
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
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Token"), "secret")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            }
        )

        let capabilities = try await client.fetchCapabilities()

        XCTAssertEqual(capabilities.mode, "single_user")
        XCTAssertEqual(capabilities.sync, ["messages", "media_files"])
    }

    func testDecodesRecentMessagesWithIntegerMediaFlag() async throws {
        let client = makeClient(
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

        let page = try await client.fetchRecentMessages(limit: 100)

        XCTAssertEqual(page.items.first?.displayChat, "Source")
        XCTAssertEqual(page.items.first?.hasMedia, true)
        XCTAssertEqual(page.nextCursor, 7)
    }

    func testSearchMessagesEndpointDecodesItems() async throws {
        let client = makeClient(
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

        let messages = try await client.searchMessages(query: "needle", limit: 50)

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.displaySender, "Ada")
        XCTAssertEqual(messages.first?.isDeleted, true)
        XCTAssertEqual(messages.first?.permalink, "https://t.me/c/1/100")
    }

    func testAccountsAndTelegramAuthEndpointFamily() async throws {
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
        XCTAssertEqual(accounts.first?.title, "Main")
        XCTAssertEqual(accounts.first?.lastError, "previous failure")

        let createClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/accounts",
            responseJSON:
            """
            {"item": {"source": "telegram", "account_id": "main", "display_name": "Main"}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                XCTAssertEqual(body["account_id"] as? String, "main")
                XCTAssertEqual(body["session_dir"] as? String, "/tmp/session")
            }
        )
        let created = try await createClient.createAccount(
            CreateAccountRequest(accountID: "main", displayName: "Main", phone: "+100", sessionName: "main", sessionDir: "/tmp/session")
        )
        XCTAssertEqual(created.accountID, "main")

        let statusClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/accounts/auth/status",
            responseJSON:
            """
            {"item": {"account_id": "main", "status": "signed_in"}}
            """,
            verify: { request in
                XCTAssertEqual(try requestJSONObject(request)["account_id"] as? String, "main")
            }
        )
        XCTAssertEqual(try await statusClient.authStatus(accountID: "main").status, "signed_in")

        let requestCodeClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/accounts/auth/request-code",
            responseJSON:
            """
            {"item": {"account_id": "main", "phone": "+100", "message": "sent"}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                XCTAssertEqual(body["account_id"] as? String, "main")
                XCTAssertEqual(body["phone"] as? String, "+100")
            }
        )
        XCTAssertEqual(try await requestCodeClient.requestCode(accountID: "main", phone: "+100").message, "sent")

        let submitCodeClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/accounts/auth/submit-code",
            responseJSON:
            """
            {"item": {"account_id": "main", "status": "signed_in"}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                XCTAssertEqual(body["code"] as? String, "12345")
                XCTAssertEqual(body["password"] as? String, "2fa")
            }
        )
        XCTAssertEqual(try await submitCodeClient.submitCode(accountID: "main", phone: "+100", code: "12345", password: "2fa").status, "signed_in")
    }

    func testOriginsAndBackupPolicyEndpointFamilies() async throws {
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
        XCTAssertEqual(origins.count, 2)
        XCTAssertEqual(origins.first?.backupPolicy?.enabled, true)
        XCTAssertEqual(origins.last?.isTopic, true)

        let discoverClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/discover-origins",
            responseJSON:
            """
            {"item": {"account_id": "main", "origins": 2, "topics": 1, "skipped_private": 3}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                XCTAssertEqual(body["account_id"] as? String, "main")
                XCTAssertEqual(body["include_topics"] as? Bool, true)
                XCTAssertEqual(body["include_private"] as? Bool, false)
                XCTAssertEqual(body["topic_limit"] as? Int, 500)
            }
        )
        XCTAssertEqual(try await discoverClient.discoverOrigins(accountID: "main").topics, 1)

        let archiveClient = makeClient(
            expectedMethod: "PATCH",
            expectedPath: "/manage/origins/archive",
            responseJSON:
            """
            {"item": {"source": "telegram", "account_id": "main", "origin_id": -1001, "topic_id": 0, "archived": true, "changed_rows": 1}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                XCTAssertEqual(body["archived"] as? Bool, true)
                XCTAssertEqual(body["origin_id"] as? Int, -1001)
            }
        )
        XCTAssertEqual(
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
                XCTAssertEqual(body["download_media"] as? Bool, true)
                XCTAssertEqual(body["tags"] as? String, "prod")
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
        XCTAssertEqual(policy.downloadMedia, true)
    }

    func testDiagnosticsEndpointFamilies() async throws {
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
        XCTAssertEqual(participants.first?.username, "ada")
        XCTAssertEqual(participants.first?.isBot, false)

        let refreshClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/participants/refresh",
            responseJSON:
            """
            {"item": {"account_id": "main", "origin_id": -1001, "refreshed": 12}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                XCTAssertEqual(body["origin_id"] as? Int, -1001)
                XCTAssertEqual(body["limit"] as? Int, 500)
            }
        )
        XCTAssertEqual(try await refreshClient.refreshParticipants(accountID: "main", originID: -1001).refreshed, 12)

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
        XCTAssertEqual(try await cursorsClient.listCaptureCursors(accountID: "main").first?.lastMessageID, 99)

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
        XCTAssertEqual(try await eventsClient.listOperationEvents(accountID: "main", status: "failed").first?.errorCode, "rate_limited")

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
        XCTAssertEqual(try await mediaClient.listMediaFiles(accountID: "main", chatID: -1001, messageID: 99).first?.mediaKind, "photo")
    }

    func testThrowsHelpfulHTTPError() async throws {
        let client = makeClient(
            expectedPath: "/sync/state",
            responseJSON: #"{"error": "unauthorized", "detail": "bad token"}"#,
            status: 401
        )

        do {
            let _: CoreState = try await client.fetchSyncState()
            XCTFail("Expected request failure")
        } catch let error as CoreAPIError {
            XCTAssertEqual(error, .httpStatus(401, "bad token"))
        }
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
        XCTAssertEqual(request.httpMethod, expectedMethod)
        XCTAssertEqual(request.url?.path, expectedPath)
        let query = request.url?.query ?? ""
        for item in expectedQueryItems {
            XCTAssertTrue(query.contains(item), "Expected query to contain \(item), got \(query)")
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
        XCTFail("Expected JSON request body")
        return [:]
    }
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any] else {
        XCTFail("Expected JSON object body")
        return [:]
    }
    return dictionary
}

private func jsonResponse(_ json: String, status: Int = 200) throws -> (Data, HTTPURLResponse) {
    let url = URL(string: "http://core.local")!
    let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    return (Data(json.utf8), response)
}
