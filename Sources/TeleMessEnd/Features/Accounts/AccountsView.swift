import SwiftUI

struct AccountsView: View {
    @Bindable var model: AppModel
    @State private var accountID = ""
    @State private var displayName = ""
    @State private var phone = ""
    @State private var sessionName = ""
    @State private var sessionDir = ""
    @State private var code = ""
    @State private var password = ""
    @State private var pendingDeleteAccount: CoreAccount?

    var body: some View {
        HSplitView {
            accountForm
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Accounts")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await model.loadAccounts() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }

                if model.accounts.isEmpty {
                    EmptyStateView(title: "No accounts", detail: "Create account metadata, then request a Telegram login code.", systemImage: "person.badge.plus")
                } else {
                    AccountsTable(accounts: model.accounts, select: { account in
                        accountID = account.accountID
                        displayName = account.displayName ?? ""
                        phone = account.phone ?? ""
                        sessionName = account.sessionName ?? account.accountID
                        sessionDir = account.sessionDir ?? ""
                    }, requestDelete: { account in
                        pendingDeleteAccount = account
                    })
                }
            }
            .padding(20)
        }
        .navigationTitle("Accounts")
        .task {
            if model.accounts.isEmpty {
                await model.loadAccounts()
            }
        }
        .alert("Delete account metadata?", isPresented: Binding(
            get: { pendingDeleteAccount != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteAccount = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                if let account = pendingDeleteAccount {
                    Task { await model.deleteAccount(account) }
                }
                pendingDeleteAccount = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAccount = nil
            }
        } message: {
            Text("This removes account management metadata through the core API. Archived messages remain unless the core changes that contract.")
        }
    }

    private var accountForm: some View {
        Form {
            Section("Account") {
                TextField("Account ID", text: $accountID)
                TextField("Display name", text: $displayName)
                TextField("Phone", text: $phone)
                TextField("Session name", text: $sessionName)
                TextField("Session directory", text: $sessionDir)
                Button {
                    Task {
                        await model.createAccount(
                            CreateAccountRequest(
                                accountID: accountID,
                                displayName: displayName.nilIfEmpty,
                                phone: phone.nilIfEmpty,
                                sessionName: sessionName.nilIfEmpty,
                                sessionDir: sessionDir.nilIfEmpty
                            )
                        )
                    }
                } label: {
                    Label("Save Account", systemImage: "square.and.arrow.down")
                }
                .disabled(accountID.isEmpty)
            }

            Section("Telegram Auth") {
                TextField("Login code", text: $code)
                SecureField("2FA password", text: $password)
                HStack {
                    Button("Status") {
                        Task { await model.authStatus(accountID: accountID) }
                    }
                    .disabled(accountID.isEmpty)
                    Button("Request Code") {
                        Task { await model.requestCode(accountID: accountID, phone: phone) }
                    }
                    .disabled(accountID.isEmpty || phone.isEmpty)
                }
                Button {
                    Task {
                        await model.submitCode(accountID: accountID, phone: phone, code: code, password: password.nilIfEmpty)
                    }
                } label: {
                    Label("Submit Code", systemImage: "paperplane")
                }
                .disabled(accountID.isEmpty || phone.isEmpty || code.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct AccountsTable: View {
    var accounts: [CoreAccount]
    var select: (CoreAccount) -> Void
    var requestDelete: (CoreAccount) -> Void

    var body: some View {
        Table(accounts) {
            TableColumn("Account") { account in
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.title)
                        .lineLimit(1)
                    Text(account.accountID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Auth") { account in
                StatusBadge(text: account.authState ?? "unknown", kind: account.lastError == nil ? .neutral : .error)
            }
            TableColumn("Session") { account in
                Text(account.sessionName ?? "")
                    .lineLimit(1)
            }
            TableColumn("Phone") { account in
                Text(account.phone ?? "")
                    .lineLimit(1)
            }
            TableColumn("Last Error") { account in
                Text(account.lastError ?? "")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            TableColumn("Updated") { account in
                Text(DisplayFormat.shortDateTime(account.authUpdatedAt ?? account.updatedAt))
                    .foregroundStyle(.secondary)
            }
            TableColumn("Actions") { account in
                HStack {
                    Button("Use") {
                        select(account)
                    }
                    Button(role: .destructive) {
                        requestDelete(account)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
