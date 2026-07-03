import Foundation

enum DisplayFormat {
    static func shortDateTime(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "+00:00", with: "Z")
    }

    static func count(_ value: Int?) -> String {
        guard let value else { return "0" }
        return value.formatted()
    }

    static func bool(_ value: Bool) -> String {
        value ? "On" : "Off"
    }
}
