import Foundation

@main
enum SummarySettingsTests {
    static func main() throws {
        try testScheduleInputEncodesScopeAndDelivery()
        try testLegacyImportantOnlyIsIgnoredAndDropped()
        try testScheduleResponseMapsDelivery()
        try testOmittedDeliveryPreservesFallback()
        try testExplicitNullDeliveryClearsFallback()
        print("Summary settings tests passed")
    }

    private static func testScheduleInputEncodesScopeAndDelivery() throws {
        var settings = SummarySettings()
        settings.enabled = true
        settings.scheduleHour = 7
        settings.scheduleMinute = 5
        settings.timezone = "Asia/Tokyo"
        settings.accountID = "main"
        settings.originID = "-1001"
        settings.topicID = "42"
        settings.tags = "important"
        settings.deliveryEnabled = true
        settings.deliveryAccountID = "delivery"
        settings.deliveryOriginID = "-2002"
        settings.deliveryTopicID = "9"

        let data = try JSONEncoder.core.encode(settings.scheduleInput)
        let object = try expectDictionary(JSONSerialization.jsonObject(with: data))
        try expectEqual(object["enabled"] as? Bool, true)
        try expectEqual(object["time_of_day"] as? String, "07:05")
        let scope = try expectDictionary(object["scope"])
        try expectEqual(scope["account_id"] as? String, "main")
        try expectEqual((scope["origin_id"] as? NSNumber)?.intValue, -1001)
        try expectEqual((scope["topic_id"] as? NSNumber)?.intValue, 42)
        try expectEqual(scope["tags"] as? String, "important")
        try expectNil(scope["important"])
        let delivery = try expectDictionary(object["delivery"])
        try expectEqual(delivery["account_id"] as? String, "delivery")
        try expectEqual((delivery["origin_id"] as? NSNumber)?.intValue, -2002)
        try expectEqual((delivery["topic_id"] as? NSNumber)?.intValue, 9)
    }

    private static func testLegacyImportantOnlyIsIgnoredAndDropped() throws {
        let settings = try JSONDecoder.core.decode(
            SummarySettings.self,
            from: Data(
                """
                {
                  "enabled": true,
                  "accountID": "main",
                  "importantOnly": true
                }
                """.utf8
            )
        )

        let scheduleData = try JSONEncoder.core.encode(settings.scheduleInput)
        let scheduleObject = try expectDictionary(JSONSerialization.jsonObject(with: scheduleData))
        let scope = try expectDictionary(scheduleObject["scope"])
        try expectEqual(scope["account_id"] as? String, "main")
        try expectNil(scope["important"])

        let persistedData = try JSONEncoder.core.encode(settings)
        let persistedObject = try expectDictionary(JSONSerialization.jsonObject(with: persistedData))
        try expectNil(persistedObject["importantOnly"])
    }

    private static func testScheduleResponseMapsDelivery() throws {
        let schedule = try decodeSchedule(
            deliveryJSON: #"{"enabled":true,"account_id":"main","origin_id":-1001,"topic_id":42}"#
        )
        let settings = SummarySettings(schedule: schedule)
        try expectEqual(schedule.deliveryWasProvided, true)
        try expectEqual(settings.deliveryEnabled, true)
        try expectEqual(settings.deliveryAccountID, "main")
        try expectEqual(settings.deliveryOriginID, "-1001")
        try expectEqual(settings.deliveryTopicID, "42")

        let scheduleData = try JSONEncoder.core.encode(settings.scheduleInput)
        let scheduleObject = try expectDictionary(JSONSerialization.jsonObject(with: scheduleData))
        let scope = try expectDictionary(scheduleObject["scope"])
        try expectNil(scope["important"])
    }

    private static func testOmittedDeliveryPreservesFallback() throws {
        var fallback = SummarySettings()
        fallback.deliveryEnabled = true
        fallback.deliveryAccountID = "main"
        fallback.deliveryOriginID = "-1001"
        fallback.deliveryTopicID = "42"

        let schedule = try decodeSchedule(deliveryJSON: nil)
        let settings = SummarySettings(schedule: schedule, preservingDeliveryFrom: fallback)
        try expectEqual(schedule.deliveryWasProvided, false)
        try expectEqual(settings.deliveryEnabled, true)
        try expectEqual(settings.deliveryAccountID, "main")
    }

    private static func testExplicitNullDeliveryClearsFallback() throws {
        var fallback = SummarySettings()
        fallback.deliveryEnabled = true
        fallback.deliveryAccountID = "main"
        fallback.deliveryOriginID = "-1001"
        fallback.deliveryTopicID = "42"

        let schedule = try decodeSchedule(deliveryJSON: "null")
        let settings = SummarySettings(schedule: schedule, preservingDeliveryFrom: fallback)
        try expectEqual(schedule.deliveryWasProvided, true)
        try expectNil(schedule.delivery)
        try expectEqual(settings.deliveryEnabled, false)
        try expectEqual(settings.deliveryAccountID, "")
        try expectEqual(settings.deliveryOriginID, "")
        try expectEqual(settings.deliveryTopicID, "")
    }

    private static func decodeSchedule(deliveryJSON: String?) throws -> DailyPackageSchedule {
        let deliveryMember = deliveryJSON.map { ", \"delivery\": \($0)" } ?? ""
        return try JSONDecoder.core.decode(DailyPackageSchedule.self, from: Data(
            """
            {
              "enabled": true,
              "time_of_day": "08:00",
              "timezone": "Asia/Tokyo",
              "scope": {"important": true},
              "system_manager": "systemd-user",
              "installed": false
              \(deliveryMember)
            }
            """.utf8
        ))
    }
}

private func expectDictionary(_ value: Any?) throws -> [String: Any] {
    guard let dictionary = value as? [String: Any] else {
        throw SummarySettingsTestError.failure("Expected dictionary, got \(String(describing: value))")
    }
    return dictionary
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    guard actual == expected else {
        throw SummarySettingsTestError.failure("Expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

private func expectNil<T>(_ value: T?) throws {
    guard value == nil else {
        throw SummarySettingsTestError.failure("Expected nil, got \(String(describing: value))")
    }
}

private enum SummarySettingsTestError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case .failure(let message):
            message
        }
    }
}
