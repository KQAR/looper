import AppKit
import Foundation
import GhosttyTerminal
import Observation
import os

private let logger = Logger(subsystem: "com.looper", category: "Terminal")

@MainActor
@Observable
final class PipelineTerminalRegistry {
    static let shared = PipelineTerminalRegistry()

    /// Pipeline-level sessions (default shell per pipeline)
    private(set) var sessions: [UUID: PipelineTerminalSession] = [:]
    /// Run-level sessions (one per active run, keyed by Run.ID)
    private(set) var runSessions: [UUID: PipelineTerminalSession] = [:]
    private(set) var terminalHost: TerminalHostView?
    private var eventContinuations: [UUID: AsyncStream<PipelineTerminalEvent>.Continuation] = [:]

    func setTerminalHost(_ host: TerminalHostView) {
        guard terminalHost == nil else {
            logger.info("[Registry] terminalHost already set, ignoring duplicate")
            return
        }
        terminalHost = host
        logger.info("[Registry] terminalHost set, sessions=\(self.sessions.count)")

        // Defer terminal creation until the host is in a window
        // (SwiftUI calls makeNSView before adding to window)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            logger.info("[Registry] deferred terminal creation, hostInWindow=\(host.window != nil)")
            for (id, session) in self.sessions {
                logger.info("[Registry] creating persistent terminal for pipeline \(id.uuidString.prefix(8))")
                session.createPersistentTerminalIfNeeded(in: host)
            }
            for (id, session) in self.runSessions {
                logger.info("[Registry] creating persistent terminal for run \(id.uuidString.prefix(8))")
                session.createPersistentTerminalIfNeeded(in: host)
            }
        }
    }

    func upsertSession(for pipeline: Pipeline) {
        if let session = sessions[pipeline.id] {
            session.updatePipeline(pipeline)
            return
        }

        let session = PipelineTerminalSession(pipeline: pipeline) { [weak self] event in
            self?.broadcast(event)
        }
        sessions[pipeline.id] = session

        if let terminalHost, terminalHost.window != nil {
            session.createPersistentTerminalIfNeeded(in: terminalHost)
        }
    }

    func rebuildSession(for pipeline: Pipeline) {
        sessions[pipeline.id]?.invalidate()
        let session = PipelineTerminalSession(pipeline: pipeline) { [weak self] event in
            self?.broadcast(event)
        }
        sessions[pipeline.id] = session

        if let terminalHost, terminalHost.window != nil {
            session.createPersistentTerminalIfNeeded(in: terminalHost)
        }
    }

    func session(id: UUID) -> PipelineTerminalSession? {
        sessions[id]
    }

    func removeSession(id: UUID) {
        sessions.removeValue(forKey: id)?.invalidate()
    }

    // MARK: - Run Sessions

    func upsertRunSession(runID: UUID, pipeline: Pipeline, executionPath: String) {
        if runSessions[runID] != nil { return }

        var runPipeline = pipeline
        runPipeline.executionPath = executionPath

        let session = PipelineTerminalSession(
            pipeline: runPipeline,
            runID: runID
        ) { [weak self] event in
            self?.broadcast(event)
        }
        runSessions[runID] = session

        if let terminalHost, terminalHost.window != nil {
            session.createPersistentTerminalIfNeeded(in: terminalHost)
        }
    }

    func runSession(id: UUID) -> PipelineTerminalSession? {
        runSessions[id]
    }

    func removeRunSession(id: UUID) {
        runSessions.removeValue(forKey: id)?.invalidate()
    }

    /// All active run sessions for a given pipeline
    func runSessions(forPipeline pipelineID: UUID) -> [UUID: PipelineTerminalSession] {
        runSessions.filter { $0.value.pipeline.id == pipelineID }
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
    var runID: UUID?
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
    let runID: UUID?
    private(set) var title: String = ""
    private(set) var surfaceSize: TerminalGridMetrics?
    private(set) var isFocused: Bool = false
    private(set) var phase: Phase = .idle
    private(set) var persistentTerminal: AppTerminalView?
    private(set) var shouldAttachWhenReady = false

    let controller: TerminalController
    let configuration: TerminalSurfaceOptions

    private weak var terminalView: AppTerminalView?
    private var attachTask: Task<Void, Never>?
    private var didAttemptAttach = false
    private let eventSink: @MainActor @Sendable (PipelineTerminalEvent) -> Void

    init(
        pipeline: Pipeline,
        runID: UUID? = nil,
        eventSink: @escaping @MainActor @Sendable (PipelineTerminalEvent) -> Void
    ) {
        self.pipeline = pipeline
        self.runID = runID
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

    func createPersistentTerminalIfNeeded(in hostView: TerminalHostView) {
        guard persistentTerminal == nil else {
            logger.info("[Session:\(self.pipeline.name)] persistentTerminal already exists, skipping")
            return
        }
        let terminal = AppTerminalView(
            frame: NSRect(origin: .zero, size: CGSize(width: 640, height: 400))
        )
        terminal.delegate = self
        terminal.controller = controller
        terminal.configuration = configuration
        persistentTerminal = terminal
        terminalView = terminal

        // Add to host — terminal stays here forever, visibility controlled by isHidden
        hostView.addTerminal(terminal)

        logger.info("[Session:\(self.pipeline.name)] persistentTerminal created, inWindow=\(terminal.window != nil), shouldAttach=\(self.shouldAttachWhenReady)")

        if shouldAttachWhenReady {
            logger.info("[Session:\(self.pipeline.name)] auto-attaching (shouldAttachWhenReady=true)")
            scheduleAttachIfNeeded()
        }
    }

    func markShouldAttach() {
        shouldAttachWhenReady = true
        let hasTerminal = persistentTerminal != nil
        logger.info("[Session:\(self.pipeline.name)] markShouldAttach, hasTerminal=\(hasTerminal), didAttemptAttach=\(self.didAttemptAttach)")
        if hasTerminal {
            scheduleAttachIfNeeded()
        }
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
        persistentTerminal?.removeFromSuperview()
        persistentTerminal = nil
        terminalView = nil
    }

    private func scheduleAttachIfNeeded() {
        guard !didAttemptAttach else {
            logger.info("[Session:\(self.pipeline.name)] scheduleAttach skipped (already attempted)")
            return
        }
        guard terminalView != nil else {
            logger.warning("[Session:\(self.pipeline.name)] scheduleAttach skipped (no terminalView)")
            return
        }

        didAttemptAttach = true
        phase = .bootstrapping
        logger.info("[Session:\(self.pipeline.name)] scheduling attach script (450ms delay)")

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
            logger.warning("[Session:\(self.pipeline.name)] sendAttachScript failed (no terminalView)")
            didAttemptAttach = false
            phase = .idle
            return
        }

        let inWindow = terminalView.window != nil
        let script = pipeline.attachScript
        logger.info("[Session:\(self.pipeline.name)] sending attach script, inWindow=\(inWindow), scriptLen=\(script.count)")
        logger.debug("[Session:\(self.pipeline.name)] script=\(script)")

        terminalView.window?.makeFirstResponder(terminalView)
        terminalView.insertText(
            script + "\n",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        phase = .attached
        logger.info("[Session:\(self.pipeline.name)] attach script sent, phase=attached")
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
                runID: runID,
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
