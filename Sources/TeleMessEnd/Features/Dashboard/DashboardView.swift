import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.dashboard.coreState != nil {
                connectedDashboard
            } else {
                DashboardOnboardingView(model: model)
            }
        }
        .navigationTitle("Dashboard")
    }

    private var connectedDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metrics
                recentMessages
                operationEvents
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedProfile?.name ?? "No Profile")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(model.selectedProfile?.baseURLString ?? "Create a profile in Settings")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: model.validationStatus.title, kind: validationBadgeKind)
            Button {
                Task { await model.validateActiveProfile() }
            } label: {
                Label("Validate", systemImage: model.validationStatus.systemImage)
            }
            .tint(validationTint)
            .disabled(model.isLoading)
            Button {
                model.openConsole()
            } label: {
                Label("Open Console", systemImage: "safari")
            }
        }
    }

    private var validationBadgeKind: StatusBadgeKind {
        switch model.validationStatus {
        case .verified:
            .success
        case .validating:
            .warning
        case .unverified, .failed:
            .error
        }
    }

    private var validationTint: Color {
        switch model.validationStatus {
        case .verified:
            .green
        case .validating:
            .orange
        case .unverified, .failed:
            .red
        }
    }

    private var metrics: some View {
        let state = model.dashboard.coreState
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            MetricCard(title: "Messages", value: DisplayFormat.count(state?.messageCount), detail: "Archived rows", systemImage: "tray.full")
            MetricCard(title: "Last Event", value: DisplayFormat.count(state?.lastEventSeq), detail: "Sync cursor", systemImage: "arrow.left.arrow.right")
            MetricCard(title: "Operation Errors", value: DisplayFormat.count(state?.operationErrorCount), detail: "Failed, partial, rate limited", systemImage: "exclamationmark.triangle")
            MetricCard(title: "Schema", value: state?.schemaVersionText ?? "-", detail: "Core archive schema", systemImage: "square.stack.3d.up")
            MetricCard(title: "Database", value: state?.databaseID ?? "-", detail: "Archive identity", systemImage: "cylinder")
            MetricCard(title: "Server Time", value: DisplayFormat.shortDateTime(state?.serverTime), detail: "Core clock", systemImage: "clock")
            MetricCard(title: "API Contract", value: model.dashboard.apiManifest?.contractVersion ?? "-", detail: "Live manifest version", systemImage: "doc.badge.gearshape")
            MetricCard(title: "Contract Hash", value: model.dashboard.apiManifest?.contractHash ?? "-", detail: "Compatibility fingerprint", systemImage: "number")
        }
    }

    private var recentMessages: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Messages")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await model.loadDashboard() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
            if model.dashboard.recentMessages.isEmpty {
                EmptyStateView(title: "No messages loaded", detail: "Refresh the dashboard after connecting to a core profile.", systemImage: "bubble.left")
                    .frame(height: 180)
            } else {
                MessageTable(messages: model.dashboard.recentMessages)
                    .frame(minHeight: 260)
            }
        }
    }

    private var operationEvents: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Failed Operation Events")
                .font(.headline)
            if model.dashboard.operationEvents.isEmpty {
                Text("No failed operation events loaded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                OperationEventsTable(events: model.dashboard.operationEvents, selection: .constant(nil))
                    .frame(minHeight: 180)
            }
        }
    }
}

