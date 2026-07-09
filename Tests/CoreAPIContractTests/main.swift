import Foundation

@main
enum CoreAPIContractTests {
    static func main() async {
        var runner = ContractRunner()
        await runner.run("health decodes state") { try await testHealthDecodesState() }
        await runner.run("state uses bearer token") { try await testStateUsesBearerToken() }
        await runner.run("capabilities uses api token") { try await testCapabilitiesUsesAPIToken() }
        await runner.run("manifest and sync metadata") { try await testManifestAndSyncMetadata() }
        await runner.run("messages and search decode") { try await testMessagesAndSearchDecode() }
        await runner.run("accounts and auth flow") { try await testAccountsAndAuthFlow() }
        await runner.run("origins and policies") { try await testOriginsAndPolicies() }
        await runner.run("diagnostics endpoints") { try await testDiagnosticsEndpoints() }
        await runner.run("daily package and summary endpoints") { try await testDailyPackageAndSummaryEndpoints() }
        await runner.run("media content download") { try await testMediaContentDownload() }
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
              "schema_version": 2,
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
        try expectEqual(state.schemaVersion, "2")
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
              "auth_flow": {"request_code": true},
              "api_contract": {"contract_version": "2026-07-03.1"}
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
        try expectEqual(capabilities.apiContract?.description.contains("2026-07-03.1") ?? false, true)
    }

    static func testManifestAndSyncMetadata() async throws {
        let manifestClient = makeClient(
            expectedPath: "/manage/api-manifest",
            responseJSON:
            """
            {
              "name": "tele-mess-core API",
              "contract_version": "2026-07-03.1",
              "contract_hash": "hash",
              "endpoints": [{"path": "/sync/events"}]
            }
            """
        )
        let manifest = try await manifestClient.fetchAPIManifest()
        try expectEqual(manifest.contractVersion, "2026-07-03.1")
        try expectEqual(manifest.contractHash, "hash")

        let eventsClient = makeClient(
            expectedPath: "/sync/events",
            expectedQueryItems: ["after=12", "limit=50"],
            responseJSON:
            """
            {
              "items": [
                {"seq": 13, "source": "telegram", "account_id": "main", "event_type": "message", "payload_json": {"ok": true}}
              ],
              "next_cursor": 13,
              "has_more": false
            }
            """
        )
        let events = try await eventsClient.fetchEvents(after: 12, limit: 50)
        try expectEqual(events.items.first?.eventType, "message")
        try expectEqual(events.nextCursor, 13)

        let chatsClient = makeClient(
            expectedPath: "/sync/chats",
            responseJSON:
            """
            {"items": [{"source": "telegram", "account_id": "main", "chat_id": -1001, "title": "Ops"}]}
            """
        )
        try expectEqual(try await chatsClient.listChats().first?.displayTitle, "Ops")
    }

