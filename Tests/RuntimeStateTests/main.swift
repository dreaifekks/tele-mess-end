import Darwin
import Foundation
import Security

@main
enum RuntimeStateTests {
    static func main() async {
        var runner = RuntimeTestRunner()
        await runner.run("summary settings are isolated by profile") {
            try summarySettingsAreProfileScoped()
        }
        await runner.run("profile selection resolves nil and invalid IDs") {
            try profileSelectionAlwaysResolves()
        }
        await runner.run("legacy profiles preserve fields and migrate local runtime modes") {
            try legacyProfilesPreserveFieldsAndMigrateRuntimeModes()
        }
        await runner.run("managed local runtime builds pinned paths and web command") {
            try managedRuntimeBuildsPinnedPathsAndWebCommand()
        }
        await runner.run("managed local runtime locates uv without shell startup") {
            try managedRuntimeLocatesUVWithoutShellStartup()
        }
        await runner.run("managed installation marker invalidates before repair") {
            try managedInstallationMarkerInvalidatesBeforeRepair()
        }
        await runner.run("managed local bootstrap is private and non-destructive") {
            try managedBootstrapIsPrivateAndNonDestructive()
        }
        await runner.run("managed bootstrap normalizes the local profile to bearer auth") {
            try await managedBootstrapNormalizesBearerAuth()
        }
        await runner.run("managed bootstrap requests Keychain authorization before writing config") {
            try await managedBootstrapRequestsKeychainAuthorizationBeforeWriting()
        }
        await runner.run("managed bootstrap rolls back when Keychain save needs authorization") {
            try await managedBootstrapRollsBackWhenKeychainSaveNeedsAuthorization()
        }
        await runner.run("managed bootstrap repairs Keychain access on explicit retry") {
            try await managedBootstrapRepairsKeychainAccessOnExplicitRetry()
        }
        await runner.run("automatic refresh waits for managed local setup") {
            try await automaticRefreshWaitsForManagedLocalSetup()
        }
        await runner.run("custom local Core follows awaited lifecycle") {
            try await customLocalCoreFollowsAwaitedLifecycle()
        }
        await runner.run("custom local Core reports an early exit") {
            try await customLocalCoreReportsEarlyExit()
        }
        await runner.run("early-exit cleanup reaps the owned process group") {
            try await earlyExitCleanupReapsOwnedProcessGroup()
        }
        await runner.run("synchronous shutdown crosses the process-group barrier") {
            try await synchronousShutdownCrossesProcessGroupBarrier()
        }
        await runner.run("stale operation ownership cannot stop a newer Core") {
            try await staleOperationOwnershipCannotStopNewerCore()
        }
        await runner.run("overlapping same-profile waiters preserve the replacement owner") {
            try await overlappingSameProfileWaitersPreserveReplacementOwner()
        }
        await runner.run("AppModel marks a custom local Core ready from the authenticated API") {
            try await appModelMarksCustomLocalCoreReadyFromAuthenticatedAPI()
        }
        await runner.run("saving a running local profile requires an explicit stop") {
            try await savingRunningLocalProfileRequiresStop()
        }
        await runner.run("superseded AppModel start cannot stop the newer Core") {
            try await supersededAppModelStartCannotStopNewerCore()
        }
        await runner.run("stopping during validation cannot restore stale verified state") {
            try await stoppingDuringValidationCannotRestoreStaleState()
        }
        await runner.run("delivery fallback distinguishes omitted and null") {
            try deliveryFallbackUsesFieldPresence()
        }
        await runner.run("summary target options follow the active draft") {
            try summaryTargetOptionsFollowDraft()
        }
        await runner.run("auth-disabled local core loads without token") {
            try await localCoreLoadsWithoutToken()
        }
        await runner.run("remote background load requires a token") {
            try await remoteBackgroundLoadRequiresToken()
        }
        await runner.run("protected local token never degrades to no auth") {
            try await protectedLocalTokenDoesNotDegrade()
        }
        await runner.run("legacy token migrates without deletion") {
            try legacyTokenMigratesWithoutDeletion()
        }
        await runner.run("inaccessible managed token rotates on save") {
            try inaccessibleManagedTokenRotatesOnSave()
        }
        await runner.run("Keychain authorization unlocks before reading credentials") {
            try keychainAuthorizationUnlocksBeforeReadingCredentials()
        }
        await runner.run("managed clear masks a legacy token") {
            try managedClearMasksLegacyToken()
        }
        await runner.run("runtime log buffer is bounded and clearable") {
            try runtimeLogBufferIsBoundedAndClearable()
        }
        await runner.run("runtime log store follows concurrent writers") {
            try await runtimeLogStoreFollowsConcurrentWriters()
        }
        await runner.run("Core output clear keeps later process output") {
            try await coreOutputClearKeepsLaterProcessOutput()
        }
        await runner.run("keychain runtime logs omit credential material") {
            try keychainRuntimeLogsOmitCredentialMaterial()
        }
        await runner.run("app operation failures emit safe runtime logs") {
            try await appOperationFailuresEmitSafeRuntimeLogs()
        }
        await runner.run("API runtime logs omit auth and query values") {
            try await apiRuntimeLogsOmitAuthAndQueryValues()
        }
        await runner.run("saving the same profile advances the session") {
            try sameProfileSaveAdvancesSession()
        }
        await runner.run("successful account mutation survives refresh failure") {
            try await accountMutationSurvivesRefreshFailure()
        }
        await runner.run("partial batch mutation remains visible") {
            try await partialBatchMutationRemainsVisible()
        }
        await runner.run("stale profile request cannot commit") {
            try await staleProfileRequestIsDiscarded()
        }
        await runner.run("newer search wins within one profile") {
            try await newerSearchWins()
        }
        await runner.run("manifest bootstraps before feature loading") {
            try await manifestBootstrapsBeforeFeatureLoad()
        }
        await runner.run("message points follow manifest, filters, item loading, and session reset") {
            try await messagePointsFollowManifestAndSession()
        }
        await runner.run("busy validation waits without false failure") {
            try await busyValidationDoesNotFail()
        }
        runner.finish()
    }

    @MainActor
    private static func summarySettingsAreProfileScoped() throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let store = SummarySettingsStore(defaults: defaults)
        let firstProfileID = UUID()
        let secondProfileID = UUID()

        store.selectProfile(firstProfileID)
        var firstSettings = SummarySettings()
        firstSettings.deliveryEnabled = true
        firstSettings.deliveryAccountID = "first"
        firstSettings.deliveryOriginID = "-1001"
        store.save(firstSettings)

        store.selectProfile(secondProfileID)
        try expectEqual(store.settings.deliveryEnabled, false)
        var secondSettings = SummarySettings()
        secondSettings.deliveryAccountID = "second"
        store.save(secondSettings)

