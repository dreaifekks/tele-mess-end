import Foundation
import Observation
import OSLog

enum AppRuntimeLogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error

    var label: String {
        rawValue.uppercased()
    }
}

struct AppRuntimeLogEvent: Equatable, Sendable {
    var timestamp: Date
    var level: AppRuntimeLogLevel
    var category: String
    var message: String
}

struct AppRuntimeLogEntry: Identifiable, Equatable, Sendable {
    var id: UInt64
    var event: AppRuntimeLogEvent

    var renderedLine: String {
        let timestamp = event.timestamp.formatted(date: .omitted, time: .standard)
        return "[\(timestamp)] [\(event.level.label)] [\(event.category)] \(event.message)"
    }
}

struct AppRuntimeLogSnapshot: Sendable {
    var revision: UInt64
    var entries: [AppRuntimeLogEntry]
}

protocol AppRuntimeLogSink: Sendable {
    func record(_ event: AppRuntimeLogEvent)
}

final class AppRuntimeLogBuffer: AppRuntimeLogSink, @unchecked Sendable {
    private let maximumEntries: Int
    private let maximumCharacters: Int
    private let lock = NSLock()
    private var entries: [AppRuntimeLogEntry] = []
    private var characterCount = 0
    private var nextID: UInt64 = 0
    private var revision: UInt64 = 0
    private var continuations: [UUID: AsyncStream<AppRuntimeLogSnapshot>.Continuation] = [:]

    init(maximumEntries: Int = 1_000, maximumCharacters: Int = 200_000) {
        self.maximumEntries = max(1, maximumEntries)
        self.maximumCharacters = max(1, maximumCharacters)
    }

    func record(_ event: AppRuntimeLogEvent) {
        let snapshot: AppRuntimeLogSnapshot
        let subscribers: [AsyncStream<AppRuntimeLogSnapshot>.Continuation]

        lock.lock()
        nextID &+= 1
        revision &+= 1
        let entry = AppRuntimeLogEntry(id: nextID, event: event)
        entries.append(entry)
        characterCount += characterCost(of: entry)
        trimIfNeeded()
        snapshot = makeSnapshot()
        subscribers = Array(continuations.values)
        lock.unlock()

        for continuation in subscribers {
            continuation.yield(snapshot)
        }
    }

    @discardableResult
    func clear() -> AppRuntimeLogSnapshot {
        let snapshot: AppRuntimeLogSnapshot
        let subscribers: [AsyncStream<AppRuntimeLogSnapshot>.Continuation]

        lock.lock()
        entries.removeAll(keepingCapacity: true)
        characterCount = 0
        revision &+= 1
        snapshot = makeSnapshot()
        subscribers = Array(continuations.values)
        lock.unlock()

        for continuation in subscribers {
            continuation.yield(snapshot)
        }
        return snapshot
    }

    func snapshot() -> AppRuntimeLogSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return makeSnapshot()
    }

    func updates() -> AsyncStream<AppRuntimeLogSnapshot> {
        let continuationID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.lock()
            continuations[continuationID] = continuation
            continuation.yield(makeSnapshot())
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(continuationID)
            }
        }
    }

    private func trimIfNeeded() {
        while entries.count > maximumEntries || characterCount > maximumCharacters {
            guard !entries.isEmpty else { break }
            characterCount -= characterCost(of: entries.removeFirst())
        }
    }

    private func characterCost(of entry: AppRuntimeLogEntry) -> Int {
        entry.event.category.count + entry.event.message.count + 32
    }

    private func makeSnapshot() -> AppRuntimeLogSnapshot {
        AppRuntimeLogSnapshot(revision: revision, entries: entries)
    }

    private func removeContinuation(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}

struct AppRuntimeLogger: Sendable {
    private let category: String
    private let unifiedLogger: Logger?
    private let sink: any AppRuntimeLogSink

    init(
        subsystem: String,
        category: String,
        sink: any AppRuntimeLogSink,
        mirrorsToUnifiedLog: Bool = true
    ) {
        self.category = category
        unifiedLogger = mirrorsToUnifiedLog ? Logger(subsystem: subsystem, category: category) : nil
        self.sink = sink
    }

    func debug(_ message: String) {
        record(.debug, message: message)
    }

    func info(_ message: String) {
        record(.info, message: message)
    }

    func warning(_ message: String) {
        record(.warning, message: message)
    }

    func error(_ message: String) {
        record(.error, message: message)
    }

    private func record(_ level: AppRuntimeLogLevel, message: String) {
        switch level {
        case .debug:
            unifiedLogger?.debug("\(message, privacy: .public)")
        case .info:
            unifiedLogger?.info("\(message, privacy: .public)")
        case .warning:
            unifiedLogger?.warning("\(message, privacy: .public)")
        case .error:
            unifiedLogger?.error("\(message, privacy: .public)")
        }
        sink.record(
            AppRuntimeLogEvent(
                timestamp: Date(),
                level: level,
                category: category,
                message: message
            )
        )
    }
}

@MainActor
@Observable
final class AppRuntimeLogStore {
    private(set) var entries: [AppRuntimeLogEntry]
    @ObservationIgnored private let buffer: AppRuntimeLogBuffer
    @ObservationIgnored private var observedRevision: UInt64
    @ObservationIgnored private var monitoringTask: Task<Void, Never>?

    init(buffer: AppRuntimeLogBuffer = AppLog.buffer) {
        self.buffer = buffer
        let snapshot = buffer.snapshot()
        entries = snapshot.entries
        observedRevision = snapshot.revision
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        let updates = buffer.updates()
        monitoringTask = Task { [weak self] in
            for await _ in updates {
                guard let self else { return }
                // A notification can arrive out of order when multiple threads
                // log concurrently. Always apply the buffer's newest snapshot.
                apply(buffer.snapshot())
            }
        }
    }

    func clear() {
        apply(buffer.clear())
    }

    var renderedText: String {
        entries.map(\.renderedLine).joined(separator: "\n")
    }

    private func apply(_ snapshot: AppRuntimeLogSnapshot) {
        guard snapshot.revision > observedRevision else { return }
        observedRevision = snapshot.revision
        entries = snapshot.entries
    }
}

enum AppLog {
    static let subsystem = "com.dreaifekks.TeleMessEnd"
    static let buffer = AppRuntimeLogBuffer()
    static let api = AppRuntimeLogger(subsystem: subsystem, category: "api", sink: buffer)
    static let runtime = AppRuntimeLogger(subsystem: subsystem, category: "runtime", sink: buffer)
}