    static func testMessagesAndSearchDecode() async throws {
        let recentClient = makeClient(
            expectedPath: "/sync/messages",
            expectedQueryItems: ["latest=true", "limit=100", "include_media=true"],
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
                  "media_count": 1,
                  "media_files": [
                    {
                      "source": "telegram",
                      "account_id": "main",
                      "chat_id": -1001,
                      "message_id": 99,
                      "file_index": 0,
                      "content_type": "image/jpeg"
                    }
                  ],
                  "origin_title": "Source",
                  "version": 1
                }
              ],
              "next_cursor": 7,
              "has_more": false
            }
            """
        )

        let page = try await recentClient.fetchRecentMessages(limit: 100, includeMedia: true)
        try expectEqual(page.items.first?.displayChat, "Source")
        try expectEqual(page.items.first?.hasMedia, true)
        try expectEqual(page.items.first?.mediaCount, 1)
        try expectEqual(page.items.first?.mediaFiles?.first?.contentType, "image/jpeg")
        try expectEqual(page.nextCursor, 7)

        let searchClient = makeClient(
            expectedPath: "/sync/search",
            expectedQueryItems: ["q=needle", "limit=50", "include_media=true"],
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

        let messages = try await searchClient.searchMessages(query: "needle", limit: 50, includeMedia: true)
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
                  "important": true,
                  "parent_title": "Workspace",
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
        try expectEqual(origins.first?.important, true)
        try expectEqual(origins.first?.parentTitle, "Workspace")
        try expectEqual(origins.last?.isTopic, true)

        let discoverClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/discover-origins",
            responseJSON: #"{"item": {"account_id": "main", "origins": 2, "topics": 1, "private_skipped": 3, "topics_truncated": false}}"#,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["account_id"] as? String, "main")
                try expectEqual(body["include_topics"] as? Bool, true)
                try expectEqual(body["include_private"] as? Bool, false)
                try expectEqual(body["topic_limit"] as? Int, 500)
            }
        )
        try expectEqual(try await discoverClient.discoverOrigins(accountID: "main").topics, 1)
        try expectEqual(try await discoverClient.discoverOrigins(accountID: "main").privateSkipped, 3)

        let updateOriginClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/origins",
            responseJSON:
            """
            {"item": {"source": "telegram", "account_id": "main", "origin_id": -1001, "topic_id": 0, "origin_type": "group", "important": true}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["important"] as? Bool, true)
                try expectEqual(body["origin_type"] as? String, "group")
            }
        )
        let updatedOrigin = try await updateOriginClient.updateOrigin(OriginUpdateRequest(origin: origins[0], important: true))
        try expectEqual(updatedOrigin.important, true)

        let importantClient = makeClient(
            expectedMethod: "PATCH",
            expectedPath: "/manage/origins/important",
            responseJSON:
            """
            {"item": {"source": "telegram", "account_id": "main", "origin_id": -1001, "topic_id": 0, "origin_type": "group", "important": false}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["important"] as? Bool, false)
                try expectEqual(body["origin_id"] as? Int, -1001)
            }
        )
        let unmarkedOrigin = try await importantClient.setOriginImportant(
            OriginImportantRequest(accountID: "main", originID: -1001, important: false)
        )
        try expectEqual(unmarkedOrigin.important, false)

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
            expectedMethod: "POST",
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
            responseJSON: #"{"item": {"account_id": "main", "origin_id": -1001, "participants": 12, "participants_truncated": false}}"#,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["origin_id"] as? Int, -1001)
                try expectEqual(body["limit"] as? Int, 500)
            }
        )
        let refreshResult = try await refreshClient.refreshParticipants(accountID: "main", originID: -1001)
        try expectEqual(refreshResult.participants, 12)
        try expectEqual(refreshResult.refreshed, 12)

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
                  "error_type": "FloodWait",
                  "subject_label": "Ops",
                  "raw_json": {"retry_after": 30}
                }
              ]
            }
            """
        )
        let events = try await eventsClient.listOperationEvents(accountID: "main", status: "failed")
        try expectEqual(events.first?.errorCode, "rate_limited")
        try expectEqual(events.first?.subjectLabel, "Ops")

        let deleteEventClient = makeClient(
            expectedMethod: "DELETE",
            expectedPath: "/manage/operation-events",
            responseJSON: #"{"item": {"ids": [1], "deleted": 1}}"#,
            verify: { request in
                try expectEqual(try requestJSONObject(request)["id"] as? Int, 1)
            }
        )
        try expectEqual(try await deleteEventClient.deleteOperationEvent(id: 1).deleted, 1)

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
                  "file_size": 123,
                  "origin_title": "Ops",
                  "content_type": "image/jpeg",
                  "preview_kind": "image",
                  "access_url": "/sync/media-files/content?account_id=main"
                }
              ]
            }
            """
        )
        let media = try await mediaClient.listMediaFiles(accountID: "main", chatID: -1001, messageID: 99)
        try expectEqual(media.first?.mediaKind, "photo")
        try expectEqual(media.first?.originTitle, "Ops")
    }

    static func testDailyPackageAndSummaryEndpoints() async throws {
        let scheduleClient = makeClient(
            expectedPath: "/manage/daily-package-schedule",
            responseJSON:
            """
            {"item": {"enabled": true, "time_of_day": "08:30", "timezone": "Asia/Tokyo", "scope": {"important": true}, "delivery": {"enabled": true, "account_id": "main", "origin_id": -1001, "topic_id": 42}, "system_manager": "systemd-user", "installed": true}}
            """
        )
        let schedule = try await scheduleClient.fetchDailyPackageSchedule()
        try expectEqual(schedule.enabled, true)
        try expectEqual(schedule.timeOfDay, "08:30")
        try expectEqual(schedule.delivery?.accountID, "main")
        try expectEqual(schedule.delivery?.originID, -1001)
        try expectEqual(schedule.delivery?.topicID, 42)

        let updateScheduleClient = makeClient(
            expectedMethod: "PATCH",
            expectedPath: "/manage/daily-package-schedule",
            responseJSON:
            """
            {"item": {"enabled": false, "time_of_day": "09:00", "timezone": "Asia/Tokyo", "scope": {}, "system_manager": "systemd-user", "installed": false}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["time_of_day"] as? String, "09:00")
                try expectEqual(body["enabled"] as? Bool, false)
                let delivery = try expectDictionary(body["delivery"], "Expected delivery object")
                try expectEqual(delivery["enabled"] as? Bool, true)
                try expectEqual(delivery["account_id"] as? String, "main")
                try expectEqual(delivery["origin_id"] as? Int, -1001)
                try expectEqual(delivery["topic_id"] as? Int, 42)
            }
        )
        let updatedSchedule = try await updateScheduleClient.updateDailyPackageSchedule(
            DailyPackageScheduleInput(
                enabled: false,
                timeOfDay: "09:00",
                timezone: "Asia/Tokyo",
                scope: .object([:]),
                systemManager: "systemd-user",
                activateSystemd: false,
                delivery: DailySummaryDeliveryConfig(enabled: true, accountID: "main", originID: -1001, topicID: 42)
            )
        )
        try expectEqual(updatedSchedule.timeOfDay, "09:00")

        let packageClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/daily-packages",
            responseJSON:
            """
            {"item": {"run_id": "pkg-1", "status": "completed", "date": "2026-07-04", "timezone": "Asia/Tokyo", "message_count": 12, "media_count": 3, "progress_current": 5, "progress_total": 5, "progress_label": "package complete", "progress": {"stage": "done"}}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["account_id"] as? String, "main")
            }
        )
        let packageRun = try await packageClient.runDailyPackage(
            DailyPackageRunInput(date: "2026-07-04", timezone: "Asia/Tokyo", scope: .object(["important": .bool(true)]), accountID: "main", originID: nil, topicID: nil, tags: nil, tagGroups: nil)
        )
        try expectEqual(packageRun.runID, "pkg-1")
        try expectEqual(packageRun.messageCount, 12)
        try expectEqual(packageRun.progressCurrent, 5)
        try expectEqual(packageRun.progressLabel, "package complete")

        let packageRunsClient = makeClient(
            expectedPath: "/manage/daily-package-runs",
            expectedQueryItems: ["status=completed", "limit=20"],
            responseJSON:
            """
            {"items": [{"run_id": "pkg-1", "status": "completed", "date": "2026-07-04", "timezone": "Asia/Tokyo"}]}
            """
        )
        try expectEqual(try await packageRunsClient.listDailyPackageRuns(status: "completed", limit: 20).count, 1)

        let summaryClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/daily-summaries",
            responseJSON:
            """
            {"item": {"run_id": "sum-1", "status": "queued", "package_run_id": "pkg-1", "date": "2026-07-04", "timezone": "Asia/Tokyo", "provider": "openai", "progress_current": 1, "progress_total": 8, "progress_label": "media"}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["package_run_id"] as? String, "pkg-1")
                try expectEqual(body["background"] as? Bool, true)
            }
        )
        let summaryRun = try await summaryClient.runDailySummary(
            DailySummaryRunInput(packageRunID: "pkg-1", date: nil, timezone: "Asia/Tokyo", scope: nil, accountID: nil, originID: nil, topicID: nil, tags: nil, tagGroups: nil, background: true)
        )
        try expectEqual(summaryRun.runID, "sum-1")
        try expectEqual(summaryRun.progressTotal, 8)

        let jobClient = makeClient(
            expectedMethod: "POST",
            expectedPath: "/manage/daily-summary-jobs",
            responseJSON:
            """
            {"item": {"job_id": "job-1", "status": "running", "package_run_id": "pkg-1", "summary_run_id": "sum-1", "date": "2026-07-04", "timezone": "Asia/Tokyo", "provider": "codex-cli", "progress_current": 2, "progress_total": 10, "progress_label": "normal groups"}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["account_id"] as? String, "main")
                try expectEqual(body["background"] as? Bool, true)
            }
        )
        let job = try await jobClient.runDailySummaryJob(
            DailySummaryRunInput(packageRunID: nil, date: "2026-07-04", timezone: "Asia/Tokyo", scope: nil, accountID: "main", originID: nil, topicID: nil, tags: nil, tagGroups: nil, background: true)
        )
        try expectEqual(job.jobID, "job-1")
        try expectEqual(job.summaryRunID, "sum-1")
        try expectEqual(job.isActive, true)

        let jobsClient = makeClient(
            expectedPath: "/manage/daily-summary-jobs",
            expectedQueryItems: ["status=running", "limit=10"],
            responseJSON:
            """
            {"items": [{"job_id": "job-1", "status": "running", "progress_current": 2, "progress_total": 10}]}
            """
        )
        try expectEqual(try await jobsClient.listDailySummaryJobs(status: "running", limit: 10).first?.progressTotal, 10)

        let cancelJobClient = makeClient(
            expectedMethod: "PATCH",
            expectedPath: "/manage/daily-summary-jobs/cancel",
            responseJSON:
            """
            {"item": {"job_id": "job-1", "status": "cancel_requested", "cancel_requested_at": "2026-07-04T00:00:00+00:00"}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["job_id"] as? String, "job-1")
            }
        )
        try expectEqual(try await cancelJobClient.cancelDailySummaryJob(jobID: "job-1").status, "cancel_requested")

        let recordsClient = makeClient(
            expectedPath: "/manage/daily-summary-records",
            expectedQueryItems: ["important=true", "include_deleted=false", "include_content=false", "limit=10"],
            responseJSON:
            """
            {"items": [{"summary_id": "rec-1", "run_id": "sum-1", "content_preview": "Daily summary", "tags": ["prod", "ops"], "tags_csv": "prod,ops", "important": true, "origin_count": 5, "group_count": 2, "image_count": 1, "deleted": false}]}
            """
        )
        let records = try await recordsClient.listDailySummaryRecords(important: true, includeContent: false, limit: 10)
        try expectEqual(records.first?.summaryID, "rec-1")
        try expectEqual(records.first?.tags ?? [], ["prod", "ops"])
        try expectEqual(records.first?.tagsCSV, "prod,ops")
        try expectEqual(records.first?.originCount, 5)
        try expectEqual(records.first?.important, true)
        try expectEqual(records.first?.deleted, false)

        let recordClient = makeClient(
            expectedPath: "/manage/daily-summary-records/item",
            expectedQueryItems: ["summary_id=rec-1", "include_deleted=false"],
            responseJSON:
            """
            {"item": {"summary_id": "rec-1", "run_id": "sum-1", "content_preview": "Daily summary", "content_md": "# Daily", "deleted": false}}
            """
        )
        try expectEqual(try await recordClient.fetchDailySummaryRecord(summaryID: "rec-1").contentMD, "# Daily")

        let contentTransport = MockTransport { request in
            try expectEqual(request.url?.path, "/manage/daily-summary-runs/content")
            try expectTrue((request.url?.query ?? "").contains("run_id=sum-1"))
            let response = HTTPURLResponse(url: URL(string: "http://core.local")!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/markdown"])!
            return (Data("# Summary".utf8), response)
        }
        let contentClient = CoreAPIClient(baseURL: URL(string: "http://core.local")!, transport: contentTransport)
        try expectEqual(try await contentClient.fetchDailySummaryRunContent(runID: "sum-1"), "# Summary")

        let deleteRecordsClient = makeClient(
            expectedMethod: "DELETE",
            expectedPath: "/manage/daily-summary-records",
            responseJSON:
            """
            {"item": {"summary_ids": ["rec-1", "rec-2"], "deleted": true, "changed_rows": 2}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["summary_ids"] as? [String], ["rec-1", "rec-2"])
                try expectEqual(body["deleted"] as? Bool, true)
            }
        )
        try expectEqual(try await deleteRecordsClient.deleteDailySummaryRecords(summaryIDs: ["rec-1", "rec-2"]).changedRows, 2)

        let restoreRecordsClient = makeClient(
            expectedMethod: "PATCH",
            expectedPath: "/manage/daily-summary-records",
            responseJSON:
            """
            {"item": {"summary_ids": ["rec-1"], "deleted": false, "changed_rows": 1}}
            """,
            verify: { request in
                let body = try requestJSONObject(request)
                try expectEqual(body["summary_ids"] as? [String], ["rec-1"])
                try expectEqual(body["deleted"] as? Bool, false)
            }
        )
        try expectEqual(try await restoreRecordsClient.restoreDailySummaryRecords(summaryIDs: ["rec-1"]).deleted, false)
    }

    static func testMediaContentDownload() async throws {
        let transport = MockTransport { request in
            try expectEqual(request.httpMethod, "GET")
            try expectEqual(request.url?.path, "/sync/media-files/content")
            let query = request.url?.query ?? ""
            for item in ["source=telegram", "account_id=main", "chat_id=-1001", "message_id=99", "file_index=0"] {
                try expectTrue(query.contains(item), "Expected query to contain \(item), got \(query)")
            }
            try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            try expectEqual(request.value(forHTTPHeaderField: "Accept"), "application/octet-stream")
            let response = HTTPURLResponse(
                url: URL(string: "http://core.local/sync/media-files/content")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/octet-stream"]
            )!
            return (Data("binary".utf8), response)
        }
        let client = CoreAPIClient(
            baseURL: URL(string: "http://core.local")!,
            tokenProvider: FixedTokenProvider(value: "secret"),
            transport: transport
        )

        let data = try await client.downloadMediaContent(accountID: "main", chatID: -1001, messageID: 99)
        try expectEqual(String(data: data, encoding: .utf8) ?? "", "binary")
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

private func expectDictionary(_ value: Any?, _ message: String? = nil) throws -> [String: Any] {
    guard let dictionary = value as? [String: Any] else {
        throw ContractError.failure(message ?? "Expected dictionary, got \(String(describing: value))")
    }
    return dictionary
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
