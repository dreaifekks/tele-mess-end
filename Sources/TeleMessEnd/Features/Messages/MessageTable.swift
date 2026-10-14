import SwiftUI

struct MessageTable: View {
    var messages: [CoreMessage]
    var showMedia: ((CoreMessage) -> Void)?

    var body: some View {
        Table(messages) {
            TableColumn("Time") { message in
                Text(DisplayFormat.shortDateTime(message.sentAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120, max: 150)

            TableColumn("Chat") { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.displayChat)
                        .lineLimit(1)
                    Text("\(message.chatID) · \(message.accountID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 160, max: 200)

            TableColumn("Sender") { message in
                Text(message.displaySender)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 120, max: 150)

            TableColumn("Text") { message in
                HStack(spacing: 8) {
                    if message.isDeleted {
                        StatusBadge(text: "Deleted", kind: .warning)
                    }
                    Text(message.text ?? "")
                        .textSelection(.enabled)
                }
            }
            .width(min: 220, ideal: 400)

            TableColumn("Media") { message in
                HStack {
                    if message.hasMedia {
                        Button {
                            showMedia?(message)
                        } label: {
                            Label(mediaLabel(for: message), systemImage: "paperclip")
                        }
                        .buttonStyle(.borderless)
                        .help("Show media files")
                    } else {
                        Text("")
                    }

                    if let url = message.telegramDeepLink {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .help("Open in Telegram")
                    } else {
                        Text("")
                    }
                }
            }
            .width(min: 65, ideal: 80, max: 100)
        }
    }

    private func mediaLabel(for message: CoreMessage) -> String {
        if let count = message.mediaCount, count > 0 {
            return "\(count)"
        }
        if let count = message.mediaFiles?.count, count > 0 {
            return "\(count)"
        }
        return "Media"
    }
}
