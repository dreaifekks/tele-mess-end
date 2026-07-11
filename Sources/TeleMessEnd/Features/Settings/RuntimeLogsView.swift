import AppKit
import SwiftUI

private enum RuntimeLogSource: String, CaseIterable, Identifiable {
    case application
    case coreProcess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .application:
            "TeleMessEnd"
        case .coreProcess:
            "Core Process"
        }
    }
}

struct RuntimeLogsView: View {
    @Bindable var appLogs: AppRuntimeLogStore
    @Bindable var localRunner: LocalCoreProcessController
    var showsCoreProcess: Bool
    @State private var source: RuntimeLogSource = .application

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Log source", selection: $source) {
                    Text(RuntimeLogSource.application.title)
                        .tag(RuntimeLogSource.application)
                    if showsCoreProcess {
                        Text(RuntimeLogSource.coreProcess.title)
                            .tag(RuntimeLogSource.coreProcess)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    copyCurrentLog()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .help("Copy visible logs")
                .disabled(!hasContent)

                Button {
                    clearCurrentLog()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Clear visible logs")
                .disabled(!hasContent)
            }

            Group {
                switch source {
                case .application:
                    ApplicationRuntimeLogView(entries: appLogs.entries)
                case .coreProcess:
                    CoreProcessLogView(output: localRunner.lastOutput)
                }
            }
            .frame(minHeight: 135, idealHeight: 155, maxHeight: 190)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            }
        }
        .onChange(of: showsCoreProcess) {
            if !showsCoreProcess {
                source = .application
            }
        }
    }

    private var statusText: String {
        switch source {
        case .application:
            "\(appLogs.entries.count) entries"
        case .coreProcess:
            localRunner.isRunning ? "Running" : "Stopped"
        }
    }

    private var currentText: String {
        switch source {
        case .application:
            appLogs.renderedText
        case .coreProcess:
            localRunner.lastOutput
        }
    }

    private var hasContent: Bool {
        !currentText.isEmpty
    }

    private func copyCurrentLog() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentText, forType: .string)
    }

    private func clearCurrentLog() {
        switch source {
        case .application:
            appLogs.clear()
        case .coreProcess:
            localRunner.clearOutput()
        }
    }
}

private struct ApplicationRuntimeLogView: View {
    var entries: [AppRuntimeLogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                if entries.isEmpty {
                    Text("No application runtime logs yet.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                } else {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(entries) { entry in
                            ApplicationRuntimeLogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(10)
                }
            }
            .onAppear {
                scrollToLatest(using: proxy)
            }
            .onChange(of: entries.last?.id) {
                scrollToLatest(using: proxy)
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let id = entries.last?.id else { return }
        proxy.scrollTo(id, anchor: .bottom)
    }
}

private struct ApplicationRuntimeLogRow: View {
    var entry: AppRuntimeLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(entry.event.timestamp, format: .dateTime.hour().minute().second())
                .foregroundStyle(.secondary)
            Text(entry.event.level.label)
                .foregroundStyle(levelColor)
                .frame(width: 58, alignment: .leading)
            Text("[\(entry.event.category)]")
                .foregroundStyle(.secondary)
            Text(entry.event.message)
                .foregroundStyle(.primary)
        }
        .font(.system(.caption, design: .monospaced))
        .fixedSize(horizontal: true, vertical: false)
        .textSelection(.enabled)
    }

    private var levelColor: Color {
        switch entry.event.level {
        case .debug:
            .secondary
        case .info:
            .primary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

private struct CoreProcessLogView: View {
    var output: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Text(output.isEmpty ? "No Core process output yet." : output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(output.isEmpty ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(10)

                Color.clear
                    .frame(height: 1)
                    .id("core-log-bottom")
            }
            .onAppear {
                proxy.scrollTo("core-log-bottom", anchor: .bottom)
            }
            .onChange(of: output) {
                proxy.scrollTo("core-log-bottom", anchor: .bottom)
            }
        }
    }
}
