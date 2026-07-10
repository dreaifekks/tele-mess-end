import Foundation
import Observation

@MainActor
@Observable
final class LocalCoreProcessController {
    private static let outputCharacterLimit = 200_000

    private var process: Process?
    private var outputPipe: Pipe?
    private var isStopping = false
    var isRunning = false
    var lastOutput = ""
    var lastError: String?

    func start(profile: CoreProfile) {
        guard profile.kind == .local else {
            lastError = "The selected profile is not local."
            return
        }
        stop()
        lastOutput = ""
        lastError = nil
        isStopping = false

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", profile.localCommand]
        if !profile.localWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: profile.localWorkingDirectory, isDirectory: true)
        }

        let pipe = Pipe()
        outputPipe = pipe
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendOutput(text)
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
                }
                self.isStopping = false
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            lastError = nil
        } catch {
            isRunning = false
            lastError = error.localizedDescription
        }
    }

    func stop() {
        isStopping = process != nil
        clearOutputPipe()
        process?.terminate()
        process = nil
        isRunning = false
        isStopping = false
    }

    private func appendOutput(_ text: String) {
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
