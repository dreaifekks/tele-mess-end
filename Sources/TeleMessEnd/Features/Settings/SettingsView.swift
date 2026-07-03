import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var draft = CoreProfile.defaultLocal
    @State private var token = ""

    var body: some View {
        TabView {
            profileSettings
                .tabItem { Label("Profiles", systemImage: "server.rack") }
            localRuntime
                .tabItem { Label("Local Core", systemImage: "terminal") }
        }
        .frame(width: 620, height: 460)
        .scenePadding()
        .onAppear(perform: loadDraft)
        .onChange(of: model.profileStore.selectedProfileID) {
            loadDraft()
        }
    }

    private var profileSettings: some View {
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
                Section("Profile") {
                    TextField("Name", text: $draft.name)
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(CoreProfileKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    TextField("Base URL", text: $draft.baseURLString)
                    Picker("Auth", selection: $draft.authMode) {
                        ForEach(CoreAuthMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    SecureField("API token", text: $token)
                }

                if draft.kind == .local {
                    Section("Local Command") {
                        TextField("Command", text: $draft.localCommand)
                        TextField("Working directory", text: $draft.localWorkingDirectory)
                    }
                }

                Section {
                    HStack {
                        Button {
                            model.saveProfile(draft, token: token)
                        } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                        Button {
                            Task { await model.validateActiveProfile() }
                        } label: {
                            Label("Test", systemImage: "network")
                        }
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

    private var localRuntime: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Local Core Runner")
                .font(.headline)
            Text("Runs the selected local profile command. Remote profiles are managed through their HTTP endpoint only.")
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    model.startLocalCore()
                } label: {
                    Label("Start", systemImage: "play")
                }
                .disabled(model.selectedProfile?.kind != .local)
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
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
    }

    private func loadDraft() {
        draft = model.selectedProfile ?? .defaultLocal
        token = model.tokenForSelectedProfile()
    }
}
