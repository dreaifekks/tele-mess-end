import Darwin
import Dispatch
import Foundation
import Observation

enum LocalCoreProcessPhase: String, CaseIterable, Sendable {
    case idle
    case installing
    case starting
    case running
    case stopping
    case failed
}

private enum LocalCoreProcessPurpose: Equatable {
    case installation(profileID: UUID)
    case runtime(profileID: UUID)

    var profileID: UUID {
        switch self {
        case .installation(let profileID), .runtime(let profileID):
            profileID
        }
    }
}

private enum LocalCoreProcessControllerError: LocalizedError {
    case emptyCustomCommand
    case invalidWorkingDirectory(String)
    case missingWorkspaceConfiguration(String)
    case unreadableWorkspaceConfiguration(String)
    case processAlreadyActive
    case processDidNotExit

    var errorDescription: String? {
        switch self {
        case .emptyCustomCommand:
            "Enter a custom Core command before starting."
        case .invalidWorkingDirectory(let path):
            "The custom Core working directory does not exist: \(path)"
        case .missingWorkspaceConfiguration(let path):
            "Create the local Core configuration before starting: \(path)"
        case .unreadableWorkspaceConfiguration(let path):
            "The local Core configuration is not readable: \(path)"
        case .processAlreadyActive:
            "Another local Core operation is still running."
        case .processDidNotExit:
            "The previous local Core process did not exit after it was force-stopped."
        }
    }
}

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

private final class ActiveLocalCoreProcess {
    let operationID = UUID()
    let process: OwnedLocalCoreProcess
    let outputPipe: Pipe
    let purpose: LocalCoreProcessPurpose
    var terminationRequested = false
    var launchOperationPending = true
    var terminationCleanupPending = false
    var outputPipeClosed = false

    init(process: OwnedLocalCoreProcess, outputPipe: Pipe, purpose: LocalCoreProcessPurpose) {
        self.process = process
        self.outputPipe = outputPipe
        self.purpose = purpose
    }
}

/// A child launched into a process group whose ID is exactly the child's PID.
///
/// Foundation `Process` inherits the application's process group, so signaling
/// only its PID can leave shell or installer descendants behind. `posix_spawn`
/// with `POSIX_SPAWN_SETPGROUP` gives this controller an isolated group that it
/// can safely signal without ever targeting the app's own process group.
private final class OwnedLocalCoreProcess: @unchecked Sendable {
    typealias TerminationHandler = @Sendable (Int32) -> Void

    let processIdentifier: pid_t
    let processGroupIdentifier: pid_t

    private let lock = NSLock()
    private var running = true
    private var storedTerminationStatus: Int32?
    private var terminationHandler: TerminationHandler?
    private var exitSource: DispatchSourceProcess?

    var isRunning: Bool {
        reapExitedLeader(waitOptions: WNOHANG)
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    var terminationStatus: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return storedTerminationStatus ?? 0
    }