        store.selectProfile(firstProfileID)
        try expectEqual(store.settings.deliveryEnabled, true)
        try expectEqual(store.settings.deliveryAccountID, "first")
        try expectEqual(store.settings.deliveryOriginID, "-1001")
    }

    @MainActor
    private static func profileSelectionAlwaysResolves() throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let store = CoreProfileStore(defaults: defaults)
        let firstID = store.selectedProfile?.id

        store.select(nil)
        try expectEqual(store.selectedProfileID, firstID)
        store.select(UUID())
        try expectEqual(store.selectedProfileID, firstID)
    }

    private static func legacyProfilesPreserveFieldsAndMigrateRuntimeModes() throws {
        let remoteID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let customLocalID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let managedLocalID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let relativeManagedLocalID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        let legacyJSON =
            """
            [
              {
                "id": "\(remoteID.uuidString)",
                "name": "Existing Remote",
                "kind": "remote",
                "baseURLString": "https://core.example.test:8765",
                "authMode": "apiToken",
                "localCommand": "",
                "localWorkingDirectory": "",
                "createdAt": 100,
                "updatedAt": 200
              },
              {
                "id": "\(customLocalID.uuidString)",
                "name": "Existing Custom Local",
                "kind": "local",
                "baseURLString": "http://127.0.0.1:9876",
                "authMode": "bearer",
                "localCommand": "python3 -m tele_mess_core serve-custom",
                "localWorkingDirectory": "/tmp/custom-core",
                "createdAt": 300,
                "updatedAt": 400
              },
              {
                "id": "\(managedLocalID.uuidString)",
                "name": "Existing Managed Local",
                "kind": "local",
                "baseURLString": "http://127.0.0.1:8765",
                "authMode": "bearer",
                "localCommand": "tele-mess-core run-server --config config.yml",
                "localWorkingDirectory": "/tmp/existing core workspace",
                "createdAt": 500,
                "updatedAt": 600
              },
              {
                "id": "\(relativeManagedLocalID.uuidString)",
                "name": "Relative Managed Local",
                "kind": "local",
                "baseURLString": "http://127.0.0.1:8765",
                "authMode": "bearer",
                "localCommand": "tele-mess-core run-server --config config.yml",
                "localWorkingDirectory": "relative-core-workspace",
                "createdAt": 700,
                "updatedAt": 800
              }
            ]
            """

        let profiles = try JSONDecoder().decode([CoreProfile].self, from: Data(legacyJSON.utf8))
        try expectEqual(profiles.count, 4)

        let remote = profiles[0]
        try expectEqual(remote.id, remoteID)
        try expectEqual(remote.name, "Existing Remote")
        try expectEqual(remote.kind, .remote)
        try expectEqual(remote.baseURLString, "https://core.example.test:8765")
        try expectEqual(remote.authMode, .apiToken)
        try expectEqual(remote.createdAt, Date(timeIntervalSinceReferenceDate: 100))
        try expectEqual(remote.updatedAt, Date(timeIntervalSinceReferenceDate: 200))

        let customLocal = profiles[1]
        try expectEqual(customLocal.id, customLocalID)
        try expectEqual(customLocal.localRuntimeMode, .customCommand)
        try expectEqual(customLocal.localCommand, "python3 -m tele_mess_core serve-custom")
        try expectEqual(customLocal.localWorkingDirectory, "/tmp/custom-core")
        try expectEqual(customLocal.localCoreVersion, CoreProfile.defaultManagedLocalCoreVersion)

        let managedLocal = profiles[2]
        try expectEqual(managedLocal.id, managedLocalID)
        try expectEqual(managedLocal.localRuntimeMode, .managedPyPI)
        try expectEqual(managedLocal.localWorkspaceDirectory, "/tmp/existing core workspace")
        try expectEqual(managedLocal.localCommand, CoreProfile.legacyDefaultLocalCommand)

        let relativeManagedLocal = profiles[3]
        try expectEqual(relativeManagedLocal.id, relativeManagedLocalID)
        try expectEqual(relativeManagedLocal.localRuntimeMode, .managedPyPI)
        try expectEqual(
            relativeManagedLocal.localWorkspaceDirectory,
            URL(fileURLWithPath: "relative-core-workspace", isDirectory: true).standardizedFileURL.path
        )

        let roundTripped = try JSONDecoder().decode(
            [CoreProfile].self,
            from: JSONEncoder().encode(profiles)
        )
        try expectEqual(roundTripped, profiles)
    }

    private static func managedRuntimeBuildsPinnedPathsAndWebCommand() throws {
        let root = try makeTemporaryDirectory(named: "managed runtime paths")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("Home", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let workspace = root.appendingPathComponent("Workspace With Spaces", isDirectory: true)
        var profile = CoreProfile.defaultLocal
        profile.localCoreVersion = "0.3.0"
        profile.localWorkspaceDirectory = workspace.path

        let runtime = try ManagedLocalCoreRuntime(
            profile: profile,
            environment: [:],
            applicationSupportDirectory: support,
            homeDirectory: home
        )
        let expectedVersionDirectory = support
            .appendingPathComponent("TeleMessEnd/CoreRuntime/versions/0.3.0", isDirectory: true)
            .standardizedFileURL
        try expectEqual(runtime.versionDirectory, expectedVersionDirectory)
        try expectEqual(
            runtime.managedCoreExecutableURL,
            expectedVersionDirectory.appendingPathComponent("bin/tele-mess-core", isDirectory: false)
        )

        let command = runtime.runCommand()
        try expectEqual(command.executableURL, runtime.managedCoreExecutableURL)
        try expectEqual(
            command.arguments,
            ["run-local", "--workspace", workspace.standardizedFileURL.path, "--web"]
        )
        try expectNil(command.currentDirectoryURL)
        try expectEqual(command.environment["UV_TOOL_DIR"], runtime.uvToolDirectory.path)
        try expectEqual(command.environment["UV_TOOL_BIN_DIR"], runtime.uvBinDirectory.path)
        try expectEqual(command.environment["UV_CACHE_DIR"], runtime.uvCacheDirectory.path)
    }

    private static func managedRuntimeLocatesUVWithoutShellStartup() throws {
        let root = try makeTemporaryDirectory(named: "uv locator")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("Home", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let pathBin = root.appendingPathComponent("Injected Bin", isDirectory: true)
        try FileManager.default.createDirectory(at: pathBin, withIntermediateDirectories: true)
        let uvExecutable = pathBin.appendingPathComponent("uv", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: uvExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: uvExecutable.path
        )

        let profile = CoreProfile.defaultLocal
        let runtime = try ManagedLocalCoreRuntime(
            profile: profile,
            environment: [
                "PATH": pathBin.path,
                "HOME": home.path,
                "UV_INDEX_URL": "https://untrusted.example/simple",
                "UV_EXTRA_INDEX_URL": "https://extra.example/simple",
                "UV_FIND_LINKS": "/tmp/untrusted-wheels",
                "UV_CONSTRAINT": "/tmp/untrusted-constraints.txt",
                "PIP_INDEX_URL": "https://pip-untrusted.example/simple",
            ],
            applicationSupportDirectory: support,
            homeDirectory: home
        )
        try expectEqual(runtime.locateUVExecutable(), uvExecutable.standardizedFileURL)

        let command = try runtime.installCommand(force: false)
        try expectEqual(command.executableURL, uvExecutable.standardizedFileURL)
        try expectEqual(
            command.arguments,
            [
                "tool", "install",
                "--no-config",
                "--default-index", "https://pypi.org/simple",
                "tele-mess-core==0.3.0",
            ]
        )
        try expectEqual(
            command.environment["PATH"]?.split(separator: ":").first.map(String.init),
            runtime.uvBinDirectory.path
        )
        try expectNil(command.environment["UV_INDEX_URL"])
        try expectNil(command.environment["UV_EXTRA_INDEX_URL"])
        try expectNil(command.environment["UV_FIND_LINKS"])
        try expectNil(command.environment["UV_CONSTRAINT"])
        try expectNil(command.environment["PIP_INDEX_URL"])
    }

    private static func managedInstallationMarkerInvalidatesBeforeRepair() throws {
        let root = try makeTemporaryDirectory(named: "installation marker")
        defer { try? FileManager.default.removeItem(at: root) }
        var profile = CoreProfile.defaultLocal
        profile.localWorkspaceDirectory = root.appendingPathComponent("Workspace").path
        let runtime = try ManagedLocalCoreRuntime(
            profile: profile,
            environment: [:],
            applicationSupportDirectory: root.appendingPathComponent("Support", isDirectory: true),
            homeDirectory: root.appendingPathComponent("Home", isDirectory: true)
        )
        try runtime.prepareDirectories()
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: runtime.managedCoreExecutableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: runtime.managedCoreExecutableURL.path
        )
        try runtime.markInstalled()
        try expectEqual(runtime.isInstalled, true)

        try runtime.invalidateInstalledVersionMarker()

        try expectEqual(runtime.isInstalled, false)
        try expectEqual(FileManager.default.fileExists(atPath: runtime.installedVersionMarkerURL.path), false)
        try expectEqual(FileManager.default.isExecutableFile(atPath: runtime.managedCoreExecutableURL.path), true)
    }

    private static func managedBootstrapIsPrivateAndNonDestructive() throws {
        let root = try makeTemporaryDirectory(named: "bootstrap workspace")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("Core Workspace With Spaces", isDirectory: true)
        var profile = CoreProfile.defaultLocal
        profile.localWorkspaceDirectory = workspace.path
        let runtime = try ManagedLocalCoreRuntime(
            profile: profile,
            environment: [:],
            applicationSupportDirectory: root.appendingPathComponent("Support", isDirectory: true),
            homeDirectory: root.appendingPathComponent("Home", isDirectory: true)
        )
        let apiHash = #"api-hash-\"quoted\"-\\value"#
        let result = try runtime.bootstrapConfiguration(
            LocalCoreBootstrapConfiguration(
                accountID: "main account",
                apiID: 123_456,
                apiHash: apiHash,
                sessionName: "main_session",
                timezone: "Asia/Tokyo"
            )
        )

        let originalData = try Data(contentsOf: result.configurationFileURL)
        guard let originalText = String(data: originalData, encoding: .utf8),
              let encodedHash = String(data: try JSONEncoder().encode(apiHash), encoding: .utf8),
              let encodedToken = String(data: try JSONEncoder().encode(result.serverToken), encoding: .utf8) else {
            throw RuntimeTestError.failure("Could not inspect generated local Core configuration")
        }
        try expectEqual(originalText.contains("api_id: 123456"), true)
        try expectEqual(originalText.contains("api_hash: \(encodedHash)"), true)
        try expectEqual(originalText.contains("token: \(encodedToken)"), true)
        try expectEqual(originalText.contains("allow_unauthenticated_localhost: false"), true)
        try expectEqual(runtime.workspaceStatus().isReadyForLaunch, true)

        let attributes = try FileManager.default.attributesOfItem(atPath: result.configurationFileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        try expectEqual(permissions.map { $0 & 0o777 }, 0o600)
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            atPath: result.workspaceDirectory.path
        ).filter { $0.hasPrefix(".config.yml.") && $0.hasSuffix(".tmp") }
        try expectEqual(temporaryArtifacts, [])

        do {
            _ = try runtime.bootstrapConfiguration(
                LocalCoreBootstrapConfiguration(
                    accountID: "replacement",
                    apiID: 654_321,
                    apiHash: "replacement-secret"
                )
            )
            throw RuntimeTestError.failure("Expected an existing config to block bootstrap")
        } catch let error as LocalCoreRuntimeSupportError {
            try expectEqual(error, .configurationAlreadyExists(result.configurationFileURL))
        }
        try expectEqual(try Data(contentsOf: result.configurationFileURL), originalData)
        try expectEqual(originalText.contains("replacement-secret"), false)
    }

    @MainActor
    private static func managedBootstrapNormalizesBearerAuth() async throws {
        let root = try makeTemporaryDirectory(named: "bootstrap bearer")
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: StaticCredentialStore(token: "bootstrap-test-token")
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        profile.authMode = .apiToken
        profile.localWorkspaceDirectory = root.appendingPathComponent("Workspace", isDirectory: true).path
        try expectEqual(model.saveProfile(profile, token: nil), true)

        let created = model.bootstrapLocalCore(
            LocalCoreBootstrapConfiguration(
                accountID: "main",
                apiID: 123_456,
                apiHash: "fake-api-hash",
                sessionName: "main",
                timezone: "Asia/Tokyo"
            )
        )

        try expectEqual(created, true)
        try expectEqual(model.selectedProfile?.authMode, .bearer)
        try expectEqual(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Workspace/config.yml").path
            ),
            true
        )
    }

    @MainActor
    private static func managedBootstrapRequestsKeychainAuthorizationBeforeWriting() async throws {
        let root = try makeTemporaryDirectory(named: "bootstrap keychain authorization")
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let credentials = AuthorizationFailingCredentialStore()
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: credentials
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        let workspace = root.appendingPathComponent("Workspace", isDirectory: true)
        profile.localWorkspaceDirectory = workspace.path
        try expectEqual(model.saveProfile(profile, token: nil), true)

        let created = model.bootstrapLocalCore(
            LocalCoreBootstrapConfiguration(
                accountID: "main",
                apiID: 123_456,
                apiHash: "fake-api-hash"
            )
        )

        try expectEqual(created, false)
        try expectEqual(credentials.readAllowsAuthenticationUI, [true])
        try expectEqual(credentials.saveCount, 0)
        try expectEqual(model.localCoreKeychainAuthorizationRequired, true)
        try expectEqual(model.statusMessage, "Keychain authorization required")
        try expectEqual(
            FileManager.default.fileExists(atPath: workspace.appendingPathComponent("config.yml").path),
            false
        )
    }

    @MainActor
    private static func managedBootstrapRollsBackWhenKeychainSaveNeedsAuthorization() async throws {
        let root = try makeTemporaryDirectory(named: "bootstrap keychain save authorization")
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let credentials = SaveAuthorizationFailingCredentialStore()
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: credentials
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        let workspace = root.appendingPathComponent("Workspace", isDirectory: true)
        profile.localWorkspaceDirectory = workspace.path
        try expectEqual(model.saveProfile(profile, token: nil), true)

        let created = model.bootstrapLocalCore(
            LocalCoreBootstrapConfiguration(
                accountID: "main",
                apiID: 123_456,
                apiHash: "fake-api-hash"
            )
        )

        try expectEqual(created, false)
        try expectEqual(credentials.readAllowsAuthenticationUI, [true])
        try expectEqual(credentials.saveCount, 1)
        try expectEqual(model.localCoreKeychainAuthorizationRequired, true)
        try expectEqual(model.statusMessage, "Keychain authorization required")
        try expectEqual(model.lastError?.contains("Repair Keychain Access & Retry"), true)
        try expectEqual(
            FileManager.default.fileExists(atPath: workspace.appendingPathComponent("config.yml").path),
            false
        )
    }

    @MainActor
    private static func managedBootstrapRepairsKeychainAccessOnExplicitRetry() async throws {
        let root = try makeTemporaryDirectory(named: "bootstrap keychain repair")
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let credentials = RepairRecordingCredentialStore()
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: credentials
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        let workspace = root.appendingPathComponent("Workspace", isDirectory: true)
        profile.localWorkspaceDirectory = workspace.path
        try expectEqual(model.saveProfile(profile, token: nil), true)
        let configuration = LocalCoreBootstrapConfiguration(
            accountID: "main",
            apiID: 123_456,
            apiHash: "fake-api-hash"
        )

        try expectEqual(model.bootstrapLocalCore(configuration), false)
        try expectEqual(model.localCoreKeychainAuthorizationRequired, true)
        try expectEqual(
            model.bootstrapLocalCore(configuration, repairingKeychainAccess: true),
            true
        )
        try expectEqual(credentials.forceResetRequests, [false, true])
        try expectEqual(credentials.saveCount, 1)
        try expectEqual(
            FileManager.default.fileExists(atPath: workspace.appendingPathComponent("config.yml").path),
            true
        )
    }

    @MainActor
    private static func automaticRefreshWaitsForManagedLocalSetup() async throws {
        let root = try makeTemporaryDirectory(named: "managed onboarding")
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: FailIfCalledTransport()
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        profile.localCoreVersion = "0.0.0+onboarding.\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        profile.localWorkspaceDirectory = root.appendingPathComponent("Workspace", isDirectory: true).path
        try expectEqual(model.saveProfile(profile, token: nil), true)

        await model.refreshCurrentSectionWhenIdle(allowKeychainUI: false)

        try expectNil(model.dashboard.coreState)
        try expectNil(model.lastError)
        try expectEqual(model.validationStatus.title, "Unverified")
        try expectEqual(model.statusMessage, "Install local Core to continue")
    }

    @MainActor
    private static func customLocalCoreFollowsAwaitedLifecycle() async throws {
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let controller = LocalCoreProcessController(logger: logger)
        var profile = CoreProfile.defaultLocal
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "trap 'printf term-observed; exit 0' TERM; printf started; while true; do sleep 0.05; done"
        defer { controller.shutdown() }

        let started: Bool = await controller.start(profile: profile)
        try expectEqual(started, true)
        try expectEqual(controller.phase, .starting)
        try expectEqual(controller.isRunning, true)
        try expectEqual(controller.runningProfileID, profile.id)
        try expectEqual(controller.markReady(profileID: profile.id), true)
        try expectEqual(controller.phase, .running)

        let stopped: Bool = await controller.stop()
        try expectEqual(stopped, true)
        try expectEqual(controller.phase, .idle)
        try expectEqual(controller.isRunning, false)
        try expectNil(controller.runningProfileID)
        try expectEqual(controller.lastOutput.contains("started"), true)
        try expectEqual(controller.lastOutput.contains("term-observed"), true)
    }

    @MainActor
    private static func customLocalCoreReportsEarlyExit() async throws {
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let controller = LocalCoreProcessController(logger: logger)
        var profile = CoreProfile.defaultLocal
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "printf quick-failure; exit 23"
        defer { controller.shutdown() }

        let started: Bool = await controller.start(profile: profile)
        try expectEqual(started, false)
        try expectEqual(controller.phase, .failed)
        try expectEqual(controller.isRunning, false)
        try expectNil(controller.runningProfileID)
        try expectEqual(controller.lastError?.contains("status 23"), true)
        try expectEqual(controller.lastOutput.contains("quick-failure"), true)
    }

    @MainActor
    private static func earlyExitCleanupReapsOwnedProcessGroup() async throws {
        let root = try makeTemporaryDirectory(named: "owned-process-group")
        defer { try? FileManager.default.removeItem(at: root) }
        let childPIDFile = root.appendingPathComponent("child.pid", isDirectory: false)
        let quotedPIDFile = "'" + childPIDFile.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let controller = LocalCoreProcessController(logger: logger)
        var profile = CoreProfile.defaultLocal
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "/bin/sleep 100 & printf '%s' $! > \(quotedPIDFile); exit 23"
        defer { controller.shutdown() }

        let started: Bool = await controller.start(profile: profile)
        try expectEqual(started, false)
        try expectEqual(controller.phase, .failed)
        try expectEqual(controller.lastError?.contains("status 23"), true)

        guard let rawPID = try? String(contentsOf: childPIDFile, encoding: .utf8),
              let childPID = pid_t(rawPID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RuntimeTestError.failure("Could not read the early-exit descendant PID")
        }
        for _ in 0..<100 where processExists(childPID) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        try expectEqual(processExists(childPID), false)
        try expectNil(controller.activeOperationID)
        try expectNil(controller.activeProfileID)
    }

    @MainActor
    private static func synchronousShutdownCrossesProcessGroupBarrier() async throws {
        let root = try makeTemporaryDirectory(named: "shutdown-process-group")
        defer { try? FileManager.default.removeItem(at: root) }
        let childPIDFile = root.appendingPathComponent("child.pid", isDirectory: false)
        let quotedPIDFile = "'" + childPIDFile.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let controller = LocalCoreProcessController(logger: logger)
        var profile = CoreProfile.defaultLocal
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "/bin/sleep 100 & printf '%s' $! > \(quotedPIDFile); wait"

        try expectEqual(await controller.start(profile: profile), true)
        guard let rawPID = try? String(contentsOf: childPIDFile, encoding: .utf8),
              let childPID = pid_t(rawPID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            controller.shutdown()
            throw RuntimeTestError.failure("Could not read the shutdown descendant PID")
        }
        try expectEqual(processExists(childPID), true)

        controller.shutdown()

        try expectEqual(processExists(childPID), false)
        try expectEqual(controller.phase, .idle)
        try expectEqual(controller.isRunning, false)
        try expectNil(controller.activeOperationID)
        try expectNil(controller.activeProfileID)
    }

    @MainActor
    private static func staleOperationOwnershipCannotStopNewerCore() async throws {
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let controller = LocalCoreProcessController(logger: logger)
        defer { controller.shutdown() }

        var firstProfile = CoreProfile.defaultLocal
        firstProfile.localRuntimeMode = .customCommand
        firstProfile.localCommand = "while true; do sleep 1; done"
        try expectEqual(await controller.start(profile: firstProfile), true)
        guard let firstOperationID = controller.activeOperationID else {
            throw RuntimeTestError.failure("Expected the first operation owner")
        }
        try expectEqual(controller.activeProfileID, firstProfile.id)
        try expectEqual(await controller.stop(ifOwnedByOperationID: firstOperationID), true)

        var secondProfile = CoreProfile.defaultLocal
        secondProfile.localRuntimeMode = .customCommand
        secondProfile.localCommand = "while true; do sleep 1; done"
        try expectEqual(await controller.start(profile: secondProfile), true)
        guard let secondOperationID = controller.activeOperationID else {
            throw RuntimeTestError.failure("Expected the second operation owner")
        }
        try expectEqual(secondOperationID == firstOperationID, false)
        try expectEqual(controller.activeProfileID, secondProfile.id)

        try expectEqual(await controller.stop(ifOwnedByOperationID: firstOperationID), true)
        try expectEqual(controller.isRunning, true)
        try expectEqual(controller.activeOperationID, secondOperationID)
        try expectEqual(controller.activeProfileID, secondProfile.id)
        try expectEqual(await controller.stop(ifOwnedByOperationID: secondOperationID), true)
        try expectEqual(controller.isRunning, false)
    }

    @MainActor
    private static func overlappingSameProfileWaitersPreserveReplacementOwner() async throws {
        let root = try makeTemporaryDirectory(named: "same-profile-waiters")
        defer { try? FileManager.default.removeItem(at: root) }
        let exitSentinel = root.appendingPathComponent("allow-old-exit", isDirectory: false)
        let quotedSentinel = "'" + exitSentinel.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let controller = LocalCoreProcessController()
        defer { controller.shutdown() }

        var oldProfile = CoreProfile.defaultLocal
        oldProfile.localRuntimeMode = .customCommand
        oldProfile.localCommand = "trap '' TERM; while [ ! -f \(quotedSentinel) ]; do sleep 0.01; done"
        try expectEqual(await controller.start(profile: oldProfile), true)

        let staleStop = Task { @MainActor in await controller.stop() }
        for _ in 0..<100 {
            if controller.phase == .stopping { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        try expectEqual(controller.phase, .stopping)
        try await Task.sleep(for: .milliseconds(50))

        var replacementProfile = oldProfile
        replacementProfile.localCommand = "while true; do sleep 0.1; done"
        let replacementStart = Task { @MainActor in
            await controller.start(profile: replacementProfile)
        }
        try await Task.sleep(for: .milliseconds(170))
        try Data().write(to: exitSentinel)

        let replacementStarted = await replacementStart.value
        _ = await staleStop.value

        try expectEqual(replacementStarted, true)
        try expectEqual(controller.isRunning, true)
        try expectEqual(controller.runningProfileID, replacementProfile.id)
        try expectEqual(controller.activeProfileID, replacementProfile.id)
        try expectEqual(controller.markReady(profileID: replacementProfile.id), true)
        try expectEqual(await controller.stop(), true)
    }

    @MainActor
    private static func appModelMarksCustomLocalCoreReadyFromAuthenticatedAPI() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let token = "local-readiness-token"
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let localRunner = LocalCoreProcessController(logger: logger)
        defer { localRunner.shutdown() }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: StaticCredentialStore(token: token),
            localRunner: localRunner,
            transport: LocalCoreReadinessTransport(expectedToken: token),
            runtimeLogger: logger,
            apiLogger: logger
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "printf app-model-started; while true; do sleep 0.1; done"
        try expectEqual(model.saveProfile(profile, token: nil), true)

        let started = await model.startLocalCore()
        try expectEqual(started, true)
        try expectEqual(localRunner.phase, .running)
        try expectEqual(localRunner.runningProfileID, profile.id)
        try expectEqual(model.validationStatus.title, "Verified")
        try expectEqual(model.dashboard.apiManifest?.contractVersion, "2026-07-22.1")
        try expectNil(model.lastError)

        await model.stopLocalCore()
        try expectEqual(localRunner.phase, .idle)
        try expectEqual(localRunner.isRunning, false)
        try expectNil(model.dashboard.coreState)
        try expectEqual(model.validationStatus.title, "Unverified")
    }

    @MainActor
    private static func savingRunningLocalProfileRequiresStop() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let localRunner = LocalCoreProcessController()
        defer { localRunner.shutdown() }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            localRunner: localRunner,
            transport: FailIfCalledTransport()
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "while true; do sleep 0.1; done"
        try expectEqual(model.saveProfile(profile, token: nil), true)
        try expectEqual(await localRunner.start(profile: profile), true)
        try expectEqual(localRunner.markReady(profileID: profile.id), true)

        var editedProfile = profile
        editedProfile.name = "Edited while running"
        try expectEqual(model.saveProfile(editedProfile, token: nil), false)
        try expectEqual(model.selectedProfile?.name, profile.name)
        try expectEqual(localRunner.isRunning, true)
        try expectEqual(model.lastError, "Stop this local Core before changing its profile settings.")

        try expectEqual(await localRunner.stop(), true)
    }

    @MainActor
    private static func supersededAppModelStartCannotStopNewerCore() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let token = "superseded-start-token"
        let transport = SupersedingLocalCoreTransport(expectedToken: token)
        let localRunner = LocalCoreProcessController()
        defer { localRunner.shutdown() }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: StaticCredentialStore(token: token),
            localRunner: localRunner,
            transport: transport
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "while true; do sleep 0.1; done"
        try expectEqual(model.saveProfile(profile, token: nil), true)

        let firstStart = Task { @MainActor in await model.startLocalCore() }
        for _ in 0..<200 {
            if await transport.healthRequestCount() > 0 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        try expectEqual(await transport.healthRequestCount() > 0, true)

        let secondStarted = await model.startLocalCore()
        let firstStarted = await firstStart.value

        try expectEqual(firstStarted, false)
        try expectEqual(secondStarted, true)
        try expectEqual(localRunner.phase, .running)
        try expectEqual(localRunner.runningProfileID, profile.id)
        try expectEqual(localRunner.isRunning, true)
        await model.stopLocalCore()
    }

    @MainActor
    private static func stoppingDuringValidationCannotRestoreStaleState() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let token = "stale-validation-token"
        let transport = DelayedLocalCoreValidationTransport(expectedToken: token)
        let localRunner = LocalCoreProcessController()
        defer { localRunner.shutdown() }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: StaticCredentialStore(token: token),
            localRunner: localRunner,
            transport: transport
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "while true; do sleep 0.1; done"
        try expectEqual(model.saveProfile(profile, token: nil), true)

        let startTask = Task { @MainActor in await model.startLocalCore() }
        for _ in 0..<300 {
            if await transport.validationHasStarted() { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        try expectEqual(await transport.validationHasStarted(), true)

        await model.stopLocalCore()
        let started = await startTask.value

        try expectEqual(started, false)
        try expectEqual(localRunner.phase, .idle)
        try expectEqual(localRunner.isRunning, false)
        try expectEqual(model.validationStatus.title, "Unverified")
        try expectEqual(model.statusMessage, "Local Core stopped")
        try expectNil(model.lastError)
    }

    @MainActor
    private static func deliveryFallbackUsesFieldPresence() throws {
        var fallback = SummarySettings()
        fallback.deliveryEnabled = true
        fallback.deliveryAccountID = "main"
        fallback.deliveryOriginID = "-1001"
        fallback.deliveryTopicID = "42"

        let omitted = try decodeSchedule(deliveryJSON: nil)
        try expectEqual(omitted.deliveryWasProvided, false)
        let preserved = SummarySettings(schedule: omitted, preservingDeliveryFrom: fallback)
        try expectEqual(preserved.deliveryEnabled, true)
        try expectEqual(preserved.deliveryAccountID, "main")

        let explicitNull = try decodeSchedule(deliveryJSON: "null")
        try expectEqual(explicitNull.deliveryWasProvided, true)
        try expectNil(explicitNull.delivery)
        let cleared = SummarySettings(schedule: explicitNull, preservingDeliveryFrom: fallback)
        try expectEqual(cleared.deliveryEnabled, false)
        try expectEqual(cleared.deliveryAccountID, "")
        try expectEqual(cleared.deliveryOriginID, "")
        try expectEqual(cleared.deliveryTopicID, "")
    }

    private static func summaryTargetOptionsFollowDraft() throws {
        let accounts = try JSONDecoder.core.decode(
            [CoreAccount].self,
            from: Data(
                """
                [
                  {"source":"telegram","account_id":"a","display_name":"Primary"},
                  {"source":"telegram","account_id":"b","display_name":"Backup"}
                ]
                """.utf8
            )
        )
        let origins = try JSONDecoder.core.decode(
            [CoreOrigin].self,
            from: Data(
                """
                [
                  {"source":"telegram","account_id":"a","origin_id":100,"origin_type":"group","title":"Alpha","backup_policy":{"enabled":true,"capture_text":true,"capture_media_metadata":true,"download_media":false,"tags":"ops, daily"}},
                  {"source":"telegram","account_id":"a","origin_id":100,"topic_id":10,"origin_type":"topic","title":"Alpha / News"},
                  {"source":"telegram","account_id":"a","origin_id":100,"topic_id":11,"origin_type":"topic","title":"Alpha / Ops"},
                  {"source":"telegram","account_id":"b","origin_id":200,"origin_type":"channel","title":"Beta"}
                ]
                """.utf8
            )
        )
        var draft = SummarySettings()
        draft.accountID = "a"
        draft.originID = "100"
        draft.deliveryAccountID = "a"
        draft.deliveryOriginID = "100"

        let options = SummaryTargetOptions(accounts: accounts, origins: origins, draft: draft)
        try expectEqual(options.scopeAccountIDs, ["a", "b"])
        try expectEqual(options.scopeOrigins.map(\.value), ["100"])
        try expectEqual(options.scopeTopics.map(\.value), ["10", "11"])
        try expectEqual(options.deliveryOrigins.map(\.value), ["100"])
        try expectEqual(options.deliveryTopics.map(\.value), ["10", "11"])
        try expectEqual(options.scopeTags, ["daily", "ops"])
    }

    @MainActor
    private static func localCoreLoadsWithoutToken() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let profileStore = CoreProfileStore(defaults: defaults)
        let model = AppModel(
            profileStore: profileStore,
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: DashboardTransport()
        )

        await model.loadDashboard(allowKeychainUI: false)

        try expectEqual(model.dashboard.coreState?.databaseID, "db")
        try expectEqual(model.dashboard.recentMessages.count, 0)
        try expectNil(model.lastError)
    }

    @MainActor
    private static func remoteBackgroundLoadRequiresToken() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let profileStore = CoreProfileStore(defaults: defaults)
        let model = AppModel(
            profileStore: profileStore,
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: FailIfCalledTransport()
        )
        var remote = model.addRemoteProfile()
        remote.baseURLString = "http://core.example"
        try expectEqual(model.saveProfile(remote, token: nil), true)

        await model.loadDashboard(allowKeychainUI: false)

        try expectNil(model.dashboard.coreState)
        try expectEqual(model.lastError, CoreAPIError.missingToken.localizedDescription)
    }

    @MainActor
    private static func protectedLocalTokenDoesNotDegrade() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: InteractionBlockedCredentialStore(),
            transport: FailIfCalledTransport()
        )

        await model.loadDashboard(allowKeychainUI: false)

        try expectNil(model.dashboard.coreState)
        try expectEqual(
            model.lastError,
            KeychainError(status: errSecInteractionNotAllowed).localizedDescription
        )
    }

    private static func legacyTokenMigratesWithoutDeletion() throws {
        let profileID = UUID()
        let backend = MemoryKeychainItemBackend()
        let namespaces = MemoryCredentialNamespaceStore()
        let legacyService = "com.dreaifekks.TeleMessEnd.coreToken"
        backend.values[legacyService] = "legacy-token"
        let store = KeychainStore(backend: backend, namespaceStore: namespaces)

        let token = try store.readToken(profileID: profileID, allowAuthenticationUI: false)

        try expectEqual(token, "legacy-token")
        guard let managedService = namespaces.service(profileID: profileID) else {
            throw RuntimeTestError.failure("Expected a managed credential namespace")
        }
        try expectEqual(backend.values[managedService], "legacy-token")
        try expectEqual(backend.values[legacyService], "legacy-token")
    }

    private static func inaccessibleManagedTokenRotatesOnSave() throws {
        let profileID = UUID()
        let backend = MemoryKeychainItemBackend()
        let namespaces = MemoryCredentialNamespaceStore()
        let inaccessibleService = "managed-inaccessible"
        namespaces.selectService(inaccessibleService, profileID: profileID)
        backend.values[inaccessibleService] = "old-token"
        backend.upsertFailures[inaccessibleService] = KeychainError(status: errSecAuthFailed)
        let store = KeychainStore(backend: backend, namespaceStore: namespaces)

        try store.saveToken("replacement-token", profileID: profileID)

        guard let replacementService = namespaces.service(profileID: profileID) else {
            throw RuntimeTestError.failure("Expected a replacement credential namespace")
        }
        try expectEqual(replacementService == inaccessibleService, false)
        try expectEqual(backend.values[inaccessibleService], "old-token")
        try expectEqual(backend.values[replacementService], "replacement-token")
        try expectEqual(
            store.readToken(profileID: profileID, allowAuthenticationUI: false),
            "replacement-token"
        )
    }

    private static func keychainAuthorizationUnlocksBeforeReadingCredentials() throws {
        let profileID = UUID()
        let backend = MemoryKeychainItemBackend()
        let namespaces = MemoryCredentialNamespaceStore()
        let authorizer = RecordingDefaultKeychainAuthorizer()
        let store = KeychainStore(
            backend: backend,
            namespaceStore: namespaces,
            defaultKeychainAuthorizer: authorizer
        )

        try store.requestAuthorization(profileID: profileID, forceResetDefaultKeychain: true)

        try expectEqual(authorizer.forceResetRequests, [true])
        try expectEqual(backend.readAllowsAuthenticationUI, [true])
    }

    private static func managedClearMasksLegacyToken() throws {
        let profileID = UUID()
        let backend = MemoryKeychainItemBackend()
        let namespaces = MemoryCredentialNamespaceStore()
        let legacyService = "com.dreaifekks.TeleMessEnd.coreToken"
        backend.values[legacyService] = "legacy-token"
        let store = KeychainStore(backend: backend, namespaceStore: namespaces)

        try store.clearToken(profileID: profileID)

        try expectNil(store.readToken(profileID: profileID, allowAuthenticationUI: false))
        try expectEqual(backend.values[legacyService], "legacy-token")
        guard let managedService = namespaces.service(profileID: profileID) else {
            throw RuntimeTestError.failure("Expected a managed credential tombstone")
        }
        try expectEqual(backend.values[managedService], "")
    }

    private static func runtimeLogBufferIsBoundedAndClearable() throws {
        let buffer = AppRuntimeLogBuffer(maximumEntries: 2, maximumCharacters: 1_000)
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )

        logger.info("first")
        logger.warning("second")
        logger.error("third")

        try expectEqual(buffer.snapshot().entries.map(\.event.message), ["second", "third"])
        try expectEqual(buffer.clear().entries.isEmpty, true)
        try expectEqual(buffer.snapshot().entries.isEmpty, true)
    }

    @MainActor
    private static func runtimeLogStoreFollowsConcurrentWriters() async throws {
        let buffer = AppRuntimeLogBuffer(maximumEntries: 200, maximumCharacters: 20_000)
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let store = AppRuntimeLogStore(buffer: buffer)
        store.startMonitoring()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    logger.info("concurrent entry \(index)")
                }
            }
        }

        for _ in 0..<100 where store.entries.count < 100 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        try expectEqual(store.entries.count, 100)
        try expectEqual(store.entries.map(\.id), (1...100).map(UInt64.init))
    }

    @MainActor
    private static func coreOutputClearKeepsLaterProcessOutput() async throws {
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let runner = LocalCoreProcessController(logger: logger)
        var profile = CoreProfile.defaultLocal
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "printf before-clear; sleep 0.5; printf after-clear; while true; do sleep 1; done"
        defer { runner.shutdown() }

        let started: Bool = await runner.start(profile: profile)
        try expectEqual(started, true)

        for _ in 0..<100 where !runner.lastOutput.contains("before-clear") {
            try? await Task.sleep(for: .milliseconds(5))
        }
        try expectEqual(runner.lastOutput.contains("before-clear"), true)
        runner.clearOutput()

        for _ in 0..<200 where runner.lastOutput != "after-clear" {
            try? await Task.sleep(for: .milliseconds(5))
        }
        try expectEqual(runner.lastOutput, "after-clear")
        let stopped: Bool = await runner.stop()
        try expectEqual(stopped, true)
    }

    private static func keychainRuntimeLogsOmitCredentialMaterial() throws {
        let profileID = UUID(uuidString: "11111111-2222-3333-4444-555566667777")!
        let token = "super-secret-token"
        let legacyService = "com.dreaifekks.TeleMessEnd.coreToken"
        let backend = MemoryKeychainItemBackend()
        backend.values[legacyService] = token
        let namespaces = MemoryCredentialNamespaceStore()
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let store = KeychainStore(backend: backend, namespaceStore: namespaces, logger: logger)

        try expectEqual(store.readToken(profileID: profileID, allowAuthenticationUI: false), token)

        let rendered = buffer.snapshot().entries.map(\.renderedLine).joined(separator: "\n")
        try expectEqual(rendered.contains(String(profileID.uuidString.suffix(8))), true)
        try expectEqual(rendered.contains(profileID.uuidString), false)
        try expectEqual(rendered.contains(token), false)
        try expectEqual(rendered.contains(legacyService), false)
    }

    @MainActor
    private static func appOperationFailuresEmitSafeRuntimeLogs() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "runtime",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: FailIfCalledTransport(),
            runtimeLogs: AppRuntimeLogStore(buffer: buffer),
            runtimeLogger: logger,
            apiLogger: logger
        )
        var remote = model.addRemoteProfile()
        remote.baseURLString = "http://core.example"
        try expectEqual(model.saveProfile(remote, token: nil), true)
        buffer.clear()

        await model.loadDashboard(allowKeychainUI: false)

        let rendered = buffer.snapshot().entries.map(\.renderedLine).joined(separator: "\n")
        try expectEqual(
            rendered.contains("Operation end action=Loading dashboard result=failure error=missing_token"),
            true
        )
        try expectEqual(rendered.contains(remote.id.uuidString), false)
    }

    private static func apiRuntimeLogsOmitAuthAndQueryValues() async throws {
        let token = "top-secret-api-token"
        let query = "private-search-phrase"
        let buffer = AppRuntimeLogBuffer()
        let logger = AppRuntimeLogger(
            subsystem: "com.dreaifekks.TeleMessEnd.tests",
            category: "api",
            sink: buffer,
            mirrorsToUnifiedLog: false
        )
        let client = CoreAPIClient(
            baseURL: URL(string: "http://core.example")!,
            tokenProvider: FixedTokenProvider(value: token),
            authMode: .bearer,
            transport: PrivateSearchTransport(expectedToken: token, expectedQuery: query),
            logger: logger
        )

        _ = try await client.searchMessages(query: query)

        let rendered = buffer.snapshot().entries.map(\.renderedLine).joined(separator: "\n")
        try expectEqual(rendered.contains("method=GET path=/sync/search status=200"), true)
        try expectEqual(rendered.contains(token), false)
        try expectEqual(rendered.contains(query), false)
        try expectEqual(rendered.localizedCaseInsensitiveContains("authorization"), false)
    }

    @MainActor
    private static func sameProfileSaveAdvancesSession() throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: FailIfCalledTransport()
        )
        let initialRevision = model.sessionRevision
        guard let profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected a selected profile")
        }

        try expectEqual(model.saveProfile(profile, token: nil), true)
        try expectEqual(model.sessionRevision, initialRevision + 1)
    }

    @MainActor
    private static func accountMutationSurvivesRefreshFailure() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: AccountMutationThenRefreshFailureTransport()
        )

        let succeeded = await model.createAccount(
            CreateAccountRequest(
                accountID: "created",
                displayName: nil,
                phone: nil,
                sessionName: nil,
                sessionDir: nil
            )
        )

        try expectEqual(succeeded, true)
        try expectEqual(model.accounts.map(\.accountID), ["created"])
        try expectNil(model.lastError)
        try expectEqual(model.statusMessage, "Account saved; refresh pending")
    }

    @MainActor
    private static func partialBatchMutationRemainsVisible() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: PartialArchiveTransport()
        )
        model.includeArchivedOrigins = true
        model.origins = try JSONDecoder.core.decode(
            [CoreOrigin].self,
            from: Data(
                """
                [
                  {"source":"telegram","account_id":"main","origin_id":100,"origin_type":"group","title":"First"},
                  {"source":"telegram","account_id":"main","origin_id":200,"origin_type":"group","title":"Second"}
                ]
                """.utf8
            )
        )

        let succeeded = await model.archiveOrigins(model.origins, archived: true)

        try expectEqual(succeeded, false)
        try expectEqual(model.origins.first { $0.originID == 100 }?.isArchived, true)
        try expectEqual(model.origins.first { $0.originID == 200 }?.isArchived, false)
        try expectEqual(model.lastError?.contains("1 of 2 items"), true)
    }

    @MainActor
    private static func staleProfileRequestIsDiscarded() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let profileStore = CoreProfileStore(defaults: defaults)
        let model = AppModel(
            profileStore: profileStore,
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: DelayedAccountsTransport()
        )

        let loadTask = Task { await model.loadAccounts(allowKeychainUI: false) }
        try await Task.sleep(for: .milliseconds(20))
        let newProfile = model.addRemoteProfile()
        await loadTask.value

        try expectEqual(model.selectedProfile?.id, newProfile.id)
        try expectEqual(model.accounts.count, 0)
        try expectNil(model.lastError)
    }

    @MainActor
    private static func newerSearchWins() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: ReorderedSearchTransport()
        )

        model.messageSearchQuery = "slow"
        let slowSearch = Task { await model.searchMessages() }
        try await Task.sleep(for: .milliseconds(10))
        model.messageSearchQuery = "fast"
        let fastSearch = Task { await model.searchMessages() }
        await fastSearch.value
        await slowSearch.value

        try expectEqual(model.messages.first?.text, "fast")
        try expectNil(model.lastError)
    }

    @MainActor
    private static func manifestBootstrapsBeforeFeatureLoad() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: CapabilityBootstrapTransport()
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "test-core"
        try expectEqual(model.saveProfile(profile, token: nil), true)
        model.selectedSection = .summaries

        await model.refreshCurrentSectionWhenIdle(allowKeychainUI: false)

        try expectEqual(model.selectedSection, .dashboard)
        try expectEqual(model.availableSections, [.dashboard, .accounts])
        try expectEqual(model.dashboard.coreState?.databaseID, "db")
    }

    @MainActor
    private static func messagePointsFollowManifestAndSession() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: MessagePointRuntimeTransport()
        )
        guard var profile = model.selectedProfile else {
            throw RuntimeTestError.failure("Expected the default local profile")
        }
        profile.localRuntimeMode = .customCommand
        profile.localCommand = "test-core"
        try expectEqual(model.saveProfile(profile, token: nil), true)
        model.selectedSection = .messagePoints
        model.messagePointSearchQuery = "needle"
        model.messagePointDateFilter = "2026-07-11"
        model.messagePointTagsFilter = "ops, ai"
        model.messagePointAccountFilter = "main"
        model.messagePointOriginIDFilter = "-1001"
        model.messagePointImportanceMin = 3
        model.messagePointImportanceMax = 5
        model.messagePointOriginImportanceFilter = .important

        await model.refreshCurrentSectionWhenIdle(allowKeychainUI: false)

        try expectEqual(model.selectedSection, .messagePoints)
        try expectEqual(model.availableSections, [.dashboard, .messagePoints])
        try expectEqual(model.dailyMessagePoints.map(\.pointID), ["point-1"])
        try expectEqual(model.dailyMessagePoints.first?.content, "List content")
        try expectNil(model.lastError)

        guard let point = model.dailyMessagePoints.first else {
            throw RuntimeTestError.failure("Expected a loaded message point")
        }
        try expectEqual(await model.loadDailyMessagePoint(point), true)
        try expectEqual(model.dailyMessagePoints.first?.content, "Detailed content")

        _ = model.addRemoteProfile()
        try expectEqual(model.dailyMessagePoints.count, 0)
        try expectEqual(model.messagePointSearchQuery, "")
        try expectEqual(model.messagePointImportanceMin, 1)
        try expectEqual(model.messagePointImportanceMax, 5)
        try expectEqual(model.messagePointOriginImportanceFilter, .any)
    }

    @MainActor
    private static func busyValidationDoesNotFail() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            profileStore: CoreProfileStore(defaults: defaults),
            summarySettingsStore: SummarySettingsStore(defaults: defaults),
            keychain: EmptyCredentialStore(),
            transport: DelayedAccountsTransport()
        )

        let loadTask = Task { await model.loadAccounts(allowKeychainUI: false) }
        try await Task.sleep(for: .milliseconds(20))
        let validationTask = Task { await model.validateActiveProfile() }
        try await Task.sleep(for: .milliseconds(20))
        try expectEqual(model.validationStatus.title, "Validating")
        validationTask.cancel()
        await validationTask.value
        try expectEqual(model.validationStatus.title, "Unverified")
        await loadTask.value
    }

    @MainActor
    private static func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }

    private static func decodeSchedule(deliveryJSON: String?) throws -> DailyPackageSchedule {
        let deliveryMember = deliveryJSON.map { ", \"delivery\": \($0)" } ?? ""
        let json =
            """
            {
              "enabled": true,
              "time_of_day": "08:00",
              "timezone": "Asia/Tokyo",
              "scope": {},
              "system_manager": "systemd-user",
              "installed": false
              \(deliveryMember)
            }
            """
        return try JSONDecoder.core.decode(DailyPackageSchedule.self, from: Data(json.utf8))
    }
}

