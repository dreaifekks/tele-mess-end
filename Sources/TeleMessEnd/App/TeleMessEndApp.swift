import AppKit
import SwiftUI
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var shutdownHandler: (@MainActor () async -> Void)?
    var emergencyShutdownHandler: (@MainActor () -> Void)?
    private var terminationReplyPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLog.runtime.info("Application launched")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let shutdownHandler else { return .terminateNow }
        guard !terminationReplyPending else { return .terminateLater }
        terminationReplyPending = true
        Task { @MainActor [weak self, weak sender] in
            await shutdownHandler()
            guard let self, self.terminationReplyPending else { return }
            self.terminationReplyPending = false
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.runtime.info("Application will terminate")
        // Normal termination has already crossed the awaited stop barrier.
        // Keep a last-chance signal for unusual AppKit termination paths.
        emergencyShutdownHandler?()
    }
}

@main
struct TeleMessEndApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        Window("Tele Mess End", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    appDelegate.shutdownHandler = {
                        await model.stopLocalCore()
                    }
                    appDelegate.emergencyShutdownHandler = {
                        model.shutdownLocalCore()
                    }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }

            CommandMenu("Core") {
                Button("Refresh") {
                    Task { await model.refreshCurrentSection() }
                }
                .keyboardShortcut("r")

                Button("Open Console") {
                    model.openConsole()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Validate Profile") {
                    Task { await model.validateActiveProfile() }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

private struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
