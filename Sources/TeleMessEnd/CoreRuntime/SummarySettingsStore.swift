import Foundation
import Observation

@MainActor
@Observable
final class SummarySettingsStore {
    private(set) var settings = SummarySettings()
    private(set) var selectedProfileID: UUID?

    private let defaults: UserDefaults
    private let legacySettingsKey = "teleMessEnd.summarySettings"
    private let settingsKeyPrefix = "teleMessEnd.summarySettings.profile."
    private let migratedProfileKey = "teleMessEnd.summarySettings.migratedProfileID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func selectProfile(_ profileID: UUID?) {
        selectedProfileID = profileID
        guard let profileID else {
            settings = SummarySettings()
            return
        }

        if let decoded = decodeSettings(forKey: settingsKey(for: profileID)) {
            settings = decoded
            return
        }

        if defaults.string(forKey: migratedProfileKey) == nil,
           let legacy = decodeSettings(forKey: legacySettingsKey) {
            settings = normalized(legacy)
            persist(settings, for: profileID)
            defaults.set(profileID.uuidString, forKey: migratedProfileKey)
            return
        }

        settings = SummarySettings()
    }

    func save(_ settings: SummarySettings) {
        let value = normalized(settings)
        self.settings = value
        guard let selectedProfileID else { return }
        persist(value, for: selectedProfileID)
    }

    func removeProfile(_ profileID: UUID) {
        defaults.removeObject(forKey: settingsKey(for: profileID))
    }

    private func settingsKey(for profileID: UUID) -> String {
        settingsKeyPrefix + profileID.uuidString
    }

    private func decodeSettings(forKey key: String) -> SummarySettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SummarySettings.self, from: data)
    }

    private func persist(_ settings: SummarySettings, for profileID: UUID) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey(for: profileID))
    }

    private func normalized(_ settings: SummarySettings) -> SummarySettings {
        var value = settings
        value.scheduleHour = min(max(value.scheduleHour, 0), 23)
        value.scheduleMinute = min(max(value.scheduleMinute, 0), 59)
        return value
    }
}