private let defaultsSuiteName = "TeleMessEndTests.RuntimeSession"

private func makeTemporaryDirectory(named name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TeleMessEndTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func processExists(_ processID: pid_t) -> Bool {
    guard processID > 1 else { return false }
    if Darwin.kill(processID, 0) == 0 {
        return true
    }
    return errno == EPERM
}

private struct EmptyCredentialStore: CredentialStore {
    func readToken(profileID: UUID, allowAuthenticationUI: Bool) throws -> String? { nil }
    func saveToken(_ token: String, profileID: UUID) throws {}
    func clearToken(profileID: UUID) throws {}
    func deleteToken(profileID: UUID) throws {}
}

private struct StaticCredentialStore: CredentialStore {
    var token: String

    func readToken(profileID: UUID, allowAuthenticationUI: Bool) throws -> String? { token }
    func saveToken(_ token: String, profileID: UUID) throws {}
    func clearToken(profileID: UUID) throws {}
    func deleteToken(profileID: UUID) throws {}
}

private struct InteractionBlockedCredentialStore: CredentialStore {
    func readToken(profileID: UUID, allowAuthenticationUI: Bool) throws -> String? {
        throw KeychainError(status: errSecInteractionNotAllowed)
    }

    func saveToken(_ token: String, profileID: UUID) throws {}
    func clearToken(profileID: UUID) throws {}
    func deleteToken(profileID: UUID) throws {}
}

private final class AuthorizationFailingCredentialStore: CredentialStore, @unchecked Sendable {
    private(set) var readAllowsAuthenticationUI: [Bool] = []
    private(set) var saveCount = 0

    func readToken(profileID: UUID, allowAuthenticationUI: Bool) throws -> String? {
        readAllowsAuthenticationUI.append(allowAuthenticationUI)
        throw KeychainError(status: errSecAuthFailed)
    }

    func saveToken(_ token: String, profileID: UUID) throws {
        saveCount += 1
    }

    func clearToken(profileID: UUID) throws {}
    func deleteToken(profileID: UUID) throws {}
}

private final class SaveAuthorizationFailingCredentialStore: CredentialStore, @unchecked Sendable {
    private(set) var readAllowsAuthenticationUI: [Bool] = []
    private(set) var saveCount = 0

    func readToken(profileID: UUID, allowAuthenticationUI: Bool) throws -> String? {
        readAllowsAuthenticationUI.append(allowAuthenticationUI)
        return nil
    }

    func saveToken(_ token: String, profileID: UUID) throws {
        saveCount += 1
        throw KeychainError(status: errSecAuthFailed)
    }

    func clearToken(profileID: UUID) throws {}
    func deleteToken(profileID: UUID) throws {}
}

private final class RepairRecordingCredentialStore: CredentialStore, @unchecked Sendable {
    private(set) var forceResetRequests: [Bool] = []
    private(set) var saveCount = 0

    func readToken(profileID: UUID, allowAuthenticationUI: Bool) throws -> String? { nil }

    func requestAuthorization(profileID: UUID, forceResetDefaultKeychain: Bool) throws {
        forceResetRequests.append(forceResetDefaultKeychain)
        if !forceResetDefaultKeychain {
            throw KeychainError(status: errSecAuthFailed)
        }
    }

    func saveToken(_ token: String, profileID: UUID) throws {
        saveCount += 1
    }

    func clearToken(profileID: UUID) throws {}
    func deleteToken(profileID: UUID) throws {}
}

private final class MemoryKeychainItemBackend: KeychainItemBackend, @unchecked Sendable {
    var values: [String: String] = [:]
    var readFailures: [String: KeychainError] = [:]
    var upsertFailures: [String: KeychainError] = [:]
    var deleteFailures: [String: KeychainError] = [:]
    private(set) var readAllowsAuthenticationUI: [Bool] = []

    func read(service: String, profileID: UUID, allowAuthenticationUI: Bool) throws -> String? {
        readAllowsAuthenticationUI.append(allowAuthenticationUI)
        if let failure = readFailures[service] {
            throw failure
        }
        return values[service]
    }

    func upsert(_ value: String, service: String, profileID: UUID) throws {
        if let failure = upsertFailures[service] {
            throw failure
        }
        values[service] = value
    }

    func delete(service: String, profileID: UUID) throws {
        if let failure = deleteFailures[service] {
            throw failure
        }
        values.removeValue(forKey: service)
    }
}

private final class RecordingDefaultKeychainAuthorizer: DefaultKeychainAuthorizer, @unchecked Sendable {
    private(set) var forceResetRequests: [Bool] = []

    func requestUnlock(forceReset: Bool) throws {
        forceResetRequests.append(forceReset)
    }
}

private final class MemoryCredentialNamespaceStore: CredentialNamespaceStore, @unchecked Sendable {
    private var services: [UUID: String] = [:]

    func service(profileID: UUID) -> String? {
        services[profileID]
    }

    func selectService(_ service: String?, profileID: UUID) {
        services[profileID] = service
    }
}

private struct DashboardTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.value(forHTTPHeaderField: "Authorization") == nil,
              request.value(forHTTPHeaderField: "X-Api-Token") == nil else {
            throw RuntimeTestError.failure("Unexpected authentication header")
        }

        let json: String
        switch request.url?.path {
        case "/sync/state":
            json = #"{"database_id":"db","schema_version":1,"last_event_seq":0,"message_count":0}"#
        case "/manage/capabilities":
            json = #"{"mode":"single_user","management":[]}"#
        case "/sync/messages":
            json = #"{"items":[]}"#
        case "/manage/operation-events":
            json = #"{"items":[]}"#
        default:
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        return try response(for: request, json: json)
    }
}

