import Foundation

@main
enum CoreAPILiveSmoke {
    static func main() async {
        do {
            let environment = ProcessInfo.processInfo.environment
            let baseURLString = environment["CORE_BASE_URL"] ?? "http://127.0.0.1:8765"
            guard let baseURL = URL(string: baseURLString) else {
                throw SmokeError.failure("Invalid CORE_BASE_URL: \(baseURLString)")
            }

            let token = environment["CORE_API_TOKEN"]
            let authMode = (environment["CORE_AUTH_MODE"] == "api-token") ? CoreAuthMode.apiToken : .bearer
            let client = CoreAPIClient(
                baseURL: baseURL,
                tokenProvider: FixedTokenProvider(value: token),
                authMode: authMode
            )

            let health = try await client.health()
            try expectEqual(health.ok, true, "healthz should report ok")

            let state = try await client.fetchSyncState()
            try expectTrue(state.schemaVersion != nil, "sync state should include schema version")

            let capabilities = try await client.fetchCapabilities()
            let management = capabilities.management ?? []
            try expectTrue(!management.isEmpty, "capabilities should include management entries")
            try expectTrue(
                management.contains(where: { $0.contains("account") || $0.contains("origin") }),
                "capabilities should include account or origin management"
            )

            let manifest = try await client.fetchAPIManifest()
            try expectTrue(!manifest.contractVersion.isEmpty, "manifest should include contract version")
            try expectTrue(!manifest.contractHash.isEmpty, "manifest should include contract hash")

            let accounts = try await client.listManagementAccounts()
            let origins = try await client.listOrigins(includeArchived: true)
            let messages = try await client.fetchRecentMessages(limit: 100)
            let operationEvents = try await client.listOperationEvents(status: "failed", limit: 100)
            let participants = try await client.listParticipants()
            let cursors = try await client.listCaptureCursors()
            let mediaFiles = try await client.listMediaFiles(limit: 100)
            let schedule = try await client.fetchDailyPackageSchedule()
            let dailyPackageRuns = try await client.listDailyPackageRuns(limit: 5)
            let dailySummaryRuns = try await client.listDailySummaryRuns(limit: 5)
            let dailySummaryJobs = try await client.listDailySummaryJobs(limit: 5)
            let dailySummaryRecords = try await client.listDailySummaryRecords(includeContent: false, limit: 5)

            print("Core API live smoke passed")
            print("base_url=\(baseURL.absoluteString)")
            print("schema_version=\(state.schemaVersionText)")
            print("contract_version=\(manifest.contractVersion)")
            print("contract_hash=\(manifest.contractHash)")
            print("messages=\(state.messageCount)")
            print("accounts=\(accounts.count)")
            print("origins=\(origins.count)")
            print("recent_messages=\(messages.items.count)")
            print("failed_events=\(operationEvents.count)")
            print("participants=\(participants.count)")
            print("cursors=\(cursors.count)")
            print("media_files=\(mediaFiles.count)")
            print("daily_schedule_enabled=\(schedule.enabled)")
            print("daily_package_runs=\(dailyPackageRuns.count)")
            print("daily_summary_runs=\(dailySummaryRuns.count)")
            print("daily_summary_jobs=\(dailySummaryJobs.count)")
            print("daily_summary_records=\(dailySummaryRecords.count)")
            exit(0)
        } catch {
            print("Core API live smoke failed: \(error)")
            exit(1)
        }
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw SmokeError.failure("\(message). Expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

private func expectTrue(_ value: Bool, _ message: String) throws {
    guard value else {
        throw SmokeError.failure(message)
    }
}

private enum SmokeError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case .failure(let message):
            message
        }
    }
}
