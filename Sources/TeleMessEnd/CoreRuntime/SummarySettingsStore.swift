import Foundation
import Observation

@MainActor
@Observable
final class SummarySettingsStore {
    var settings: SummarySettings

    private let defaults: UserDefaults
    private let settingsKey = "teleMessEnd.summarySettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(SummarySettings.self, from: data) {
            settings = decoded
        } else {
            settings = SummarySettings()
        }
    }

    func save(_ settings: SummarySettings) {
        var normalized = settings
        normalized.scheduleHour = min(max(normalized.scheduleHour, 0), 23)
        normalized.scheduleMinute = min(max(normalized.scheduleMinute, 0), 59)
        normalized.lookbackHours = min(max(normalized.lookbackHours, 1), 168)
        self.settings = normalized
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: settingsKey)
        }
    }
}
