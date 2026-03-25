import AppKit
import Foundation
import GhosttyTerminal
import Observation

@MainActor
@Observable
final class WorkspaceTerminalRegistry {
    static let shared = WorkspaceTerminalRegistry()

    private(set) var sessions: [UUID: WorkspaceTerminalSession] = [:]

    func upsertSession(for workspace: CodingWorkspace) {
        if let session = sessions[workspace.id] {
            session.updateWorkspace(workspace)
            return
        }

        sessions[workspace.id] = WorkspaceTerminalSession(workspace: workspace)
    }

    func rebuildSession(for workspace: CodingWorkspace) {
        sessions[workspace.id]?.invalidate()
        sessions[workspace.id] = WorkspaceTerminalSession(workspace: workspace)
    }

    func session(id: UUID) -> WorkspaceTerminalSession? {
        sessions[id]
    }

    func removeSession(id: UUID) {
        sessions.removeValue(forKey: id)?.invalidate()
    }
}

@MainActor
@Observable
final class WorkspaceTerminalSession: NSObject {
    enum Phase: Equatable {
        case idle
        case bootstrapping
        case attached
        case terminated

        var label: String {
            switch self {
            case .idle:
                "Idle"
            case .bootstrapping:
                "Attaching"
            case .attached:
                "Attached"
            case .terminated:
                "Closed"
            }
        }
    }

    private(set) var workspace: CodingWorkspace
    private(set) var title: String = ""
    private(set) var surfaceSize: TerminalGridMetrics?
    private(set) var isFocused: Bool = false
    private(set) var phase: Phase = .idle

    let controller: TerminalController
    let configuration: TerminalSurfaceOptions

    private weak var terminalView: AppTerminalView?
    private var attachTask: Task<Void, Never>?
    private var didAttemptAttach = false

    init(workspace: CodingWorkspace) {
        self.workspace = workspace
        self.controller = TerminalController { configuration in
            configuration.withFontSize(13)
            configuration.withBackgroundOpacity(0.92)
            configuration.withBackgroundBlur(18)
            configuration.withWindowPaddingX(10)
            configuration.withWindowPaddingY(8)
        }
        self.configuration = TerminalSurfaceOptions(
            backend: .exec,
            fontSize: 13,
            workingDirectory: workspace.worktreePath,
            context: .window
        )
        super.init()
    }

    var displayTitle: String {
        title.isEmpty ? workspace.name : title
    }

    func updateWorkspace(_ workspace: CodingWorkspace) {
        self.workspace = workspace
    }

    func attach(view: AppTerminalView) {
        terminalView = view
        scheduleAttachIfNeeded()
    }

    func focus() {
        guard let terminalView else { return }
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func scheduleAttach() {
        didAttemptAttach = false
        phase = .idle
        scheduleAttachIfNeeded()
    }

    func invalidate() {
        attachTask?.cancel()
        attachTask = nil
        terminalView = nil
    }

    private func scheduleAttachIfNeeded() {
        guard !didAttemptAttach else { return }
        guard terminalView != nil else { return }

        didAttemptAttach = true
        phase = .bootstrapping

        attachTask?.cancel()
        attachTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            await MainActor.run {
                self?.sendAttachScript()
            }
        }
    }

    private func sendAttachScript() {
        guard let terminalView else {
            didAttemptAttach = false
            phase = .idle
            return
        }

        terminalView.window?.makeFirstResponder(terminalView)
        terminalView.insertText(
            workspace.attachScript + "\n",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        phase = .attached
    }
}

extension WorkspaceTerminalSession:
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceGridResizeDelegate,
    TerminalSurfaceFocusDelegate,
    TerminalSurfaceCloseDelegate
{
    func terminalDidChangeTitle(_ title: String) {
        self.title = title
    }

    func terminalDidResize(_ size: TerminalGridMetrics) {
        surfaceSize = size
    }

    func terminalDidChangeFocus(_ focused: Bool) {
        isFocused = focused
    }

    func terminalDidClose(processAlive _: Bool) {
        phase = .terminated
        didAttemptAttach = false
    }
}
