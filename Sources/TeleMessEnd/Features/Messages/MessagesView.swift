import SwiftUI

struct MessagesView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Search messages", text: $model.messageSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await model.searchMessages() }
                    }
                Button {
                    Task { await model.searchMessages() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                Button {
                    model.messageSearchQuery = ""
                    Task { await model.loadRecentMessages() }
                } label: {
                    Label("Recent", systemImage: "clock")
                }
            }

            if model.messages.isEmpty {
                EmptyStateView(title: "No messages", detail: "Load recent messages or run a full-text search.", systemImage: "text.bubble")
            } else {
                MessageTable(messages: model.messages)
            }
        }
        .padding(20)
        .navigationTitle("Messages")
        .task {
            if model.messages.isEmpty {
                await model.loadRecentMessages()
            }
        }
    }
}