    /// Includes descendants that outlive the process-group leader.
    var isProcessGroupAlive: Bool {
        guard processGroupIdentifier > 1,
              processGroupIdentifier == processIdentifier else {
            return isRunning
        }
        if Darwin.kill(-processGroupIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    init(
        command: LocalCoreProcessCommand,
        standardOutput: Pipe
    ) throws {
        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        let fileActionInitializationError = posix_spawn_file_actions_init(&fileActions)
        guard fileActionInitializationError == 0 else {
            throw Self.posixError(
                fileActionInitializationError,
                operation: "prepare local Core process file actions"
            )
        }
        let attributeInitializationError = posix_spawnattr_init(&attributes)
        guard attributeInitializationError == 0 else {
            posix_spawn_file_actions_destroy(&fileActions)
            throw Self.posixError(
                attributeInitializationError,
                operation: "prepare local Core process attributes"
            )
        }
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attributes)
        }

        let readDescriptor = standardOutput.fileHandleForReading.fileDescriptor
        let writeDescriptor = standardOutput.fileHandleForWriting.fileDescriptor
        var actionError = posix_spawn_file_actions_adddup2(
            &fileActions,
            writeDescriptor,
            STDOUT_FILENO
        )
        if actionError == 0 {
            actionError = posix_spawn_file_actions_adddup2(
                &fileActions,
                writeDescriptor,
                STDERR_FILENO
            )
        }
        if actionError == 0 {
            actionError = posix_spawn_file_actions_addclose(&fileActions, readDescriptor)
        }
        if actionError == 0,
           writeDescriptor != STDOUT_FILENO,
           writeDescriptor != STDERR_FILENO {
            actionError = posix_spawn_file_actions_addclose(&fileActions, writeDescriptor)
        }
        if actionError == 0, let directory = command.currentDirectoryURL {
            actionError = directory.path.withCString {
                posix_spawn_file_actions_addchdir_np(&fileActions, $0)
            }
        }
        guard actionError == 0 else {
            throw Self.posixError(actionError, operation: "configure local Core process file actions")
        }

        let spawnFlags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
        var attributeError = posix_spawnattr_setflags(&attributes, spawnFlags)
        if attributeError == 0 {
            // A pgroup value of zero makes the spawned child's PID the new
            // process-group ID. We only ever signal the group after checking
            // this invariant, so the calling app's group cannot be targeted.
            attributeError = posix_spawnattr_setpgroup(&attributes, 0)
        }
        guard attributeError == 0 else {
            throw Self.posixError(attributeError, operation: "configure local Core process ownership")
        }

        let executablePath = command.executableURL.path
        let arguments = [executablePath] + command.arguments
        let environment = command.environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()
        var spawnedPID: pid_t = 0
        let spawnError = Self.withMutableCStringArray(arguments) { argumentVector in
            Self.withMutableCStringArray(environment) { environmentVector in
                executablePath.withCString { executable in
                    posix_spawn(
                        &spawnedPID,
                        executable,
                        &fileActions,
                        &attributes,
                        argumentVector,
                        environmentVector
                    )
                }
            }
        }
        guard spawnError == 0 else {
            throw Self.posixError(spawnError, operation: "launch local Core process")
        }

        processIdentifier = spawnedPID
        processGroupIdentifier = spawnedPID
        try? standardOutput.fileHandleForWriting.close()
    }

    func startMonitoring(terminationHandler: @escaping TerminationHandler) {
        lock.lock()
        self.terminationHandler = terminationHandler
        let source = DispatchSource.makeProcessSource(
            identifier: processIdentifier,
            eventMask: .exit,
            queue: DispatchQueue.global(qos: .utility)
        )
        exitSource = source
        lock.unlock()

        source.setEventHandler { [weak self] in
            self?.reapExitedLeader(waitOptions: 0)
        }
        source.resume()
    }

    @discardableResult
    func signalProcessGroup(_ signal: Int32) -> Bool {
        guard processGroupIdentifier > 1,
              processGroupIdentifier == processIdentifier,
              processGroupIdentifier != Darwin.getpgrp() else {
            return false
        }
        if Darwin.kill(-processGroupIdentifier, signal) == 0 {
            return true
        }
        return errno == ESRCH
    }

    private func reapExitedLeader(waitOptions: Int32) {
        var rawStatus: Int32 = 0
        var result: pid_t
        repeat {
            result = Darwin.waitpid(processIdentifier, &rawStatus, waitOptions)
        } while result == -1 && errno == EINTR
        guard result == processIdentifier else { return }

        let terminationStatus = Self.decodeWaitStatus(rawStatus)
        lock.lock()
        running = false
        storedTerminationStatus = terminationStatus
        let handler = terminationHandler
        terminationHandler = nil
        let source = exitSource
        exitSource = nil
        lock.unlock()

        source?.cancel()
        handler?(terminationStatus)
    }