private struct FailIfCalledTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw RuntimeTestError.failure("Transport should not be called without a remote profile token")
    }
}

private struct LocalCoreReadinessTransport: CoreHTTPTransport {
    var expectedToken: String

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expectedToken)" else {
            throw RuntimeTestError.failure("Expected the local readiness token")
        }

        let json: String
        switch request.url?.path {
        case "/healthz", "/sync/state":
            json = #"{"database_id":"local-db","schema_version":2,"last_event_seq":0,"message_count":0,"ok":true}"#
        case "/manage/api-manifest":
            json = #"{"name":"tele-mess-core","contract_version":"2026-07-22.1","contract_hash":"local-test","endpoints":[]}"#
        case "/manage/capabilities":
            json = #"{"mode":"single_user","management":[]}"#
        case "/sync/messages", "/manage/operation-events":
            json = #"{"items":[]}"#
        default:
            throw RuntimeTestError.failure("Unexpected local readiness path \(request.url?.path ?? "")")
        }
        return try response(for: request, json: json)
    }
}

private actor SupersedingLocalCoreTransport: CoreHTTPTransport {
    let expectedToken: String
    private var healthRequests = 0

    init(expectedToken: String) {
        self.expectedToken = expectedToken
    }

    func healthRequestCount() -> Int {
        healthRequests
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expectedToken)" else {
            throw RuntimeTestError.failure("Expected the superseded-start token")
        }
        if request.url?.path == "/healthz" {
            healthRequests += 1
            if healthRequests == 1 {
                try await Task.sleep(for: .milliseconds(800))
            }
        }
        return try localCoreRuntimeResponse(for: request)
    }
}

