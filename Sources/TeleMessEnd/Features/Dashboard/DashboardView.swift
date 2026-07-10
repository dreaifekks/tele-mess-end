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
            StatusBadge(text: model.validationStatus.title, kind: validationBadgeKind)
            Button {
                Task { await model.validateActiveProfile() }
            } label: {
                Label("Validate", systemImage: model.validationStatus.systemImage)
            }
            .tint(validationTint)
            .disabled(model.isLoading)
            Button {
                model.openConsole()
            } label: {
                Label("Open Console", systemImage: "safari")
            }
        }
    }

    private var validationBadgeKind: StatusBadgeKind {
        switch model.validationStatus {
        case .verified:
            .success
        case .validating:
            .warning
        case .unverified, .failed:
            .error
        }
    }

    private var validationTint: Color {
        switch model.validationStatus {
        case .verified:
            .green
        case .validating:
            .orange
        case .unverified, .failed:
            .red
        }
    }

    private var metrics: some View {
        let state = model.dashboard.coreState
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            MetricCard(title: "Messages", value: DisplayFormat.count(state?.messageCount), detail: "Archived rows", systemImage: "tray.full")
            MetricCard(title: "Last Event", value: DisplayFormat.count(state?.lastEventSeq), detail: "Sync cursor", systemImage: "arrow.left.arrow.right")
            MetricCard(title: "Operation Errors", value: DisplayFormat.count(state?.operationErrorCount), detail: "Failed, partial, rate limited", systemImage: "exclamationmark.triangle")
            MetricCard(title: "Schema", value: state?.schemaVersionText ?? "-", detail: "Core archive schema", systemImage: "square.stack.3d.up")
            MetricCard(title: "Database", value: state?.databaseID ?? "-", detail: "Archive identity", systemImage: "cylinder")
            MetricCard(title: "Server Time", value: DisplayFormat.shortDateTime(state?.serverTime), detail: "Core clock", systemImage: "clock")
            MetricCard(title: "API Contract", value: model.dashboard.apiManifest?.contractVersion ?? "-", detail: "Live manifest version", systemImage: "doc.badge.gearshape")
            MetricCard(title: "Contract Hash", value: model.dashboard.apiManifest?.contractHash ?? "-", detail: "Compatibility fingerprint", systemImage: "number")
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
                OperationEventsTable(events: model.dashboard.operationEvents, selection: .constant(nil))
                    .frame(minHeight: 180)
            }
        }
    }
}