    private static func decodeWaitStatus(_ rawStatus: Int32) -> Int32 {
        let waitStatus = rawStatus & 0x7f
        if waitStatus == 0 {
            return (rawStatus >> 8) & 0xff
        }
        if waitStatus == 0x7f {
            return (rawStatus >> 8) & 0xff
        }
        return waitStatus
    }

    private static func posixError(_ code: Int32, operation: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [
                NSLocalizedDescriptionKey: "Could not \(operation): \(String(cString: strerror(code)))"
            ]
        )
    }

    private static func withMutableCStringArray<Result>(
        _ strings: [String],
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
    ) -> Result {
        let pointers = strings.map { strdup($0) }
        defer {
            for pointer in pointers {
                free(pointer)
            }
        }
        var terminatedPointers: [UnsafeMutablePointer<CChar>?] = pointers + [nil]
        return terminatedPointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress!)
        }
    }
}

@MainActor
@Observable
final class LocalCoreProcessController {
    private static let outputCharacterLimit = 200_000
    private static let gracefulStopPollCount = 100
    private static let forcedStopPollCount = 20
    private static let stopPollInterval = Duration.milliseconds(100)
    private static let quickExitCheckDelay = Duration.milliseconds(250)

    @ObservationIgnored private let logger: AppRuntimeLogger
    @ObservationIgnored private let managedRuntimeFactory: (CoreProfile) throws -> ManagedLocalCoreRuntime
    @ObservationIgnored private let outputGeneration = LocalCoreOutputGeneration()
    @ObservationIgnored private var activeProcess: ActiveLocalCoreProcess?
    @ObservationIgnored private var lifecycleRevision: UInt64 = 0

    private(set) var phase: LocalCoreProcessPhase = .idle
    private(set) var status = "Stopped"
    private(set) var statusProfileID: UUID?
    private(set) var activeOperationID: UUID?
    private(set) var activeProfileID: UUID?
    private(set) var runningProfileID: UUID?
    private(set) var installedVersion: String?
    private(set) var lastOutput = ""
    private(set) var lastError: String?

    var isBusy: Bool {
        switch phase {
        case .installing, .starting, .stopping:
            true
        case .idle, .running, .failed:
            false
        }
    }

    var isRunning: Bool {
        guard let activeProcess,
              case .runtime = activeProcess.purpose else {
            return false
        }
        return activeProcess.process.isRunning
    }

    init(
        logger: AppRuntimeLogger = AppLog.runtime,
        managedRuntimeFactory: @escaping (CoreProfile) throws -> ManagedLocalCoreRuntime = {
            try ManagedLocalCoreRuntime(profile: $0)
        }
    ) {
        self.logger = logger
        self.managedRuntimeFactory = managedRuntimeFactory
    }

