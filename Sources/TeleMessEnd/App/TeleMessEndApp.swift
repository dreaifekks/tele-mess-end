import AppKit
import SwiftUI

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