private actor DelayedLocalCoreValidationTransport: CoreHTTPTransport {
    let expectedToken: String
    private var validationStarted = false

    init(expectedToken: String) {
        self.expectedToken = expectedToken
    }

    func validationHasStarted() -> Bool {
        validationStarted
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expectedToken)" else {
            throw RuntimeTestError.failure("Expected the stale-validation token")
        }
        if request.url?.path == "/sync/state" {
            validationStarted = true
            try await Task.sleep(for: .milliseconds(800))
        }
        return try localCoreRuntimeResponse(for: request)
    }
}

private func localCoreRuntimeResponse(
    for request: URLRequest
) throws -> (Data, HTTPURLResponse) {
    let json: String
    switch request.url?.path {
    case "/healthz", "/sync/state":
        json = #"{"database_id":"local-db","schema_version":2,"last_event_seq":0,"message_count":0,"ok":true}"#
    case "/manage/api-manifest":
        json = #"{"name":"tele-mess-core","contract_version":"2026-07-22.1","contract_hash":"local-test","endpoints":[]}"#
    case "/manage/capabilities":
        json = #"{"mode":"single_user","management":[]}"#
    case "/sync/messages", "/manage/operation-events":
        json = #"{"items":[]}"#
    default:
        throw RuntimeTestError.failure("Unexpected local runtime path \(request.url?.path ?? "")")
    }
    return try response(for: request, json: json)
}

