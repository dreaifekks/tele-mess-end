import Foundation
import Observation

@MainActor
@Observable
final class LocalCoreProcessController {
    private var process: Process?
    var isRunning = false
    var lastOutput = ""
    var lastError: String?

    func start(profile: CoreProfile) {
        guard profile.kind == .local else {
            lastError = "The selected profile is not local."
            return
        }
        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", profile.localCommand]
        if !profile.localWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: profile.localWorkingDirectory, isDirectory: true)
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.lastOutput += text
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
        process?.terminate()
        process = nil
        isRunning = false
    }
}
