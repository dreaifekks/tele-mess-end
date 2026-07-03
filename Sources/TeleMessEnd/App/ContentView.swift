import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @AppStorage(AppPreferenceKeys.sidebarWidth) private var sidebarWidth = AppLayoutDefaults.sidebarWidth

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $model.selectedSection)
                .navigationSplitViewColumnWidth(min: 170, ideal: sidebarWidth, max: 280)
        } detail: {
            detailView
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        ProfilePicker(model: model)

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

                        StatusBadge(text: toolbarStatusText, kind: model.lastError == nil ? .neutral : .error)
                            .help(model.lastError ?? model.statusMessage)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    StatusBar(model: model)
                }
        }
        .task {
            await model.loadDashboard()
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
        if error.localizedCaseInsensitiveContains("unauthorized") || error.localizedCaseInsensitiveContains("401") {
            return "Auth failed"
        }
        return "Error"
    }
}

private struct ProfilePicker: View {
    @Bindable var model: AppModel

    var body: some View {
        Picker("Profile", selection: Binding<UUID?>(
            get: { model.profileStore.selectedProfileID },
            set: { model.profileStore.select($0) }
        )) {
            ForEach(model.profileStore.profiles) { profile in
                Text(profile.name).tag(Optional(profile.id))
            }
        }
        .frame(minWidth: 170)
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