private struct PrivateSearchTransport: CoreHTTPTransport {
    var expectedToken: String
    var expectedQuery: String

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expectedToken)" else {
            throw RuntimeTestError.failure("Expected bearer authentication header")
        }
        guard request.url?.path == "/sync/search",
              queryValues(request)["q"] == [expectedQuery] else {
            throw RuntimeTestError.failure("Expected private search query")
        }
        return try response(for: request, json: #"{"items":[]}"#)
    }
}

private struct AccountMutationThenRefreshFailureTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.path == "/manage/accounts" else {
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        if request.httpMethod == "POST" {
            return try response(
                for: request,
                json: #"{"item":{"source":"telegram","account_id":"created","display_name":"Created"}}"#
            )
        }
        throw RuntimeTestError.failure("Synthetic account refresh failure")
    }
}

private actor PartialArchiveTransport: CoreHTTPTransport {
    private var archiveRequests = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.path == "/manage/origins" || request.url?.path == "/manage/origins/archive" else {
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        if request.url?.path == "/manage/origins/archive" {
            archiveRequests += 1
            if archiveRequests == 1 {
                return try response(
                    for: request,
                    json: #"{"item":{"source":"telegram","account_id":"main","origin_id":100,"topic_id":0,"archived":true,"changed_rows":1}}"#
                )
            }
            throw RuntimeTestError.failure("Synthetic second archive failure")
        }
        throw RuntimeTestError.failure("Synthetic partial refresh failure")
    }
}

