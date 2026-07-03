import Foundation

enum DisplayFormat {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func shortDateTime(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        if let date = fractionalISOFormatter.date(from: value) ?? isoFormatter.date(from: value) {
            return localDateFormatter.string(from: date)
        }
        return value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "+00:00", with: "Z")
    }

    static func count(_ value: Int?) -> String {
        guard let value else { return "0" }
        return value.formatted()
    }

    static func bool(_ value: Bool) -> String {
        value ? "On" : "Off"
    }

    static func maskedPhone(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let prefixLength = value.hasPrefix("+") ? min(4, value.count) : min(3, value.count)
        let suffixLength = min(3, max(0, value.count - prefixLength))
        guard value.count > prefixLength + suffixLength else { return value }
        let prefix = value.prefix(prefixLength)
        let suffix = value.suffix(suffixLength)
        return "\(prefix)**\(suffix)"
    }
}
