import AppKit
import GhosttyTerminal
import os
import SwiftUI

private let logger = Logger(subsystem: "com.looper", category: "TerminalUI")

/// A single NSView that hosts ALL terminal views as subviews.
/// Terminals are created once and NEVER reparented — visibility is controlled via `isHidden`.
/// This avoids ghostty's `viewDidMoveToWindow(nil)` → `freeSurface()` → PTY kill cycle.
@MainActor
final class TerminalHostView: NSView {
    private var activeSessionID: UUID?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func addTerminal(_ terminal: AppTerminalView) {
        terminal.isHidden = true
        addSubview(terminal)
    }

    func showTerminal(for sessionID: UUID?, registry: PipelineTerminalRegistry) {
        let oldID = activeSessionID
        activeSessionID = sessionID

        // Hide previously active terminal
        if oldID != sessionID, let oldID,
           let oldSession = registry.session(id: oldID)
        {
            oldSession.persistentTerminal?.isHidden = true
        }

        // Hide all if no session
        guard let sessionID,
              let session = registry.session(id: sessionID),
              let terminal = session.persistentTerminal
        else {
            // Hide all terminals when no session active
            for (_, s) in registry.sessions {
                s.persistentTerminal?.isHidden = true
            }
            return
        }

        terminal.isHidden = false
        terminal.frame = bounds
        window?.makeFirstResponder(terminal)
        logger.info("[Host] showing terminal for \(session.pipeline.name), bounds=\(self.bounds.width)x\(self.bounds.height)")
    }

    override func layout() {
        super.layout()
        for subview in subviews where !subview.isHidden {
            subview.frame = bounds
        }
    }
}

@MainActor
struct TerminalHostRepresentable: NSViewRepresentable {
    let registry: PipelineTerminalRegistry
    let activeSessionID: UUID?

    func makeNSView(context _: Context) -> TerminalHostView {
        let host = TerminalHostView(frame: .zero)
        logger.info("[Host] makeNSView: setting terminal host")
        registry.setTerminalHost(host)
        return host
    }

    func updateNSView(_ host: TerminalHostView, context _: Context) {
        host.showTerminal(for: activeSessionID, registry: registry)
    }
}