    /// Compatibility entry point for callers that have not yet adopted the
    /// awaited lifecycle API. New code should call the async overload.
    func start(profile: CoreProfile) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let _: Bool = await self.start(profile: profile)
        }
    }

    /// Compatibility entry point for callers that have not yet adopted the
    /// awaited lifecycle API. New code should call the async overload.
    func stop() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let _: Bool = await self.stop()
        }
    }

    @discardableResult
    func install(profile: CoreProfile, force: Bool = false) async -> Bool {
        let profileSuffix = String(profile.id.uuidString.suffix(8))
        statusProfileID = profile.id
        let revision = beginLifecycleRequest()
        logger.info("Local core install requested profileSuffix=\(profileSuffix) force=\(force)")

        guard profile.kind == .local else {
            setFailure(
                "The selected profile is not local.",
                profileSuffix: profileSuffix,
                reason: "non_local_profile"
            )
            return false
        }
        guard profile.localRuntimeMode == .managedPyPI else {
            setFailure(
                "Custom command profiles do not use the managed Core installer.",
                profileSuffix: profileSuffix,
                reason: "custom_command_profile"
            )
            return false
        }
        guard await stopActiveProcess(requestRevision: revision), revision == lifecycleRevision else {
            return false
        }

        clearOutput()
        lastError = nil

        do {
            let runtime = try managedRuntimeFactory(profile)
            try runtime.prepareDirectories()
            installedVersion = runtime.installedVersion
            if runtime.isInstalled, !force {
                phase = .idle
                status = "Installed \(runtime.version)"
                logger.info("Local core install skipped profileSuffix=\(profileSuffix) reason=already_installed")
                return true
            }
            return await performManagedInstallation(
                runtime: runtime,
                profileID: profile.id,
                profileSuffix: profileSuffix,
                force: force,
                requestRevision: revision
            )
        } catch {
            guard revision == lifecycleRevision else { return false }
            setFailure(
                error.localizedDescription,
                profileSuffix: profileSuffix,
                reason: "installer_preparation_failed",
                errorType: error
            )
            return false
        }
    }

    @discardableResult
    func start(profile: CoreProfile) async -> Bool {
        let profileSuffix = String(profile.id.uuidString.suffix(8))
        statusProfileID = profile.id
        let revision = beginLifecycleRequest()
        logger.info("Local core start requested profileSuffix=\(profileSuffix)")

        guard profile.kind == .local else {
            setFailure(
                "The selected profile is not local.",
                profileSuffix: profileSuffix,
                reason: "non_local_profile"
            )
            return false
        }
        guard await stopActiveProcess(requestRevision: revision), revision == lifecycleRevision else {
            return false
        }

        clearOutput()
        lastError = nil

        do {
            let command: LocalCoreProcessCommand
            switch profile.localRuntimeMode {
            case .managedPyPI:
                let runtime = try managedRuntimeFactory(profile)
                let workspace = runtime.workspaceStatus()
                guard workspace.configurationExists else {
                    throw LocalCoreProcessControllerError.missingWorkspaceConfiguration(
                        workspace.configurationFileURL.path
                    )
                }
                guard workspace.configurationIsReadable else {
                    throw LocalCoreProcessControllerError.unreadableWorkspaceConfiguration(
                        workspace.configurationFileURL.path
                    )
                }
                try runtime.prepareDirectories()
                installedVersion = runtime.installedVersion
                if !runtime.isInstalled {
                    guard await performManagedInstallation(
                        runtime: runtime,
                        profileID: profile.id,
                        profileSuffix: profileSuffix,
                        force: false,
                        requestRevision: revision
                    ), revision == lifecycleRevision else {
                        return false
                    }
                }
                command = runtime.runCommand()
            case .customCommand:
                installedVersion = nil
                command = try customProcessCommand(profile: profile)
            }

            guard revision == lifecycleRevision else { return false }
            phase = .starting
            status = "Starting"
            runningProfileID = profile.id

            let active = try launchProcess(
                command: command,
                purpose: .runtime(profileID: profile.id)
            )
            try? await Task.sleep(for: Self.quickExitCheckDelay)

            guard revision == lifecycleRevision,
                  activeProcess === active else { return false }
            if !active.process.isRunning {
                let exitStatus = active.process.terminationStatus
                active.terminationRequested = true
                var groupExited = await terminateProcessGroup(active)
                if !groupExited {
                    logger.warning("Local core early-exit cleanup timed out purpose=\(purposeLabel(active.purpose))")
                    _ = active.process.signalProcessGroup(SIGKILL)
                    groupExited = await waitForProcessGroupExit(
                        active,
                        pollCount: Self.forcedStopPollCount
                    )
                }
                guard revision == lifecycleRevision,
                      activeProcess === active else { return false }
                active.launchOperationPending = false
                if groupExited {
                    finishProcess(active)
                }
                setFailure(
                    groupExited
                        ? "Local core exited before it became ready with status \(exitStatus)."
                        : LocalCoreProcessControllerError.processDidNotExit.localizedDescription,
                    profileSuffix: profileSuffix,
                    reason: groupExited ? "early_exit_\(exitStatus)" : "early_exit_group_did_not_exit"
                )
                return false
            }

            active.launchOperationPending = false
            phase = .starting
            status = "Waiting for Core"
            lastError = nil
            logger.info("Local core spawned profileSuffix=\(profileSuffix)")
            return true
        } catch {
            guard revision == lifecycleRevision else { return false }
            runningProfileID = nil
            setFailure(
                error.localizedDescription,
                profileSuffix: profileSuffix,
                reason: "launch_failed",
                errorType: error
            )
            return false
        }
    }

    @discardableResult
    func stop() async -> Bool {
        let revision = beginLifecycleRequest()
        let stopped = await stopActiveProcess(requestRevision: revision)
        guard revision == lifecycleRevision else { return false }
        if stopped {
            phase = .idle
            status = installedVersion.map { "Installed \($0)" } ?? "Stopped"
            lastError = nil
        }
        return stopped
    }

    /// Stops the process only when it is still the operation captured by the
    /// caller. A delayed fire-and-forget stop therefore cannot terminate a
    /// newer install or runtime that replaced the original process.
    @discardableResult
    func stop(ifOwnedByOperationID operationID: UUID) async -> Bool {
        guard activeProcess?.operationID == operationID else {
            return true
        }
        return await stop()
    }

    @discardableResult
    func markReady(profileID: UUID) -> Bool {
        guard let activeProcess,
              activeProcess.process.isRunning,
              activeProcess.purpose == .runtime(profileID: profileID),
              runningProfileID == profileID else {
            return false
        }
        phase = .running
        status = "Running"
        lastError = nil
        logger.info("Local core ready profileSuffix=\(String(profileID.uuidString.suffix(8)))")
        return true
    }

    @discardableResult
    func markReadinessFailed(profileID: UUID, message: String) -> Bool {
        guard let activeProcess,
              activeProcess.process.isRunning,
              activeProcess.purpose == .runtime(profileID: profileID),
              runningProfileID == profileID else {
            return false
        }
        phase = .failed
        status = "Failed"
        lastError = message
        logger.error("Local core readiness failed profileSuffix=\(String(profileID.uuidString.suffix(8)))")
        return true
    }

    /// Synchronously crosses the TERM/KILL process-group barrier so application
    /// termination cannot orphan a running Core, custom shell child, or uv
    /// installer descendant. Normal UI stops should use `stop()` and await the
    /// same barrier without blocking the main thread.
    func shutdown() {
        lifecycleRevision &+= 1
        guard let activeProcess else { return }
        activeProcess.terminationRequested = true
        phase = .stopping
        status = "Stopping"
        _ = activeProcess.process.signalProcessGroup(SIGTERM)
        logger.info("Local core shutdown signal sent purpose=\(purposeLabel(activeProcess.purpose))")

        var exited = waitForProcessGroupExitSynchronously(
            activeProcess,
            pollCount: Self.gracefulStopPollCount
        )
        if !exited {
            logger.warning("Local core shutdown graceful stop timed out purpose=\(purposeLabel(activeProcess.purpose))")
            _ = activeProcess.process.signalProcessGroup(SIGKILL)
            exited = waitForProcessGroupExitSynchronously(
                activeProcess,
                pollCount: Self.forcedStopPollCount
            )
        }

        guard exited else {
            setFailure(
                LocalCoreProcessControllerError.processDidNotExit.localizedDescription,
                profileSuffix: profileSuffix(for: activeProcess.purpose),
                reason: "shutdown_process_did_not_exit"
            )
            return
        }
        activeProcess.launchOperationPending = false
        finishProcess(activeProcess)
        phase = .idle
        status = installedVersion.map { "Installed \($0)" } ?? "Stopped"
        lastError = nil
    }

    func clearOutput() {
        outputGeneration.advance()
        lastOutput = ""
    }

    private func beginLifecycleRequest() -> UInt64 {
        lifecycleRevision &+= 1
        return lifecycleRevision
    }

    private func performManagedInstallation(
        runtime: ManagedLocalCoreRuntime,
        profileID: UUID,
        profileSuffix: String,
        force: Bool,
        requestRevision: UInt64
    ) async -> Bool {
        guard requestRevision == lifecycleRevision else { return false }
        do {
            phase = .installing
            status = force ? "Updating Core" : "Installing Core"
            lastError = nil
            let installCommand = try runtime.installCommand(force: force)
            try runtime.invalidateInstalledVersionMarker()
            let active = try launchProcess(
                command: installCommand,
                purpose: .installation(profileID: profileID)
            )
            let exitStatus = await waitForProcessExit(
                active,
                requestRevision: requestRevision
            )
            guard requestRevision == lifecycleRevision, let exitStatus else { return false }

            if active.process.isProcessGroupAlive {
                active.terminationRequested = true
                var groupExited = await terminateProcessGroup(active)
                if !groupExited {
                    logger.warning("Local core installer leader exited with live descendants profileSuffix=\(profileSuffix)")
                    _ = active.process.signalProcessGroup(SIGKILL)
                    groupExited = await waitForProcessGroupExit(
                        active,
                        pollCount: Self.forcedStopPollCount
                    )
                }
                guard requestRevision == lifecycleRevision,
                      activeProcess === active else { return false }
                guard groupExited else {
                    active.launchOperationPending = false
                    setFailure(
                        LocalCoreProcessControllerError.processDidNotExit.localizedDescription,
                        profileSuffix: profileSuffix,
                        reason: "installer_group_did_not_exit"
                    )
                    return false
                }
            }

            guard requestRevision == lifecycleRevision,
                  activeProcess === active else { return false }
            active.launchOperationPending = false
            finishProcess(active)
            guard exitStatus == 0 else {
                setFailure(
                    "Core installation exited with status \(exitStatus).",
                    profileSuffix: profileSuffix,
                    reason: "install_exit_\(exitStatus)"
                )
                return false
            }

            try runtime.markInstalled()
            installedVersion = runtime.version
            phase = .idle
            status = "Installed \(runtime.version)"
            lastError = nil
            logger.info("Local core install completed profileSuffix=\(profileSuffix) version=\(runtime.version)")
            return true
        } catch {
            guard requestRevision == lifecycleRevision else { return false }
            setFailure(
                error.localizedDescription,
                profileSuffix: profileSuffix,
                reason: "install_failed",
                errorType: error
            )
            return false
        }
    }

    private func customProcessCommand(profile: CoreProfile) throws -> LocalCoreProcessCommand {
        let command = profile.localCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw LocalCoreProcessControllerError.emptyCustomCommand
        }

        let workingDirectory: URL?
        let rawWorkingDirectory = profile.localWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawWorkingDirectory.isEmpty {
            workingDirectory = nil
        } else {
            let expandedPath = NSString(string: rawWorkingDirectory).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw LocalCoreProcessControllerError.invalidWorkingDirectory(expandedPath)
            }
            workingDirectory = URL(fileURLWithPath: expandedPath, isDirectory: true)
        }

        return LocalCoreProcessCommand(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", command],
            currentDirectoryURL: workingDirectory,
            environment: ProcessInfo.processInfo.environment
        )
    }

    private func launchProcess(
        command: LocalCoreProcessCommand,
        purpose: LocalCoreProcessPurpose
    ) throws -> ActiveLocalCoreProcess {
        guard activeProcess == nil else {
            throw LocalCoreProcessControllerError.processAlreadyActive
        }

        let pipe = Pipe()
        let outputGeneration = self.outputGeneration
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let generation = outputGeneration.current()
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendOutput(text, generation: generation)
            }
        }

        do {
            let process = try OwnedLocalCoreProcess(
                command: command,
                standardOutput: pipe
            )
            let active = ActiveLocalCoreProcess(
                process: process,
                outputPipe: pipe,
                purpose: purpose
            )
            activeProcess = active
            activeOperationID = active.operationID
            activeProfileID = purpose.profileID
            process.startMonitoring { [weak self, weak active] exitStatus in
                Task { @MainActor [weak self, weak active] in
                    guard let self, let active else { return }
                    self.handleTermination(active, exitStatus: exitStatus)
                }
            }
            logger.info("Local core process launched purpose=\(purposeLabel(purpose))")
            return active
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
            logger.error("Local core process launch failed purpose=\(purposeLabel(purpose)) error=\(String(describing: type(of: error)))")
            throw error
        }
    }

    private func stopActiveProcess(requestRevision: UInt64) async -> Bool {
        guard let active = activeProcess else {
            runningProfileID = nil
            return true
        }

        active.terminationRequested = true
        if requestRevision == lifecycleRevision {
            phase = .stopping
            status = "Stopping"
            logger.info("Local core stop requested purpose=\(purposeLabel(active.purpose))")
        }
        _ = active.process.signalProcessGroup(SIGTERM)

        var exited = await waitForProcessGroupExit(
            active,
            pollCount: Self.gracefulStopPollCount
        )
        if !exited {
            logger.warning("Local core graceful stop timed out purpose=\(purposeLabel(active.purpose))")
            _ = active.process.signalProcessGroup(SIGKILL)
            exited = await waitForProcessGroupExit(
                active,
                pollCount: Self.forcedStopPollCount
            )
        }

        guard exited else {
            if requestRevision == lifecycleRevision,
               activeProcess === active {
                setFailure(
                    LocalCoreProcessControllerError.processDidNotExit.localizedDescription,
                    profileSuffix: profileSuffix(for: active.purpose),
                    reason: "process_did_not_exit"
                )
            }
            return false
        }

        guard activeProcess === active else { return true }
        active.launchOperationPending = false
        finishProcess(active)
        if requestRevision == lifecycleRevision {
            phase = .idle
            status = installedVersion.map { "Installed \($0)" } ?? "Stopped"
            lastError = nil
            logger.info("Local core stopped purpose=\(purposeLabel(active.purpose))")
        }
        return true
    }

    private func waitForProcessExit(
        _ active: ActiveLocalCoreProcess,
        requestRevision: UInt64
    ) async -> Int32? {
        while active.process.isRunning {
            guard requestRevision == lifecycleRevision else { return nil }
            try? await Task.sleep(for: Self.stopPollInterval)
        }
        return active.process.terminationStatus
    }

    private func waitForProcessGroupExit(
        _ active: ActiveLocalCoreProcess,
        pollCount: Int
    ) async -> Bool {
        for _ in 0..<pollCount {
            if !active.process.isRunning, !active.process.isProcessGroupAlive {
                return true
            }
            try? await Task.sleep(for: Self.stopPollInterval)
        }
        return !active.process.isRunning && !active.process.isProcessGroupAlive
    }

    private func terminateProcessGroup(_ active: ActiveLocalCoreProcess) async -> Bool {
        _ = active.process.signalProcessGroup(SIGTERM)
        return await waitForProcessGroupExit(
            active,
            pollCount: Self.gracefulStopPollCount
        )
    }

    private func waitForProcessGroupExitSynchronously(
        _ active: ActiveLocalCoreProcess,
        pollCount: Int
    ) -> Bool {
        for _ in 0..<pollCount {
            if !active.process.isRunning, !active.process.isProcessGroupAlive {
                return true
            }
            Darwin.usleep(100_000)
        }
        return !active.process.isRunning && !active.process.isProcessGroupAlive
    }

    private func handleTermination(_ active: ActiveLocalCoreProcess, exitStatus: Int32) {
        guard activeProcess === active else { return }
        guard !active.launchOperationPending else { return }
        guard !active.terminationRequested else { return }
        guard !active.terminationCleanupPending else { return }
        active.terminationCleanupPending = true
        active.terminationRequested = true
        phase = .stopping
        status = "Cleaning Up"
        let cleanupRevision = lifecycleRevision

        Task { @MainActor [weak self, weak active] in
            guard let self, let active, self.activeProcess === active else { return }
            var groupExited = await self.terminateProcessGroup(active)
            if !groupExited {
                self.logger.warning("Local core unexpected-exit cleanup timed out purpose=\(self.purposeLabel(active.purpose))")
                _ = active.process.signalProcessGroup(SIGKILL)
                groupExited = await self.waitForProcessGroupExit(
                    active,
                    pollCount: Self.forcedStopPollCount
                )
            }
            guard self.activeProcess === active,
                  self.lifecycleRevision == cleanupRevision else { return }
            guard groupExited else {
                self.setFailure(
                    LocalCoreProcessControllerError.processDidNotExit.localizedDescription,
                    profileSuffix: self.profileSuffix(for: active.purpose),
                    reason: "unexpected_exit_group_did_not_exit"
                )
                return
            }
            self.finishProcess(active)

            switch active.purpose {
            case .installation:
                self.setFailure(
                    "Core installation exited with status \(exitStatus).",
                    profileSuffix: self.profileSuffix(for: active.purpose),
                    reason: "unexpected_install_exit_\(exitStatus)"
                )
            case .runtime(let profileID):
                self.setFailure(
                    "Local core exited unexpectedly with status \(exitStatus).",
                    profileSuffix: String(profileID.uuidString.suffix(8)),
                    reason: "unexpected_exit_\(exitStatus)"
                )
            }
        }
    }

    private func finishProcess(_ active: ActiveLocalCoreProcess) {
        let ownsCurrentState = activeProcess === active
        closeOutputPipe(active, appendingRemainingOutput: ownsCurrentState)
        guard ownsCurrentState else { return }
        activeProcess = nil
        activeOperationID = nil
        activeProfileID = nil
        if case .runtime(let profileID) = active.purpose,
           runningProfileID == profileID {
            runningProfileID = nil
        }
    }

    private func closeOutputPipe(
        _ active: ActiveLocalCoreProcess,
        appendingRemainingOutput: Bool
    ) {
        guard !active.outputPipeClosed else { return }
        active.outputPipeClosed = true
        active.outputPipe.fileHandleForReading.readabilityHandler = nil
        try? active.outputPipe.fileHandleForWriting.close()
        let remainingData = drainAvailableOutput(from: active.outputPipe.fileHandleForReading)
        try? active.outputPipe.fileHandleForReading.close()
        if appendingRemainingOutput,
           !remainingData.isEmpty,
           let text = String(data: remainingData, encoding: .utf8) {
            appendOutput(text, generation: outputGeneration.current())
        }
    }

    private func drainAvailableOutput(from handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        let currentFlags = Darwin.fcntl(descriptor, F_GETFL)
        if currentFlags >= 0 {
            _ = Darwin.fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK)
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func appendOutput(_ text: String, generation: UInt64) {
        guard outputGeneration.current() == generation else { return }
        lastOutput.append(text)
        if lastOutput.count > Self.outputCharacterLimit {
            lastOutput = String(lastOutput.suffix(Self.outputCharacterLimit))
        }
    }

    private func setFailure(
        _ message: String,
        profileSuffix: String,
        reason: String,
        errorType: Error? = nil
    ) {
        phase = .failed
        status = "Failed"
        lastError = message
        runningProfileID = nil
        if let errorType {
            logger.error("Local core operation failed profileSuffix=\(profileSuffix) reason=\(reason) error=\(String(describing: type(of: errorType)))")
        } else {
            logger.error("Local core operation failed profileSuffix=\(profileSuffix) reason=\(reason)")
        }
    }

    private func purposeLabel(_ purpose: LocalCoreProcessPurpose) -> String {
        switch purpose {
        case .installation:
            "install"
        case .runtime:
            "runtime"
        }
    }

    private func profileSuffix(for purpose: LocalCoreProcessPurpose) -> String {
        switch purpose {
        case .installation(let profileID), .runtime(let profileID):
            String(profileID.uuidString.suffix(8))
        }
    }
}
