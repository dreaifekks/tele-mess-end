import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var draft = CoreProfile.defaultLocal
    @State private var token = ""
    @State private var confirmDeleteProfile = false
    @AppStorage(AppPreferenceKeys.defaultWindowWidth) private var defaultWindowWidth = AppLayoutDefaults.windowWidth
    @AppStorage(AppPreferenceKeys.defaultWindowHeight) private var defaultWindowHeight = AppLayoutDefaults.windowHeight
    @AppStorage(AppPreferenceKeys.sidebarWidth) private var sidebarWidth = AppLayoutDefaults.sidebarWidth
    @AppStorage(AppPreferenceKeys.diagnosticsDetailWidth) private var diagnosticsDetailWidth = AppLayoutDefaults.diagnosticsDetailWidth

    var body: some View {
        TabView {
            coreSettings
                .tabItem { Label("Core", systemImage: "server.rack") }
            layoutSettings
                .tabItem { Label("Layout", systemImage: "rectangle.split.3x1") }
        }
        .frame(width: 720, height: 560)
        .scenePadding()
        .onAppear(perform: loadDraft)
        .onChange(of: model.profileStore.selectedProfileID) {
            loadDraft()
        }
        .alert("Delete profile?", isPresented: $confirmDeleteProfile) {
            Button("Delete", role: .destructive) {
                model.deleteSelectedProfile()
                loadDraft()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected local app profile and its stored token. It does not change the core service.")
        }
    }

    private var coreSettings: some View {
        HSplitView {
            List(selection: Binding<UUID?>(
                get: { model.profileStore.selectedProfileID },
                set: { model.profileStore.select($0) }
            )) {
                ForEach(model.profileStore.profiles) { profile in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                        Text(profile.kind.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(profile.id))
                }
            }
            .frame(minWidth: 170, idealWidth: 200)

            Form {
                Section("Core") {
                    TextField("Name", text: $draft.name)
                    Picker("Mode", selection: $draft.kind) {
                        ForEach(CoreProfileKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Base URL", text: $draft.baseURLString)
                    Picker("Auth", selection: $draft.authMode) {
                        ForEach(CoreAuthMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    SecureField("API token", text: $token)
                }

                if draft.kind == .local {
                    Section("Local Runtime") {
                        TextField("Command", text: $draft.localCommand)
                        TextField("Working directory", text: $draft.localWorkingDirectory)
                        HStack {
                            Button {
                                saveDraft()
                                model.startLocalCore()
                            } label: {
                                Label("Start", systemImage: "play")
                            }
                            Button {
                                model.stopLocalCore()
                            } label: {
                                Label("Stop", systemImage: "stop")
                            }
                            .disabled(!model.localRunner.isRunning)
                            StatusBadge(text: model.localRunner.isRunning ? "Running" : "Stopped", kind: model.localRunner.isRunning ? .success : .neutral)
                        }
                        if let error = model.localRunner.lastError {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                        ScrollView {
                            Text(model.localRunner.lastOutput.isEmpty ? "No output yet." : model.localRunner.lastOutput)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(minHeight: 110)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Section {
                    HStack {
                        Button {
                            saveDraft()
                        } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                        Button {
                            saveDraft()
                            Task { await model.validateActiveProfile() }
                        } label: {
                            Label("Test Connection", systemImage: "network")
                        }
                        Button(role: .destructive) {
                            confirmDeleteProfile = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(model.profileStore.profiles.count <= 1)
                        Spacer()
                        Button {
                            draft = model.profileStore.addRemoteProfile()
                            token = ""
                        } label: {
                            Label("Remote", systemImage: "plus")
                        }
                        Button {
                            draft = model.profileStore.addLocalProfile()
                            token = ""
                        } label: {
                            Label("Local", systemImage: "plus")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.leading, 12)
        }
    }

    private var layoutSettings: some View {
        Form {
            Section("Window") {
                LabeledContent("Default width") {
                    Stepper(value: $defaultWindowWidth, in: 980...1800, step: 20) {
                        Text("\(Int(defaultWindowWidth)) px")
                            .monospacedDigit()
                    }
                }
                LabeledContent("Default height") {
                    Stepper(value: $defaultWindowHeight, in: 640...1200, step: 20) {
                        Text("\(Int(defaultWindowHeight)) px")
                            .monospacedDigit()
                    }
                }
            }

            Section("Split View") {
                LabeledContent("Sidebar width") {
                    Stepper(value: $sidebarWidth, in: 170...280, step: 10) {
                        Text("\(Int(sidebarWidth)) px")
                            .monospacedDigit()
                    }
                }
                LabeledContent("Diagnostics detail") {
                    Stepper(value: $diagnosticsDetailWidth, in: 280...620, step: 20) {
                        Text("\(Int(diagnosticsDetailWidth)) px")
                            .monospacedDigit()
                    }
                }
            }

            Section {
                Button {
                    defaultWindowWidth = AppLayoutDefaults.windowWidth
                    defaultWindowHeight = AppLayoutDefaults.windowHeight
                    sidebarWidth = AppLayoutDefaults.sidebarWidth
                    diagnosticsDetailWidth = AppLayoutDefaults.diagnosticsDetailWidth
                } label: {
                    Label("Reset Layout", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func saveDraft() {
        model.saveProfile(draft, token: token)
    }

    private func loadDraft() {
        draft = model.selectedProfile ?? .defaultLocal
        token = model.tokenForSelectedProfile()
    }
}