private struct DashboardOnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ContentUnavailableView {
                    Label(state.title, systemImage: state.systemImage)
                } description: {
                    VStack(spacing: 6) {
                        Text(state.detail)
                        if let profile = model.selectedProfile {
                            Text("\(profile.name) · \(profile.baseURLString)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                    }
                } actions: {
                    HStack(spacing: 10) {
                        primaryAction

                        if shouldOfferManagedConnectionCheck {
                            Button {
                                Task { await model.validateActiveProfile() }
                            } label: {
                                Label("Connect if Running", systemImage: "network")
                            }
                            .disabled(actionIsBusy)
                            .help("Connect to a local Core that you started outside TeleMessEnd.")
                        }

                        if state.primaryAction != .openSettings {
                            Button {
                                openCoreSettings()
                            } label: {
                                Label("Core Settings", systemImage: "gearshape")
                            }
                        }
                    }
                }

                if let profile = model.selectedProfile {
                    switch profile.kind {
                    case .local:
                        switch profile.localRuntimeMode {
                        case .managedPyPI:
                            if let managedState {
                                managedSetupGuide(managedState)
                            } else {
                                invalidManagedRuntimeGuide
                            }
                        case .customCommand:
                            customRuntimeGuide
                        }
                    case .remote:
                        remoteConnectionGuide
                    }
                }

                if let onboardingError {
                    connectionError(onboardingError)
                }
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch state.primaryAction {
        case .install:
            Button {
                Task { await model.installLocalCore() }
            } label: {
                Label(state.primaryActionTitle, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(actionIsBusy)
        case .start:
            Button {
                Task { await model.startLocalCore() }
            } label: {
                Label(state.primaryActionTitle, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(actionIsBusy)
        case .validate:
            Button {
                Task { await model.validateActiveProfile() }
            } label: {
                Label(state.primaryActionTitle, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(actionIsBusy)
        case .openSettings:
            Button {
                openCoreSettings()
            } label: {
                Label(state.primaryActionTitle, systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        case .none:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(state.primaryActionTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func managedSetupGuide(_ managedState: ManagedSetupState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up a local Core")
                .font(.headline)

            DashboardSetupStep(
                number: 1,
                title: "Install tele-mess-core",
                detail: managedState.isInstalled
                    ? "Version \(managedState.version) is installed for TeleMessEnd."
                    : (managedState.uvIsAvailable
                        ? "TeleMessEnd installs the pinned PyPI package in its own managed runtime."
                        : "Install uv first; TeleMessEnd uses it to create an isolated managed runtime."),
                status: managedState.isInstalled ? .complete : .current
            )

            DashboardSetupStep(
                number: 2,
                title: "Create the workspace configuration",
                detail: managedState.configurationIsReady
                    ? "config.yml is ready in the local workspace."
                    : "After installation, open Core Settings and enter your Telegram API ID and API hash. TeleMessEnd will create config.yml and save a generated local API token in Keychain.",
                status: managedState.configurationIsReady
                    ? .complete
                    : (managedState.isInstalled ? .current : .pending)
            )

            DashboardSetupStep(
                number: 3,
                title: "Start and connect",
                detail: managedState.processIsRunning
                    ? "The process is running; TeleMessEnd is checking the authenticated Core API."
                    : "Start Core here or from Core Settings, then TeleMessEnd will validate the live API contract.",
                status: managedState.processIsRunning
                    ? .current
                    : (managedState.isInstalled && managedState.configurationIsReady ? .current : .pending)
            )
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var customRuntimeGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Custom local command", systemImage: "terminal")
                .font(.headline)
            Text("TeleMessEnd will run the saved command through your login shell. Configure the command and working directory in Core Settings, and make sure it exposes the Core API at this profile's Base URL.")
                .foregroundStyle(.secondary)
            Text("Custom runtimes manage their own installation and config.yml.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var invalidManagedRuntimeGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Managed runtime settings need attention", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            Text("Review the Core version and workspace path in Core Settings. TeleMessEnd needs a valid absolute workspace before it can install or configure Core.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var remoteConnectionGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect to an existing Core", systemImage: "network")
                .font(.headline)
            Text("Check the remote Base URL and authentication token in Core Settings. Validate retries the health check and loads the live API contract without changing the remote archive.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func connectionError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Last connection attempt", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.25))
        }
    }

    private var state: DashboardOnboardingState {
        guard let profile = model.selectedProfile else {
            return DashboardOnboardingState(
                title: "Choose a Core",
                detail: "Add a local Core for this Mac or connect to an existing remote Core.",
                systemImage: "point.3.connected.trianglepath.dotted",
                primaryAction: .openSettings,
                primaryActionTitle: "Open Core Settings"
            )
        }

        switch profile.kind {
        case .local:
            return localState(for: profile)
        case .remote:
            return remoteState(for: profile)
        }
    }

    private func localState(for profile: CoreProfile) -> DashboardOnboardingState {
        if model.localRunner.activeProfileID == profile.id,
           model.localRunner.isBusy {
            let actionTitle: String
            switch model.localRunner.phase {
            case .installing:
                actionTitle = "Installing Core…"
            case .starting:
                actionTitle = "Starting Core…"
            case .stopping:
                actionTitle = "Stopping Core…"
            case .idle, .running, .failed:
                actionTitle = "Working…"
            }
            return DashboardOnboardingState(
                title: actionTitle.replacingOccurrences(of: "…", with: ""),
                detail: model.localRunner.status,
                systemImage: "desktopcomputer",
                primaryAction: .none,
                primaryActionTitle: actionTitle
            )
        }

        if let activeProfileID = model.localRunner.activeProfileID,
           activeProfileID != profile.id {
            return DashboardOnboardingState(
                title: "Another local Core is active",
                detail: "Stop the other local profile before starting \(profile.name).",
                systemImage: "exclamationmark.triangle",
                primaryAction: .openSettings,
                primaryActionTitle: "Open Core Settings"
            )
        }

        switch profile.localRuntimeMode {
        case .managedPyPI:
            guard let managedState else {
                return DashboardOnboardingState(
                    title: "Finish local Core setup",
                    detail: "The managed runtime settings need attention before TeleMessEnd can install Core.",
                    systemImage: "wrench.and.screwdriver",
                    primaryAction: .openSettings,
                    primaryActionTitle: "Review Core Settings"
                )
            }
            if !managedState.isInstalled, !managedState.uvIsAvailable {
                return DashboardOnboardingState(
                    title: "Install uv to continue",
                    detail: "Managed Core installation needs uv. Core Settings includes the official installation link and will detect it automatically afterward.",
                    systemImage: "wrench.and.screwdriver",
                    primaryAction: .openSettings,
                    primaryActionTitle: "View Install Instructions"
                )
            }
            if !managedState.isInstalled {
                return DashboardOnboardingState(
                    title: "Install the local Core",
                    detail: "Install tele-mess-core \(managedState.version), then create its workspace configuration before the first start.",
                    systemImage: "square.and.arrow.down",
                    primaryAction: .install,
                    primaryActionTitle: model.localRunner.phase == .failed ? "Retry Install" : "Install Core"
                )
            }
            if !managedState.configurationIsReady {
                return DashboardOnboardingState(
                    title: managedState.configurationExists
                        ? "Local configuration needs attention"
                        : "Configure the installed Core",
                    detail: managedState.configurationExists
                        ? "The workspace config.yml exists but is not readable. Review the workspace before starting Core."
                        : "Core is installed. Add your Telegram account details to create config.yml and the local API credential.",
                    systemImage: managedState.configurationExists
                        ? "exclamationmark.shield"
                        : "list.bullet.clipboard",
                    primaryAction: .openSettings,
                    primaryActionTitle: "Configure Core"
                )
            }
            if managedState.processIsRunning {
                return DashboardOnboardingState(
                    title: "Connect to the running Core",
                    detail: "The local process is running, but dashboard data is not available yet. Retry the authenticated connection.",
                    systemImage: "arrow.triangle.2.circlepath",
                    primaryAction: model.validationStatus == .validating ? .none : .validate,
                    primaryActionTitle: model.validationStatus == .validating ? "Checking connection…" : "Retry Connection"
                )
            }
            return DashboardOnboardingState(
                title: "Start your local Core",
                detail: "Installation and config.yml are ready. Start Core to migrate the workspace, open its API, and load your dashboard.",
                systemImage: "play.circle",
                primaryAction: .start,
                primaryActionTitle: model.localRunner.phase == .failed ? "Retry Start" : "Start Core"
            )
        case .customCommand:
            if profile.localCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return DashboardOnboardingState(
                    title: "Configure the local command",
                    detail: "Add the Core launch command and working directory before starting this profile.",
                    systemImage: "terminal",
                    primaryAction: .openSettings,
                    primaryActionTitle: "Configure Command"
                )
            }
            if model.localRunner.runningProfileID == profile.id,
               model.localRunner.isRunning {
                return DashboardOnboardingState(
                    title: "Connect to the running Core",
                    detail: "The custom Core process is running, but dashboard data is not available yet.",
                    systemImage: "arrow.triangle.2.circlepath",
                    primaryAction: model.validationStatus == .validating ? .none : .validate,
                    primaryActionTitle: model.validationStatus == .validating ? "Checking connection…" : "Retry Connection"
                )
            }
            return DashboardOnboardingState(
                title: "Start the custom local Core",
                detail: "Run the configured command, then TeleMessEnd will validate its live API contract.",
                systemImage: "terminal.fill",
                primaryAction: .start,
                primaryActionTitle: model.localRunner.phase == .failed ? "Retry Start" : "Start Core"
            )
        }
    }

    private func remoteState(for profile: CoreProfile) -> DashboardOnboardingState {
        guard let url = profile.baseURL,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return DashboardOnboardingState(
                title: "Configure the remote Core",
                detail: "Enter a complete HTTP or HTTPS Base URL and authentication details before connecting.",
                systemImage: "network",
                primaryAction: .openSettings,
                primaryActionTitle: "Configure Connection"
            )
        }

        if model.validationStatus == .validating || model.isLoading {
            return DashboardOnboardingState(
                title: "Connecting to \(profile.name)",
                detail: "TeleMessEnd is checking the remote Core API and loading its dashboard.",
                systemImage: "network",
                primaryAction: .none,
                primaryActionTitle: "Checking connection…"
            )
        }

        return DashboardOnboardingState(
            title: model.validationStatus == .failed
                ? "Could not connect to \(profile.name)"
                : "Connect to \(profile.name)",
            detail: "Validate the remote Core health, credentials, and live API contract before loading data.",
            systemImage: model.validationStatus == .failed
                ? "network.slash"
                : "network",
            primaryAction: .validate,
            primaryActionTitle: model.validationStatus == .failed ? "Retry Connection" : "Validate Connection"
        )
    }

    private var managedState: ManagedSetupState? {
        guard let profile = model.selectedProfile,
              profile.kind == .local,
              profile.localRuntimeMode == .managedPyPI,
              let runtime = try? ManagedLocalCoreRuntime(profile: profile) else {
            return nil
        }
        let workspace = runtime.workspaceStatus()
        return ManagedSetupState(
            version: runtime.version,
            isInstalled: runtime.isInstalled,
            uvIsAvailable: runtime.locateUVExecutable() != nil,
            configurationExists: workspace.configurationExists,
            configurationIsReady: workspace.isReadyForLaunch,
            processIsRunning: model.localRunner.runningProfileID == profile.id
                && model.localRunner.isRunning
        )
    }

    private var actionIsBusy: Bool {
        model.isLoading
            || model.validationStatus == .validating
            || model.localRunner.isBusy
            || (model.localRunner.activeProfileID != nil
                && model.localRunner.activeProfileID != model.selectedProfile?.id)
    }

    private var shouldOfferManagedConnectionCheck: Bool {
        guard let managedState,
              managedState.configurationIsReady,
              !managedState.processIsRunning else {
            return false
        }
        return state.primaryAction != .validate && state.primaryAction != .none
    }

    private var onboardingError: String? {
        if model.localRunner.statusProfileID == model.selectedProfile?.id,
           let runnerError = model.localRunner.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !runnerError.isEmpty {
            return runnerError
        }

        // A connection failure is expected before a managed runtime has been
        // installed and configured. Keep that initial state focused on the
        // setup steps instead of presenting the absent server as a fault.
        if let managedState,
           (!managedState.isInstalled || !managedState.configurationIsReady) {
            return nil
        }

        guard let error = model.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
              !error.isEmpty else {
            return nil
        }
        return error
    }

    private func openCoreSettings() {
        model.settingsSection = .core
        openSettings()
    }
}

private struct DashboardOnboardingState {
    var title: String
    var detail: String
    var systemImage: String
    var primaryAction: DashboardOnboardingAction
    var primaryActionTitle: String
}

private enum DashboardOnboardingAction: Equatable {
    case install
    case start
    case validate
    case openSettings
    case none
}

private struct ManagedSetupState {
    var version: String
    var isInstalled: Bool
    var uvIsAvailable: Bool
    var configurationExists: Bool
    var configurationIsReady: Bool
    var processIsRunning: Bool
}

private struct DashboardSetupStep: View {
    var number: Int
    var title: String
    var detail: String
    var status: Status

    enum Status {
        case complete
        case current
        case pending
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 28, height: 28)
                if status == .complete {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(iconForeground)
                } else {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(iconForeground)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stepAccessibilityLabel)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(status == .current ? .semibold : .regular)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(status == .pending ? 0.62 : 1)
    }

    private var iconBackground: Color {
        switch status {
        case .complete:
            .green
        case .current:
            .accentColor
        case .pending:
            Color.secondary.opacity(0.15)
        }
    }

    private var iconForeground: Color {
        status == .pending ? .secondary : .white
    }

    private var stepAccessibilityLabel: String {
        switch status {
        case .complete:
            "Step \(number) complete"
        case .current:
            "Step \(number), current"
        case .pending:
            "Step \(number), pending"
        }
    }
}
