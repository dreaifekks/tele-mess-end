import Foundation
import Observation

private final class LocalCoreOutputGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func current() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance() {
        lock.lock()
        value &+= 1
        lock.unlock()
    }
}

@MainActor
@Observable
final class LocalCoreProcessController {
    private static let outputCharacterLimit = 200_000

    @ObservationIgnored private let logger: AppRuntimeLogger
    @ObservationIgnored private let outputGeneration = LocalCoreOutputGeneration()
    private var process: Process?
    private var outputPipe: Pipe?
    private var isStopping = false
    var isRunning = false
    var lastOutput = ""
    var lastError: String?

    init(logger: AppRuntimeLogger = AppLog.runtime) {
        self.logger = logger
    }

    func start(profile: CoreProfile) {
        let profileSuffix = String(profile.id.uuidString.suffix(8))
        logger.info("Local core start requested profileSuffix=\(profileSuffix)")
        guard profile.kind == .local else {
            lastError = "The selected profile is not local."
            logger.error("Local core start rejected profileSuffix=\(profileSuffix) reason=non_local_profile")
            return
        }
        stop()
        clearOutput()
        lastError = nil
        isStopping = false

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", profile.localCommand]
        if !profile.localWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: profile.localWorkingDirectory, isDirectory: true)
        }

        let pipe = Pipe()
        let outputGeneration = self.outputGeneration
        outputPipe = pipe
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let generation = outputGeneration.current()
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendOutput(text, generation: generation)
            }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, self.process === process else { return }
                self.clearOutputPipe()
                self.process = nil
                self.isRunning = false
                if !self.isStopping && process.terminationStatus != 0 {
                    self.lastError = "Local core exited with status \(process.terminationStatus)."
                    self.logger.error("Local core exited status=\(process.terminationStatus)")
                } else {
                    self.logger.info("Local core exited status=\(process.terminationStatus)")
                }
                self.isStopping = false
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            lastError = nil
            logger.info("Local core started profileSuffix=\(profileSuffix)")
        } catch {
            isRunning = false
            lastError = error.localizedDescription
            logger.error("Local core start failed profileSuffix=\(profileSuffix) error=\(String(describing: type(of: error)))")
        }
    }

    func stop() {
        let wasRunning = process != nil
        if wasRunning {
            logger.info("Local core stop requested")
        }
        isStopping = process != nil
        clearOutputPipe()
        process?.terminate()
        process = nil
        isRunning = false
        isStopping = false
        if wasRunning {
            logger.info("Local core stop signal sent")
        }
    }

    func clearOutput() {
        outputGeneration.advance()
        lastOutput = ""
    }

    private func appendOutput(_ text: String, generation: UInt64) {
        guard outputGeneration.current() == generation else { return }
        lastOutput.append(text)
        if lastOutput.count > Self.outputCharacterLimit {
            lastOutput = String(lastOutput.suffix(Self.outputCharacterLimit))
        }
    }

    private func clearOutputPipe() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
    }
}
