import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var draft = CoreProfile.defaultLocal
    @State private var token = ""
    @State private var confirmDeleteProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Core Settings")
                .font(.title2.weight(.semibold))

            coreSettings
        }
        .frame(width: 860, height: 560)
        .padding(24)
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
                            .font(.body.weight(.semibold))
                        Text(profile.kind.title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .tag(Optional(profile.id))
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)

            Form {
                Section("Connection") {
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

                Section("Actions") {
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
                        Spacer()
                        Button(role: .destructive) {
                            confirmDeleteProfile = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(model.profileStore.profiles.count <= 1)
                    }

                    HStack {
                        Button {
                            draft = model.profileStore.addRemoteProfile()
                            token = ""
                        } label: {
                            Label("Add Remote Core", systemImage: "plus")
                        }
                        Spacer()
                        Button {
                            draft = model.profileStore.addLocalProfile()
                            token = ""
                        } label: {
                            Label("Add Local Core", systemImage: "plus")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .controlSize(.large)
            .font(.body)
            .frame(minWidth: 540)
            .padding(.leading, 18)
        }
        .frame(maxHeight: .infinity)
    }

    private func saveDraft() {
        model.saveProfile(draft, token: token)
    }

    private func loadDraft() {
        draft = model.selectedProfile ?? .defaultLocal
        token = model.tokenForSelectedProfile()
    }
}