private actor DelayedAccountsTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(100))
        guard request.url?.path == "/manage/accounts" else {
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        return try response(
            for: request,
            json: #"{"items":[{"source":"telegram","account_id":"old","display_name":"Old Core"}]}"#
        )
    }
}

private actor ReorderedSearchTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.path == "/sync/search",
              let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false),
              let query = components.queryItems?.first(where: { $0.name == "q" })?.value else {
            throw RuntimeTestError.failure("Unexpected search request")
        }
        try await Task.sleep(for: query == "slow" ? .milliseconds(100) : .milliseconds(10))
        if query == "slow" {
            throw RuntimeTestError.failure("Synthetic stale search failure")
        }
        return try response(
            for: request,
            json:
                """
                {"items":[{"source":"telegram","account_id":"main","chat_id":-1001,"message_id":2,"text":"\(query)","has_media":false}]}
                """
        )
    }
}

private struct CapabilityBootstrapTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let json: String
        switch request.url?.path {
        case "/manage/api-manifest":
            json = #"{"contract_version":"test","contract_hash":"hash","endpoints":[{"path":"/manage/accounts"}]}"#
        case "/manage/capabilities":
            json = #"{"mode":"single_user","management":["accounts"]}"#
        case "/sync/state":
            json = #"{"database_id":"db","schema_version":1,"last_event_seq":0,"message_count":0}"#
        case "/sync/messages", "/manage/operation-events":
            json = #"{"items":[]}"#
        default:
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        return try response(for: request, json: json)
    }
}

