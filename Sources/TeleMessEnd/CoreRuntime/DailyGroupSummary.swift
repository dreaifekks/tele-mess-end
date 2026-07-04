import Foundation

struct DailyGroupSummary: Identifiable, Hashable {
    var source: String
    var accountID: String
    var originID: Int
    var topicID: Int
    var title: String
    var messageCount: Int
    var mediaCount: Int
    var participantCount: Int
    var lastMessageAt: String?
    var lastText: String?
    var important: Bool

    var id: String { "\(source):\(accountID):\(originID):\(topicID)" }
}

enum DailyGroupSummaryBuilder {
    static func build(origins: [CoreOrigin], messages: [CoreMessage], settings: SummarySettings, now: Date = Date()) -> [DailyGroupSummary] {
        let cutoff = now.addingTimeInterval(TimeInterval(-settings.lookbackHours * 60 * 60))
        let originByKey = Dictionary(uniqueKeysWithValues: origins.map { (key(for: $0), $0) })
        var buckets: [String: SummaryBucket] = [:]

        for message in messages {
            guard messageMatchesScope(message, settings: settings, cutoff: cutoff) else { continue }
            let topicID = message.topicID ?? 0
            let key = key(source: message.source, accountID: message.accountID, originID: message.chatID, topicID: topicID)
            let origin = originByKey[key]
            if settings.importantOnly && origin?.important != true {
                continue
            }

            var bucket = buckets[key] ?? SummaryBucket(
                source: message.source,
                accountID: message.accountID,
                originID: message.chatID,
                topicID: topicID,
                title: origin?.displayTitle ?? message.originTitle ?? message.chatTitle ?? "\(message.chatID)",
                important: origin?.important ?? false
            )
            bucket.messageCount += 1
            bucket.mediaCount += message.mediaCount ?? message.mediaFiles?.count ?? (message.hasMedia ? 1 : 0)
            if let senderID = message.senderID {
                bucket.participants.insert("id:\(senderID)")
            } else if let sender = message.displaySender.nilIfEmpty {
                bucket.participants.insert("name:\(sender)")
            }
            if bucket.lastDate == nil || message.sentDate.map({ $0 > (bucket.lastDate ?? .distantPast) }) == true {
                bucket.lastDate = message.sentDate
                bucket.lastMessageAt = message.sentAt
                bucket.lastText = message.text
            }
            buckets[key] = bucket
        }

        return buckets.values
            .map(\.summary)
            .sorted { lhs, rhs in
                (DisplayFormat.date(from: lhs.lastMessageAt) ?? .distantPast) > (DisplayFormat.date(from: rhs.lastMessageAt) ?? .distantPast)
            }
    }

    private static func messageMatchesScope(_ message: CoreMessage, settings: SummarySettings, cutoff: Date) -> Bool {
        if !settings.accountID.isEmpty && message.accountID != settings.accountID {
            return false
        }
        if let configuredOriginID = Int(settings.originID), message.chatID != configuredOriginID {
            return false
        }
        guard let sentDate = message.sentDate else {
            return false
        }
        return sentDate >= cutoff
    }

    private static func key(for origin: CoreOrigin) -> String {
        key(source: origin.source, accountID: origin.accountID, originID: origin.originID, topicID: origin.topicID)
    }

    private static func key(source: String, accountID: String, originID: Int, topicID: Int) -> String {
        "\(source):\(accountID):\(originID):\(topicID)"
    }
}

private struct SummaryBucket {
    var source: String
    var accountID: String
    var originID: Int
    var topicID: Int
    var title: String
    var messageCount = 0
    var mediaCount = 0
    var participants = Set<String>()
    var lastDate: Date?
    var lastMessageAt: String?
    var lastText: String?
    var important: Bool

    var summary: DailyGroupSummary {
        DailyGroupSummary(
            source: source,
            accountID: accountID,
            originID: originID,
            topicID: topicID,
            title: title,
            messageCount: messageCount,
            mediaCount: mediaCount,
            participantCount: participants.count,
            lastMessageAt: lastMessageAt,
            lastText: lastText,
            important: important
        )
    }
}

private extension CoreMessage {
    var sentDate: Date? {
        DisplayFormat.date(from: sentAt)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
