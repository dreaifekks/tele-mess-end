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
    var deliveryEnabled = false
    var deliveryAccountID = ""
    var deliveryOriginID = ""
    var deliveryTopicID = ""
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
            activateSystemd: activateSystemd,
            delivery: deliveryConfig
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

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        scheduleHour = try container.decodeIfPresent(Int.self, forKey: .scheduleHour) ?? scheduleHour
        scheduleMinute = try container.decodeIfPresent(Int.self, forKey: .scheduleMinute) ?? scheduleMinute
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? timezone
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID) ?? accountID
        originID = try container.decodeIfPresent(String.self, forKey: .originID) ?? originID
        topicID = try container.decodeIfPresent(String.self, forKey: .topicID) ?? topicID
        tags = try container.decodeIfPresent(String.self, forKey: .tags) ?? tags
        importantOnly = try container.decodeIfPresent(Bool.self, forKey: .importantOnly) ?? importantOnly
        deliveryEnabled = try container.decodeIfPresent(Bool.self, forKey: .deliveryEnabled) ?? deliveryEnabled
        deliveryAccountID = try container.decodeIfPresent(String.self, forKey: .deliveryAccountID) ?? deliveryAccountID
        deliveryOriginID = try container.decodeIfPresent(String.self, forKey: .deliveryOriginID) ?? deliveryOriginID
        deliveryTopicID = try container.decodeIfPresent(String.self, forKey: .deliveryTopicID) ?? deliveryTopicID
        systemManager = try container.decodeIfPresent(String.self, forKey: .systemManager) ?? systemManager
        activateSystemd = try container.decodeIfPresent(Bool.self, forKey: .activateSystemd) ?? activateSystemd
    }

    init(schedule: DailyPackageSchedule, preservingDeliveryFrom fallback: SummarySettings? = nil) {
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
        if schedule.deliveryWasProvided {
            if let delivery = schedule.delivery {
                deliveryEnabled = delivery.enabled
                deliveryAccountID = delivery.accountID
                deliveryOriginID = delivery.originID.map(String.init) ?? ""
                deliveryTopicID = delivery.topicID == 0 ? "" : String(delivery.topicID)
            } else {
                deliveryEnabled = false
                deliveryAccountID = ""
                deliveryOriginID = ""
                deliveryTopicID = ""
            }
        } else if let fallback {
            deliveryEnabled = fallback.deliveryEnabled
            deliveryAccountID = fallback.deliveryAccountID
            deliveryOriginID = fallback.deliveryOriginID
            deliveryTopicID = fallback.deliveryTopicID
        }
    }

    private var deliveryConfig: DailySummaryDeliveryConfig {
        DailySummaryDeliveryConfig(
            enabled: deliveryEnabled,
            accountID: deliveryAccountID.nilIfEmpty ?? "",
            originID: Int(deliveryOriginID),
            topicID: Int(deliveryTopicID) ?? 0
        )
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case scheduleHour
        case scheduleMinute
        case timezone
        case accountID
        case originID
        case topicID
        case tags
        case importantOnly
        case deliveryEnabled
        case deliveryAccountID
        case deliveryOriginID
        case deliveryTopicID
        case systemManager
        case activateSystemd
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
