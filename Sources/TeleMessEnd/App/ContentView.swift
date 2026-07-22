import SwiftUI

private struct ContentLoadKey: Hashable {
    var sessionRevision: UInt64
    var section: AppSection
    var diagnosticsSection: DiagnosticsSection?
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var observedSessionRevision: UInt64?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $model.selectedSection, sections: model.availableSections)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } detail: {
            detailView
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        ProfileMenu(model: model)

                        Button {
                            Task { await model.refreshCurrentSection() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isLoading)

                        Button {
                            model.openConsole()
                        } label: {
                            Label("Console", systemImage: "safari")
                        }

                        ToolbarStatusPill(text: toolbarStatusText, kind: model.lastError == nil ? .neutral : .error)
                            .help(model.lastError ?? model.statusMessage)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    StatusBar(model: model)
                }
        }
        .task(id: ContentLoadKey(
            sessionRevision: model.sessionRevision,
            section: model.selectedSection,
            diagnosticsSection: model.selectedSection == .diagnostics ? model.diagnosticsSelection : nil
        )) {
            let allowKeychainUI = observedSessionRevision == model.sessionRevision
            observedSessionRevision = model.sessionRevision
            await model.refreshCurrentSectionWhenIdle(allowKeychainUI: allowKeychainUI)
        }
        .task {
            await model.runRecentMessageRefreshLoop()
        }
        .background(WindowFrameAutosaveView(autosaveName: "TeleMessEndMainWindow"))
    }

    @ViewBuilder
    private var detailView: some View {
        switch model.selectedSection {
        case .dashboard:
            DashboardView(model: model)
        case .accounts:
            AccountsView(model: model)
        case .origins:
            OriginsView(model: model)
        case .messages:
            MessagesView(model: model)
        case .messagePoints:
            MessagePointsView(model: model)
        case .media:
            MediaView(model: model)
        case .summaries:
            DailySummaryView(model: model)
        case .diagnostics:
            DiagnosticsView(model: model)
        }
    }

    private var toolbarStatusText: String {
        guard let error = model.lastError else {
            return model.statusMessage
        }
        if error.localizedCaseInsensitiveContains("could not connect") {
            return "Connection failed"
        }
        if error.localizedCaseInsensitiveContains("App Transport Security") {
            return "HTTP blocked"
        }
        if error.localizedCaseInsensitiveContains("unauthorized") || error.localizedCaseInsensitiveContains("401") {
            return "Auth failed"
        }
        return "Error"
    }
}

private struct ProfileMenu: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu {
            ForEach(model.profileStore.profiles) { profile in
                Button {
                    model.selectProfile(profile.id)
                } label: {
                    Label(profile.name, systemImage: profile.id == model.profileStore.selectedProfileID ? "checkmark" : profile.kind.systemImage)
                }
                .disabled(profileSwitchingIsLocked && profile.id != model.profileStore.selectedProfileID)
            }

            if profileSwitchingIsLocked {
                Label("Stop local Core before switching", systemImage: "lock.fill")
            }

            Divider()

            Button {
                model.addRemoteProfile()
                model.settingsSection = .core
                openSettings()
            } label: {
                Label("Add Remote Core", systemImage: "plus")
            }
            .disabled(profileSwitchingIsLocked)

            Button {
                model.addLocalProfile()
                model.settingsSection = .core
                openSettings()
            } label: {
                Label("Add Local Core", systemImage: "plus")
            }
            .disabled(profileSwitchingIsLocked)

            Divider()

            Button {
                model.settingsSection = .core
                openSettings()
            } label: {
                Label("Core Settings", systemImage: "gearshape")
            }
        } label: {
            ToolbarPillLabel(title: model.selectedProfile?.name ?? "Core")
        }
        .buttonStyle(.plain)
    }

    private var profileSwitchingIsLocked: Bool {
        model.localRunner.isBusy || model.localRunner.isRunning
    }
}

private struct ToolbarPillLabel: View {
    var title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 14)
        .frame(minWidth: 180, maxWidth: 260, minHeight: 30)
        .background(.quaternary.opacity(0.55), in: Capsule())
        .contentShape(Capsule())
    }
}

private struct ToolbarStatusPill: View {
    var text: String
    var kind: StatusBadgeKind

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minWidth: 64, minHeight: 30)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
            .contentShape(Capsule())
    }

    private var background: Color {
        switch kind {
        case .neutral:
            Color.secondary.opacity(0.12)
        case .success:
            Color.green.opacity(0.14)
        case .warning:
            Color.orange.opacity(0.16)
        case .error:
            Color.red.opacity(0.16)
        }
    }

    private var foreground: Color {
        switch kind {
        case .neutral:
            .secondary
        case .success:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

private struct StatusBar: View {
    var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.lastError ?? model.statusMessage)
                .foregroundStyle(model.lastError == nil ? Color.secondary : Color.red)
                .lineLimit(1)
            Spacer()
            if let profile = model.selectedProfile {
                Text(profile.baseURLString)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }
}
