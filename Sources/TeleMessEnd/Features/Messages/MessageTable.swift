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
            .width(min: 120, ideal: 160)

            TableColumn("Account") { message in
                Text(message.accountID)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Chat") { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.displayChat)
                        .lineLimit(1)
                    Text("\(message.chatID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 160, ideal: 220)

            TableColumn("Sender") { message in
                Text(message.displaySender)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Text") { message in
                HStack(spacing: 8) {
                    if message.isDeleted {
                        StatusBadge(text: "Deleted", kind: .warning)
                    }
                    Text(message.text ?? "")
                        .lineLimit(3)
                }
            }

            TableColumn("Media") { message in
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
            }
            .width(min: 80, ideal: 110)

            TableColumn("Link") { message in
                if let url = message.telegramDeepLink {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help("Open in Telegram")
                } else {
                    Text("")
                }
            }
            .width(min: 48, ideal: 56, max: 64)
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
