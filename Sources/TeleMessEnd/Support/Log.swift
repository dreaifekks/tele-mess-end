import OSLog

enum AppLog {
    static let subsystem = "com.dreaifekks.TeleMessEnd"
    static let api = Logger(subsystem: subsystem, category: "api")
    static let runtime = Logger(subsystem: subsystem, category: "runtime")
}
