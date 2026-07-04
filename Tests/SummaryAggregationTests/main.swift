import Foundation

@main
enum SummaryAggregationTests {
    static func main() throws {
        let origins = try decodeOrigins()
        let messages = try decodeMessages()
        let now = DisplayFormat.date(from: "2026-07-04T12:00:00+00:00")!

        var importantSettings = SummarySettings()
        importantSettings.importantOnly = true
        importantSettings.lookbackHours = 24

        let importantSummaries = DailyGroupSummaryBuilder.build(
            origins: origins,
            messages: messages,
            settings: importantSettings,
            now: now
        )
        try expectEqual(importantSummaries.count, 1)
        try expectEqual(importantSummaries.first?.originID, -1001)
        try expectEqual(importantSummaries.first?.messageCount, 2)
        try expectEqual(importantSummaries.first?.mediaCount, 2)
        try expectEqual(importantSummaries.first?.participantCount, 2)

        var allSettings = importantSettings
        allSettings.importantOnly = false
        let allSummaries = DailyGroupSummaryBuilder.build(origins: origins, messages: messages, settings: allSettings, now: now)
        try expectEqual(allSummaries.count, 2)
        try expectEqual(SummarySettings(schedule: try decodeSchedule(scope: #"{}"#)).importantOnly, false)
        try expectEqual(SummarySettings(schedule: try decodeSchedule(scope: #"{"important": true}"#)).importantOnly, true)

        var narrowSettings = importantSettings
        narrowSettings.lookbackHours = 1
        let narrowSummaries = DailyGroupSummaryBuilder.build(origins: origins, messages: messages, settings: narrowSettings, now: now)
        try expectEqual(narrowSummaries.count, 1)
        try expectEqual(narrowSummaries.first?.messageCount, 1)

        print("Summary aggregation tests passed")
    }

    private static func decodeOrigins() throws -> [CoreOrigin] {
        try JSONDecoder.core.decode([CoreOrigin].self, from: Data(
            """
            [
              {
                "source": "telegram",
                "account_id": "main",
                "origin_id": -1001,
                "topic_id": 0,
                "origin_type": "group",
                "title": "Important Ops",
                "important": true
              },
              {
                "source": "telegram",
                "account_id": "main",
                "origin_id": -1002,
                "topic_id": 0,
                "origin_type": "group",
                "title": "Casual",
                "important": false
              }
            ]
            """.utf8
        ))
    }

    private static func decodeMessages() throws -> [CoreMessage] {
        try JSONDecoder.core.decode([CoreMessage].self, from: Data(
            """
            [
              {
                "event_seq": 1,
                "source": "telegram",
                "account_id": "main",
                "chat_id": -1001,
                "message_id": 10,
                "sender_id": 100,
                "sent_at": "2026-07-04T11:30:00+00:00",
                "text": "latest",
                "has_media": true,
                "media_count": 2
              },
              {
                "event_seq": 2,
                "source": "telegram",
                "account_id": "main",
                "chat_id": -1001,
                "message_id": 9,
                "sender_id": 101,
                "sent_at": "2026-07-04T02:00:00+00:00",
                "text": "earlier",
                "has_media": false
              },
              {
                "event_seq": 3,
                "source": "telegram",
                "account_id": "main",
                "chat_id": -1002,
                "message_id": 8,
                "sender_id": 102,
                "sent_at": "2026-07-04T10:00:00+00:00",
                "text": "non important",
                "has_media": false
              },
              {
                "event_seq": 4,
                "source": "telegram",
                "account_id": "main",
                "chat_id": -1001,
                "message_id": 7,
                "sender_id": 103,
                "sent_at": "2026-07-02T10:00:00+00:00",
                "text": "old",
                "has_media": false
              }
            ]
            """.utf8
        ))
    }

    private static func decodeSchedule(scope: String) throws -> DailyPackageSchedule {
        try JSONDecoder.core.decode(DailyPackageSchedule.self, from: Data(
            """
            {
              "enabled": true,
              "time_of_day": "08:00",
              "timezone": "Asia/Tokyo",
              "scope": \(scope),
              "system_manager": "systemd-user",
              "installed": false
            }
            """.utf8
        ))
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    guard actual == expected else {
        throw SummaryAggregationError.failure("Expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

private enum SummaryAggregationError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case .failure(let message):
            message
        }
    }
}