private actor MessagePointRuntimeTransport: CoreHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let json: String
        switch request.url?.path {
        case "/manage/api-manifest":
            json = #"{"contract_version":"test","contract_hash":"hash","endpoints":[{"path":"/manage/daily-message-points"}]}"#
        case "/manage/capabilities":
            json = #"{"mode":"single_user","management":["daily_message_points"]}"#
        case "/manage/daily-message-points":
            let values = queryValues(request)
            try expectEqual(values["q"], ["needle"])
            try expectEqual(values["date"], ["2026-07-11"])
            try expectEqual(values["tag"], ["ops", "ai"])
            try expectEqual(values["account_id"], ["main"])
            try expectEqual(values["origin_id"], ["-1001"])
            try expectEqual(values["importance_min"], ["3"])
            try expectEqual(values["importance_max"], ["5"])
            try expectEqual(values["origin_important"], ["true"])
            try expectEqual(values["include_incomplete"], ["false"])
            try expectEqual(values["limit"], ["1000"])
            json = #"{"items":[{"point_id":"point-1","run_id":"run-1","package_run_id":"package-1","date":"2026-07-11","timezone":"Asia/Tokyo","source":"telegram","account_id":"main","origin_id":-1001,"topic_id":0,"origin_title":"Ops","message_id":42,"occurred_at":"2026-07-11T09:00:00+09:00","tags":["ops","ai"],"content":"List content","telegram_deeplink":"tg://privatepost?channel=1&post=42","permalink":"https://t.me/c/1/42","importance_score":4,"importance_reason":"Operational change","origin_important":true,"source_refs":["telegram:main:-1001:42"]}]}"#
        case "/manage/daily-message-points/item":
            try expectEqual(queryValues(request)["point_id"], ["point-1"])
            json = #"{"item":{"point_id":"point-1","run_id":"run-1","package_run_id":"package-1","date":"2026-07-11","timezone":"Asia/Tokyo","source":"telegram","account_id":"main","origin_id":-1001,"topic_id":0,"origin_title":"Ops","message_id":42,"occurred_at":"2026-07-11T09:00:00+09:00","tags":["ops","ai"],"content":"Detailed content","telegram_deeplink":"tg://privatepost?channel=1&post=42","permalink":"https://t.me/c/1/42","importance_score":4,"importance_reason":"Operational change","origin_important":true,"source_refs":[{"message_id":42}]}}"#
        default:
            throw RuntimeTestError.failure("Unexpected path \(request.url?.path ?? "")")
        }
        return try response(for: request, json: json)
    }
}

private func queryValues(_ request: URLRequest) -> [String: [String]] {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return [:]
    }
    return Dictionary(grouping: components.queryItems ?? [], by: \.name)
        .mapValues { items in items.compactMap(\.value) }
}

private func response(for request: URLRequest, json: String) throws -> (Data, HTTPURLResponse) {
    guard let url = request.url,
          let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
        throw RuntimeTestError.failure("Could not build HTTP response")
    }
    return (Data(json.utf8), response)
}

private struct RuntimeTestRunner {
    private var failures = 0

    mutating func run(_ name: String, operation: () async throws -> Void) async {
        do {
            try await operation()
            print("PASS \(name)")
        } catch {
            failures += 1
            print("FAIL \(name): \(error)")
        }
    }

    func finish() -> Never {
        if failures == 0 {
            print("Runtime state tests passed")
            exit(0)
        }
        print("Runtime state tests failed: \(failures)")
        exit(1)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    guard actual == expected else {
        throw RuntimeTestError.failure("Expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

private func expectNil<T>(_ value: T?) throws {
    guard value == nil else {
        throw RuntimeTestError.failure("Expected nil, got \(String(describing: value))")
    }
}

private enum RuntimeTestError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case .failure(let message):
            message
        }
    }
}
