import SwiftUI

struct LocalCoreSettingsSection: View {
    @Bindable var model: AppModel
    @Binding var draft: CoreProfile
    var saveDraft: () -> Bool

    @State private var accountID = "main"
    @State private var apiID = ""
    @State private var apiHash = ""
    @State private var sessionName = "main"
    @State private var timezone = TimeZone.current.identifier
    @State private var setupError: String?
    @State private var showsFirstRunSetup = true
    @State private var showsManagedSetupSteps = true
    @State private var showsAdvancedRuntimeSettings = false

    var body: some View {
        Section("Local Runtime") {
            Text("Run tele-mess-core on this Mac. Managed PyPI mode installs a private copy for TeleMessEnd and guides you through the first connection.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Runtime", selection: $draft.localRuntimeMode) {
                ForEach(LocalCoreRuntimeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(runtimeIsLocked)

            switch draft.localRuntimeMode {
            case .managedPyPI:
                managedRuntimeSettings
            case .customCommand:
                customRuntimeSettings
            }

            if let error = model.localRunner.lastError,
               model.localRunner.statusProfileID == draft.id {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var managedRuntimeSettings: some View {
        if let runtime {
            let workspace = runtime.workspaceStatus()

            DisclosureGroup(isExpanded: $showsManagedSetupSteps) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Complete these three steps once. Afterwards, Start & Connect is all you normally need.")
                        .font(.callout.weight(.medium))

                    LocalCoreSetupStep(
                        number: 1,
                        title: "Install Core",
                        detail: installStepDetail(runtime),
                        status: installStepStatus(runtime),
                        statusKind: installStepStatusKind(runtime),
                        markerState: installStepMarkerState(runtime)
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            if runtime.locateUVExecutable() == nil {
                                HStack(alignment: .firstTextBaseline) {
                                    Label("uv is required for managed installation.", systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Link(
                                        "Install uv",
                                        destination: URL(string: "https://docs.astral.sh/uv/getting-started/installation/")!
                                    )
                                }
                                .font(.callout)
                            }

                            HStack(spacing: 8) {
                                if isCurrentProfileOperation && model.localRunner.phase == .installing {
                                    ProgressView()
                                        .controlSize(.small)
                                    Button("Cancel Installation") {
                                        Task { await model.stopLocalCore() }
                                    }
                                } else {
                                    Button(runtime.isInstalled ? "Reinstall" : "Install Core") {
                                        guard saveDraft() else { return }
                                        Task { await model.installLocalCore(force: runtime.isInstalled) }
                                    }
                                    .disabled(runtimeIsLocked || runtime.locateUVExecutable() == nil)
                                }

                                if runtime.isInstalled {
                                    Text("Version \(runtime.version)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    LocalCoreSetupStep(
                        number: 2,
                        title: "Configure Workspace",
                        detail: configurationStepDetail(workspace),
                        status: configurationStepStatus(workspace),
                        statusKind: configurationStepStatusKind(workspace),
                        markerState: configurationStepMarkerState(runtime, workspace: workspace)
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(workspace.configurationFileURL.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)

                            if workspace.configurationExists && !workspace.configurationIsReadable {
                                Label(
                                    "config.yml exists, but TeleMessEnd cannot read it. Fix its ownership or permissions, or choose a different workspace above. The existing file will not be replaced.",
                                    systemImage: "lock.trianglebadge.exclamationmark"
                                )
                                .font(.callout)
                                .foregroundStyle(.red)
                            }

                            if workspace.isReadyForLaunch {
                                Label(
                                    "If TeleMessEnd created this config, its local API token is already in Keychain. For an existing config.yml, enter the matching server.token in the Connection section and Save once before starting.",
                                    systemImage: "key"
                                )
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            }

                            HStack {
                                Button {
                                    model.openLocalCoreWorkspace(draft)
                                } label: {
                                    Label("Reveal Workspace", systemImage: "folder")
                                }
                                .disabled(!workspace.workspaceExists)
                                Spacer()
                            }

                            if !workspace.configurationExists {
                                DisclosureGroup("Enter first Telegram account", isExpanded: $showsFirstRunSetup) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("TeleMessEnd creates a private config.yml for this account. The Telegram API hash stays in that file; the generated local API token is saved separately in Keychain.")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)

                                        TextField("Account ID", text: $accountID)
                                        HStack(spacing: 12) {
                                            HStack(spacing: 5) {
                                                Text("Telegram API ID")
                                                Link(destination: telegramAPIAppsURL) {
                                                    Label(
                                                        "Open Telegram API Apps",
                                                        systemImage: "arrow.up.right.square"
                                                    )
                                                    .labelStyle(.iconOnly)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Open Telegram's official page to create or manage API credentials.")
                                            }
                                            Spacer(minLength: 12)
                                            TextField("Telegram API ID", text: $apiID)
                                                .labelsHidden()
                                                .multilineTextAlignment(.trailing)
                                                .frame(minWidth: 180, maxWidth: .infinity)
                                        }
                                        SecureField("Telegram API hash", text: $apiHash)
                                        TextField("Session name", text: $sessionName)
                                        TextField("Timezone", text: $timezone)

                                        if let setupError {
                                            Text(setupError)
                                                .font(.callout)
                                                .foregroundStyle(.red)
                                                .textSelection(.enabled)
                                        }

                                        if model.localCoreKeychainAuthorizationRequired {
                                            Label(
                                                "TeleMessEnd will temporarily lock and reopen the default Keychain so macOS can show its password dialog.",
                                                systemImage: "key.fill"
                                            )
                                            .font(.callout)
                                            .foregroundStyle(.secondary)

                                            Button {
                                                createWorkspaceConfiguration(repairingKeychainAccess: true)
                                            } label: {
                                                Label("Repair Keychain Access & Retry", systemImage: "key.fill")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(runtimeIsLocked)
                                        } else {
                                            Button {
                                                createWorkspaceConfiguration()
                                            } label: {
                                                Label("Create Configuration", systemImage: "lock.shield")
                                            }
                                            .disabled(runtimeIsLocked)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                        }
                    }
                    LocalCoreSetupStep(
                        number: 3,
                        title: "Start & Connect",
                        detail: connectionStepDetail(runtime, workspace: workspace),
                        status: connectionStepStatus(runtime, workspace: workspace),
                        statusKind: connectionStepStatusKind(runtime, workspace: workspace),
                        markerState: connectionStepMarkerState(runtime, workspace: workspace)
                    ) {
                        runtimeControls(runtime: runtime, workspace: workspace)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text("Initial Setup")
                    Spacer()
                    StatusBadge(
                        text: managedSetupIsComplete(runtime, workspace: workspace) ? "Complete" : "In progress",
                        kind: managedSetupIsComplete(runtime, workspace: workspace) ? .success : .warning
                    )
                }
            }
            .onAppear {
                if managedSetupIsComplete(runtime, workspace: workspace) {
                    showsManagedSetupSteps = false
                }
            }
            .onChange(of: managedSetupIsComplete(runtime, workspace: workspace)) {
                if managedSetupIsComplete(runtime, workspace: workspace) {
                    showsManagedSetupSteps = false
                }
            }

            DisclosureGroup("Advanced runtime settings", isExpanded: $showsAdvancedRuntimeSettings) {
                managedRuntimeAdvancedFields
                    .padding(.top, 8)
            }
        } else {
            Label(runtimeConfigurationError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.callout)
                .textSelection(.enabled)
            Text("Correct the managed version or use an absolute workspace path.")
                .font(.callout)
                .foregroundStyle(.secondary)
            managedRuntimeAdvancedFields
        }
    }

    @ViewBuilder
    private var managedRuntimeAdvancedFields: some View {
        Group {
            TextField("Core version", text: $draft.localCoreVersion)
            TextField("Workspace", text: $draft.localWorkspaceDirectory)
        }
        .disabled(runtimeIsLocked)
    }

    @ViewBuilder
    private var customRuntimeSettings: some View {
        TextField("Command", text: $draft.localCommand)
            .disabled(runtimeIsLocked)
        TextField("Working directory", text: $draft.localWorkingDirectory)
            .disabled(runtimeIsLocked)
        Text("Custom commands run through the login shell for compatibility. Managed PyPI mode is recommended for normal local use.")
            .font(.callout)
            .foregroundStyle(.secondary)
        runtimeControls(runtime: nil, workspace: nil)
    }

    private var runtime: ManagedLocalCoreRuntime? {
        try? ManagedLocalCoreRuntime(profile: draft)
    }

    private var telegramAPIAppsURL: URL {
        URL(string: "https://my.telegram.org/apps")!
    }

    private var runtimeConfigurationError: String {
        do {
            _ = try ManagedLocalCoreRuntime(profile: draft)
            return "The managed runtime configuration is invalid."
        } catch {
            return error.localizedDescription
        }
    }

    private var isCurrentProfileProcess: Bool {
        model.localRunner.runningProfileID == draft.id && model.localRunner.isRunning
    }

    private func managedSetupIsComplete(
        _ runtime: ManagedLocalCoreRuntime,
        workspace: LocalCoreWorkspaceStatus
    ) -> Bool {
        runtime.isInstalled
            && workspace.isReadyForLaunch
            && isCurrentProfileProcess
            && model.localRunner.phase == .running
    }

    private var isCurrentProfileOperation: Bool {
        model.localRunner.activeProfileID == draft.id
    }

    private var anotherProfileIsActive: Bool {
        guard let activeProfileID = model.localRunner.activeProfileID else { return false }
        return activeProfileID != draft.id
    }

    private var runtimeIsLocked: Bool {
        model.localRunner.isBusy || model.localRunner.isRunning
    }

    private var canStart: Bool {
        guard !model.localRunner.isBusy, !anotherProfileIsActive else { return false }
        if isCurrentProfileProcess { return false }
        switch draft.localRuntimeMode {
        case .managedPyPI:
            guard let runtime else { return false }
            return runtime.workspaceStatus().isReadyForLaunch
                && (runtime.isInstalled || runtime.locateUVExecutable() != nil)
        case .customCommand:
            return !draft.localCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var runtimeStatusText: String {
        if anotherProfileIsActive {
            return "Another profile is active"
        }
        if isCurrentProfileOperation
            || model.localRunner.statusProfileID == draft.id {
            return model.localRunner.status
        }
        return "Stopped"
    }

    private var runtimeStatusKind: StatusBadgeKind {
        if anotherProfileIsActive { return .warning }
        guard model.localRunner.statusProfileID == draft.id else { return .neutral }
        switch model.localRunner.phase {
        case .running:
            return isCurrentProfileProcess ? .success : .neutral
        case .installing, .starting, .stopping:
            return .warning
        case .failed:
            return .error
        case .idle:
            return .neutral
        }
    }

    @ViewBuilder
    private func runtimeControls(
        runtime: ManagedLocalCoreRuntime?,
        workspace: LocalCoreWorkspaceStatus?
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                guard saveDraft() else { return }
                Task { await model.startLocalCore() }
            } label: {
                Label(startButtonTitle(runtime: runtime, workspace: workspace), systemImage: "play")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)

            if !(draft.localRuntimeMode == .managedPyPI
                && isCurrentProfileOperation
                && model.localRunner.phase == .installing) {
                Button {
                    Task { await model.stopLocalCore() }
                } label: {
                    Label("Stop", systemImage: "stop")
                }
                .disabled(
                    !isCurrentProfileOperation || model.localRunner.phase == .stopping
                )
            }

            StatusBadge(text: runtimeStatusText, kind: runtimeStatusKind)
            Spacer()
        }
    }

    private func startButtonTitle(
        runtime: ManagedLocalCoreRuntime?,
        workspace: LocalCoreWorkspaceStatus?
    ) -> String {
        guard let runtime, workspace?.isReadyForLaunch == true else { return "Start" }
        return runtime.isInstalled ? "Start & Connect" : "Install & Start"
    }

    private func installStepDetail(_ runtime: ManagedLocalCoreRuntime) -> String {
        if isCurrentProfileOperation && model.localRunner.phase == .installing {
            return "Downloading the pinned PyPI package into TeleMessEnd's private runtime. Your system Python is not changed."
        }
        if runtime.isInstalled {
            return "The managed Core is available in TeleMessEnd's private runtime. Reinstall only when you want to repair this version."
        }
        if runtime.locateUVExecutable() == nil {
            return "Install uv first. TeleMessEnd uses it to install the pinned Core package without changing your system Python."
        }
        if localRunnerFailedForDraft {
            return "The installation did not finish. Review the error below, then try Install Core again."
        }
        return "Install tele-mess-core \(runtime.version) from PyPI into an app-managed, versioned runtime."
    }

    private func installStepStatus(_ runtime: ManagedLocalCoreRuntime) -> String {
        if isCurrentProfileOperation && model.localRunner.phase == .installing {
            return "Installing"
        }
        if runtime.isInstalled { return "Complete" }
        if runtime.locateUVExecutable() == nil { return "uv required" }
        if localRunnerFailedForDraft { return "Install failed" }
        return "Required"
    }

    private func installStepStatusKind(_ runtime: ManagedLocalCoreRuntime) -> StatusBadgeKind {
        if runtime.isInstalled { return .success }
        if runtime.locateUVExecutable() == nil || localRunnerFailedForDraft { return .error }
        return .warning
    }

    private func installStepMarkerState(_ runtime: ManagedLocalCoreRuntime) -> LocalCoreSetupMarkerState {
        if runtime.isInstalled { return .complete }
        if runtime.locateUVExecutable() == nil || localRunnerFailedForDraft { return .problem }
        return .current
    }

    private func configurationStepDetail(_ workspace: LocalCoreWorkspaceStatus) -> String {
        if workspace.isReadyForLaunch {
            return "config.yml is readable. Reveal the workspace whenever you need to manage accounts or advanced Core options."
        }
        if workspace.configurationExists {
            return "A config.yml file was found, but it cannot be read. TeleMessEnd will not overwrite the existing file."
        }
        if runtime?.isInstalled == true {
            return "Core is installed. Next, create config.yml and save the matching local API token in Keychain."
        }
        return "Create a private config.yml for the first Telegram account. You can prepare this while Core is installing."
    }

    private func configurationStepStatus(_ workspace: LocalCoreWorkspaceStatus) -> String {
        if workspace.isReadyForLaunch { return "Complete" }
        if workspace.configurationExists { return "Unreadable" }
        return "Required"
    }

    private func configurationStepStatusKind(
        _ workspace: LocalCoreWorkspaceStatus
    ) -> StatusBadgeKind {
        if workspace.isReadyForLaunch { return .success }
        if workspace.configurationExists { return .error }
        return .warning
    }

    private func configurationStepMarkerState(
        _ runtime: ManagedLocalCoreRuntime,
        workspace: LocalCoreWorkspaceStatus
    ) -> LocalCoreSetupMarkerState {
        if workspace.isReadyForLaunch { return .complete }
        if workspace.configurationExists { return .problem }
        return runtime.isInstalled ? .current : .pending
    }

    private func connectionStepDetail(
        _ runtime: ManagedLocalCoreRuntime,
        workspace: LocalCoreWorkspaceStatus
    ) -> String {
        if anotherProfileIsActive {
            return "Another local profile owns the Core process. Stop it before starting this profile."
        }
        if isCurrentProfileOperation {
            switch model.localRunner.phase {
            case .installing:
                return "Core installation is in progress. Its next launch will wait for the pinned package to be ready."
            case .starting:
                return "Launching Core and checking its authenticated health and API manifest before marking it connected."
            case .running:
                return "Core is running and its API contract has been verified for this profile."
            case .stopping:
                return "Stopping the managed Core process and its child processes."
            case .idle, .failed:
                break
            }
        }
        if workspace.configurationExists && !workspace.configurationIsReadable {
            return "Start is blocked until config.yml is readable. Fix step 2 or choose a different workspace."
        }
        if !workspace.configurationExists {
            if runtime.isInstalled {
                return "Core is installed, but it has nothing to run yet. Create the workspace configuration in step 2."
            }
            return "Complete installation and workspace configuration first."
        }
        if connectionFailedForDraft {
            return "The last launch or connection check failed. Review the error below, then try again."
        }
        if !runtime.isInstalled {
            return "The workspace is ready. Install Core in step 1, or choose Install & Start here to do both."
        }
        return "Launch Core on 127.0.0.1 and verify the authenticated local API before TeleMessEnd connects."
    }

    private func connectionStepStatus(
        _ runtime: ManagedLocalCoreRuntime,
        workspace: LocalCoreWorkspaceStatus
    ) -> String {
        if anotherProfileIsActive { return "Unavailable" }
        if isCurrentProfileOperation {
            switch model.localRunner.phase {
            case .installing:
                return "Waiting for install"
            case .starting:
                return "Connecting"
            case .running:
                return "Connected"
            case .stopping:
                return "Stopping"
            case .idle, .failed:
                break
            }
        }
        if isCurrentProfileProcess { return "Connected" }
        if workspace.configurationExists && !workspace.configurationIsReadable { return "Blocked" }
        if !workspace.configurationExists { return "Waiting for config" }
        if connectionFailedForDraft { return "Connection failed" }
        return runtime.isInstalled ? "Ready" : "Ready after install"
    }

    private func connectionStepStatusKind(
        _ runtime: ManagedLocalCoreRuntime,
        workspace: LocalCoreWorkspaceStatus
    ) -> StatusBadgeKind {
        if isCurrentProfileProcess, model.localRunner.phase == .running { return .success }
        if workspace.configurationExists && !workspace.configurationIsReadable { return .error }
        if connectionFailedForDraft && workspace.isReadyForLaunch { return .error }
        if anotherProfileIsActive || isCurrentProfileOperation { return .warning }
        if workspace.isReadyForLaunch { return runtime.isInstalled ? .neutral : .warning }
        return .neutral
    }

    private func connectionStepMarkerState(
        _ runtime: ManagedLocalCoreRuntime,
        workspace: LocalCoreWorkspaceStatus
    ) -> LocalCoreSetupMarkerState {
        if isCurrentProfileProcess, model.localRunner.phase == .running { return .complete }
        if workspace.configurationExists && !workspace.configurationIsReadable { return .problem }
        if connectionFailedForDraft && workspace.isReadyForLaunch { return .problem }
        if workspace.isReadyForLaunch && runtime.isInstalled { return .current }
        return .pending
    }

    private var localRunnerFailedForDraft: Bool {
        model.localRunner.phase == .failed
            && model.localRunner.statusProfileID == draft.id
    }

    private var connectionFailedForDraft: Bool {
        localRunnerFailedForDraft
            || (model.selectedProfile?.id == draft.id && model.validationStatus == .failed)
    }

    private func createWorkspaceConfiguration(repairingKeychainAccess: Bool = false) {
        guard saveDraft() else { return }
        guard let parsedAPIID = Int(apiID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            setupError = "Telegram API ID must be a positive integer."
            return
        }
        let configuration = LocalCoreBootstrapConfiguration(
            accountID: accountID,
            apiID: parsedAPIID,
            apiHash: apiHash,
            sessionName: sessionName,
            timezone: timezone
        )
        if model.bootstrapLocalCore(
            configuration,
            repairingKeychainAccess: repairingKeychainAccess
        ) {
            apiHash = ""
            setupError = nil
            showsFirstRunSetup = false
        } else {
            setupError = model.lastError
        }
    }
}

private enum LocalCoreSetupMarkerState: Equatable {
    case pending
    case current
    case complete
    case problem
}

private struct LocalCoreSetupStep<Content: View>: View {
    let number: Int
    let title: String
    let detail: String
    let status: String
    let statusKind: StatusBadgeKind
    let markerState: LocalCoreSetupMarkerState
    let content: Content

    init(
        number: Int,
        title: String,
        detail: String,
        status: String,
        statusKind: StatusBadgeKind,
        markerState: LocalCoreSetupMarkerState,
        @ViewBuilder content: () -> Content
    ) {
        self.number = number
        self.title = title
        self.detail = detail
        self.status = status
        self.statusKind = statusKind
        self.markerState = markerState
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            marker
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    StatusBadge(text: status, kind: statusKind)
                }

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                content
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var marker: some View {
        if markerState == .complete {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 24, height: 24)
                .accessibilityLabel("Step \(number) complete")
        } else {
            Text("\(number)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(markerForeground)
                .frame(width: 22, height: 22)
                .background(markerBackground, in: Circle())
                .overlay {
                    Circle()
                        .stroke(markerForeground.opacity(0.55), lineWidth: 1)
                }
                .accessibilityLabel("Step \(number)")
        }
    }

    private var markerForeground: Color {
        switch markerState {
        case .pending:
            .secondary
        case .current:
            .accentColor
        case .complete:
            .green
        case .problem:
            .red
        }
    }

    private var markerBackground: Color {
        switch markerState {
        case .pending:
            Color.secondary.opacity(0.08)
        case .current:
            Color.accentColor.opacity(0.12)
        case .complete:
            Color.green.opacity(0.12)
        case .problem:
            Color.red.opacity(0.12)
        }
    }
}
