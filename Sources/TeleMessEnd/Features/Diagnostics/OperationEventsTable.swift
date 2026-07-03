import SwiftUI

struct OperationEventsTable: View {
    var events: [CoreOperationEvent]
    @Binding var selection: CoreOperationEvent.ID?
    var requestDelete: ((CoreOperationEvent) -> Void)? = nil

    var body: some View {
        if let requestDelete {
            Table(events, selection: $selection) {
                eventColumns

                TableColumn("Delete") { event in
                    Button(role: .destructive) {
                        requestDelete(event)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
                .width(min: 54, ideal: 64, max: 72)
            }
        } else {
            Table(events, selection: $selection) {
                eventColumns
            }
        }
    }

    @TableColumnBuilder<CoreOperationEvent, Never>
    private var eventColumns: some TableColumnContent<CoreOperationEvent, Never> {
        TableColumn("Time") { event in
            Text(DisplayFormat.shortDateTime(event.occurredAt))
                .foregroundStyle(.secondary)
        }
        .width(min: 140, ideal: 180)

        TableColumn("Account") { event in
            Text(event.accountID)
        }
        .width(min: 90, ideal: 120)

        TableColumn("Status") { event in
            StatusBadge(text: event.status, kind: event.status == "failed" ? .error : .warning)
        }
        .width(min: 90, ideal: 120)

        TableColumn("Operation") { event in
            Text(event.operation)
                .lineLimit(1)
        }

        TableColumn("Message") { event in
            Text(event.message ?? event.errorCode ?? "")
                .lineLimit(2)
        }
    }
}
