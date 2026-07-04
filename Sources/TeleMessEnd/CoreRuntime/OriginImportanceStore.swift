import Foundation
import Observation

@MainActor
@Observable
final class OriginImportanceStore {
    private var values: [CoreOrigin.ID: Bool]

    private let defaults: UserDefaults
    private let valuesKey = "teleMessEnd.originImportanceOverrides"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: valuesKey),
           let decoded = try? JSONDecoder().decode([CoreOrigin.ID: Bool].self, from: data) {
            values = decoded
        } else {
            values = [:]
        }
    }

    func value(for origin: CoreOrigin) -> Bool? {
        values[origin.id]
    }

    func set(_ important: Bool?, for origin: CoreOrigin) {
        values[origin.id] = important
        save()
    }

    func apply(to origins: [CoreOrigin]) -> [CoreOrigin] {
        origins.map { origin in
            guard let important = values[origin.id] else {
                return origin
            }
            var updated = origin
            updated.important = important
            return updated
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: valuesKey)
        }
    }
}
