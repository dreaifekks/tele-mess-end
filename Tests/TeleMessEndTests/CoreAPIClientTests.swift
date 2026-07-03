import Foundation
import XCTest
@testable import TeleMessEnd

final class CoreAPIClientTests: XCTestCase {
    func testAddsBearerTokenAndDecodesState() async throws {
        let transport = MockTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.url?.path, "/sync/state")
            return try jsonResponse(
                """
                {
                  "database_id": "db",
                  "schema_version": "2",
                  "last_event_seq": 12,
                  "message_count": 34,
                  "operation_error_count": 1,
                  "server_time": "2026-07-03T00:00:00+00:00"
                }
                """
            )
        }
        let client = CoreAPIClient(
            baseURL: URL(string: "http://127.0.0.1:8765")!,
            tokenProvider: FixedTokenProvider(value: "secret"),
            transport: transport
        )

        let state = try await client.fetchSyncState()

        XCTAssertEqual(state.databaseID, "db")
        XCTAssertEqual(state.lastEventSeq, 12)
        XCTAssertEqual(state.operationErrorCount, 1)
    }

    func testDecodesRecentMessagesWithIntegerMediaFlag() async throws {
        let transport = MockTransport { request in
            XCTAssertEqual(request.url?.path, "/sync/messages")
            XCTAssertTrue(request.url?.query?.contains("latest=true") == true)
            return try jsonResponse(
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
        }
        let client = CoreAPIClient(baseURL: URL(string: "http://core.local")!, transport: transport)

        let page = try await client.fetchRecentMessages(limit: 100)

        XCTAssertEqual(page.items.first?.displayChat, "Source")
        XCTAssertEqual(page.items.first?.hasMedia, true)
        XCTAssertEqual(page.nextCursor, 7)
    }

    func testThrowsHelpfulHTTPError() async throws {
        let transport = MockTransport { _ in
            try jsonResponse(
                """
                {"error": "unauthorized", "detail": "bad token"}
                """,
                status: 401
            )
        }
        let client = CoreAPIClient(baseURL: URL(string: "http://core.local")!, transport: transport)

        do {
            let _: CoreState = try await client.fetchSyncState()
            XCTFail("Expected request failure")
        } catch let error as CoreAPIError {
            XCTAssertEqual(error, .httpStatus(401, "bad token"))
        }
    }
}

private struct MockTransport: CoreHTTPTransport {
    var handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

private func jsonResponse(_ json: String, status: Int = 200) throws -> (Data, HTTPURLResponse) {
    let url = URL(string: "http://core.local")!
    let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    return (Data(json.utf8), response)
}
