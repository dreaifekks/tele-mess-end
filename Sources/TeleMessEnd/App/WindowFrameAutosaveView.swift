import AppKit
import SwiftUI

struct WindowFrameAutosaveView: NSViewRepresentable {
    var autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(for: nsView)
    }

    private func configureWindow(for view: NSView) {
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(autosaveName)
        }
    }
}
