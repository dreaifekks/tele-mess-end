import Foundation

struct SummarySettings: Codable, Equatable {
    var enabled = false
    var scheduleHour = 8
    var scheduleMinute = 0
    var timezone = "Asia/Tokyo"
    var accountID = ""
    var originID = ""
    var topicID = ""
    var tags = ""
    var importantOnly = false
    var lookbackHours = 24
    var systemManager = "systemd-user"
    var activateSystemd = false

    var scheduleText: String {
        "\(String(format: "%02d", scheduleHour)):\(String(format: "%02d", scheduleMinute))"
    }

    var scope: JSONValue {
        var object: [String: JSONValue] = [:]
        if importantOnly {
            object["important"] = .bool(true)
        }
        if let accountID = accountID.nilIfEmpty {
            object["account_id"] = .string(accountID)
        }
        if let originID = Int(originID) {
            object["origin_id"] = .number(Double(originID))
        }
        if let topicID = Int(topicID) {
            object["topic_id"] = .number(Double(topicID))
        }
        if let tags = tags.nilIfEmpty {
            object["tags"] = .string(tags)
        }
        return .object(object)
    }

    var scheduleInput: DailyPackageScheduleInput {
        DailyPackageScheduleInput(
            enabled: enabled,
            timeOfDay: scheduleText,
            timezone: timezone.nilIfEmpty ?? "Asia/Tokyo",
            scope: scope,
            systemManager: systemManager.nilIfEmpty ?? "systemd-user",
            activateSystemd: activateSystemd
        )
    }

    var packageRunInput: DailyPackageRunInput {
        DailyPackageRunInput(
            date: nil,
            timezone: timezone.nilIfEmpty,
            scope: scope,
            accountID: accountID.nilIfEmpty,
            originID: Int(originID),
            topicID: Int(topicID),
            tags: tags.nilIfEmpty,
            tagGroups: nil
        )
    }

    var summaryRunInput: DailySummaryRunInput {
        DailySummaryRunInput(
            packageRunID: nil,
            date: nil,
            timezone: timezone.nilIfEmpty,
            scope: scope,
            accountID: accountID.nilIfEmpty,
            originID: Int(originID),
            topicID: Int(topicID),
            tags: tags.nilIfEmpty,
            tagGroups: nil,
            background: true
        )
    }

    init() {}

    init(schedule: DailyPackageSchedule) {
        enabled = schedule.enabled
        timezone = schedule.timezone
        systemManager = schedule.systemManager
        activateSystemd = schedule.installed
        if let parsed = Self.parseTimeOfDay(schedule.timeOfDay) {
            scheduleHour = parsed.hour
            scheduleMinute = parsed.minute
        }
        if case .object(let object) = schedule.scope {
            importantOnly = object["important"]?.boolValue ?? false
            accountID = object["account_id"]?.stringValue ?? ""
            originID = object["origin_id"]?.integerStringValue ?? ""
            topicID = object["topic_id"]?.integerStringValue ?? ""
            tags = object["tags"]?.stringValue ?? ""
        }
    }

    private static func parseTimeOfDay(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return (min(max(hour, 0), 23), min(max(minute, 0), 59))
    }
}

private extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var integerStringValue: String? {
        switch self {
        case .number(let value):
            return String(Int(value))
        case .string(let value):
            return value
        default:
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
