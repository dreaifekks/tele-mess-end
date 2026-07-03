import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct TeleMessEndApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Tele Mess End", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 640)
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
