import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metrics
                recentMessages
                operationEvents
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedProfile?.name ?? "No Profile")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(model.selectedProfile?.baseURLString ?? "Create a profile in Settings")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.validateActiveProfile() }
            } label: {
                Label("Validate", systemImage: "checkmark.seal")
            }
            Button {
                model.openConsole()
            } label: {
                Label("Open Console", systemImage: "safari")
            }
        }
    }

    private var metrics: some View {
        let state = model.dashboard.coreState
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            MetricCard(title: "Messages", value: DisplayFormat.count(state?.messageCount), detail: "Archived rows", systemImage: "tray.full")
            MetricCard(title: "Last Event", value: DisplayFormat.count(state?.lastEventSeq), detail: "Sync cursor", systemImage: "arrow.left.arrow.right")
            MetricCard(title: "Operation Errors", value: DisplayFormat.count(state?.operationErrorCount), detail: "Failed, partial, rate limited", systemImage: "exclamationmark.triangle")
            MetricCard(title: "Schema", value: state?.schemaVersion ?? "-", detail: state?.databaseID ?? "No database id", systemImage: "cylinder")
        }
    }

    private var recentMessages: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Messages")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await model.loadDashboard() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
            if model.dashboard.recentMessages.isEmpty {
                EmptyStateView(title: "No messages loaded", detail: "Refresh the dashboard after connecting to a core profile.", systemImage: "bubble.left")
                    .frame(height: 180)
            } else {
                MessageTable(messages: model.dashboard.recentMessages)
                    .frame(minHeight: 260)
            }
        }
    }

    private var operationEvents: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Failed Operation Events")
                .font(.headline)
            if model.dashboard.operationEvents.isEmpty {
                Text("No failed operation events loaded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                OperationEventsTable(events: model.dashboard.operationEvents)
                    .frame(minHeight: 180)
            }
        }
    }
}
