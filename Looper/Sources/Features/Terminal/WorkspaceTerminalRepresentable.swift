import AppKit
import GhosttyTerminal
import SwiftUI

@MainActor
struct WorkspaceTerminalRepresentable: NSViewRepresentable {
    let session: WorkspaceTerminalSession

    func makeNSView(context _: Context) -> AppTerminalView {
        let view = AppTerminalView(frame: .zero)
        configure(view)
        return view
    }

    func updateNSView(_ view: AppTerminalView, context _: Context) {
        configure(view)
    }

    private func configure(_ view: AppTerminalView) {
        view.delegate = session
        view.controller = session.controller
        view.configuration = session.configuration
        session.attach(view: view)
    }
}
