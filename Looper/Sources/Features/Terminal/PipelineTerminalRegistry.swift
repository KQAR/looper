import AppKit
import Foundation
import GhosttyTerminal
import Observation

@MainActor
@Observable
final class PipelineTerminalRegistry {
    static let shared = PipelineTerminalRegistry()

    private(set) var sessions: [UUID: PipelineTerminalSession] = [:]
    private var eventContinuations: [UUID: AsyncStream<PipelineTerminalEvent>.Continuation] = [:]

    func upsertSession(for pipeline: Pipeline) {
        if let session = sessions[pipeline.id] {
            session.updatePipeline(pipeline)
            return
        }

        sessions[pipeline.id] = PipelineTerminalSession(pipeline: pipeline) { [weak self] event in
            self?.broadcast(event)
        }
    }

    func rebuildSession(for pipeline: Pipeline) {
        sessions[pipeline.id]?.invalidate()
        sessions[pipeline.id] = PipelineTerminalSession(pipeline: pipeline) { [weak self] event in
            self?.broadcast(event)
        }
    }

    func session(id: UUID) -> PipelineTerminalSession? {
        sessions[id]
    }

    func removeSession(id: UUID) {
        sessions.removeValue(forKey: id)?.invalidate()
    }

    func events() -> AsyncStream<PipelineTerminalEvent> {
        AsyncStream { continuation in
            let id = UUID()
            eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.eventContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func broadcast(_ event: PipelineTerminalEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }
}

struct PipelineTerminalEvent: Equatable, Sendable {
    var pipelineID: UUID
    var suggestedTaskStatus: LooperTask.Status?
    var exitCode: Int32?
}

@MainActor
@Observable
final class PipelineTerminalSession: NSObject {
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

    private(set) var pipeline: Pipeline
    private(set) var title: String = ""
    private(set) var surfaceSize: TerminalGridMetrics?
    private(set) var isFocused: Bool = false
    private(set) var phase: Phase = .idle

    let controller: TerminalController
    let configuration: TerminalSurfaceOptions

    private weak var terminalView: AppTerminalView?
    private var attachTask: Task<Void, Never>?
    private var didAttemptAttach = false
    private let eventSink: @MainActor @Sendable (PipelineTerminalEvent) -> Void

    init(
        pipeline: Pipeline,
        eventSink: @escaping @MainActor @Sendable (PipelineTerminalEvent) -> Void
    ) {
        self.pipeline = pipeline
        self.eventSink = eventSink
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
            workingDirectory: pipeline.executionPath,
            context: .window
        )
        super.init()
    }

    var displayTitle: String {
        title.isEmpty ? pipeline.name : title
    }

    func updatePipeline(_ pipeline: Pipeline) {
        self.pipeline = pipeline
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
            pipeline.attachScript + "\n",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        phase = .attached
    }
}

extension PipelineTerminalSession:
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

        guard pipeline.tracksAgentLifecycle else { return }

        let exitCode = consumeExitCode()
        let suggestedTaskStatus: LooperTask.Status = (exitCode ?? 1) == 0 ? .done : .failed
        eventSink(
            PipelineTerminalEvent(
                pipelineID: pipeline.id,
                suggestedTaskStatus: suggestedTaskStatus,
                exitCode: exitCode
            )
        )
    }
}

private extension PipelineTerminalSession {
    func consumeExitCode() -> Int32? {
        let url = pipeline.exitStatusFileURL
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        try? FileManager.default.removeItem(at: url)

        let rawValue = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int32(rawValue)
    }
}
