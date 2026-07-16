import ComposableArchitecture
import Foundation
import os

private let logger = Logger(subsystem: "com.looper", category: "AgentProcess")

struct AgentProcessRequest: Sendable, Equatable {
    var runID: UUID
    var workingDirectory: String
    var taskDescription: String
    var agentCommand: String
    var resumeSessionID: String?
    /// Absolute path for the agent binary from the environment check
    /// (ExecutableResolver) — lets a bare "claude" command launch even when
    /// the binary lives outside the GUI process PATH.
    var resolvedExecutablePath: String?
    /// When set, formatted agent events are appended here so the run
    /// terminal can tail them live.
    var logPath: String?
}

@DependencyClient
struct AgentProcessClient {
    var execute: @Sendable (AgentProcessRequest) async -> AsyncStream<AgentEvent> = { _ in
        AsyncStream { $0.finish() }
    }
    var cancel: @Sendable (_ runID: UUID) async -> Void
}

extension DependencyValues {
    var agentProcessClient: AgentProcessClient {
        get { self[AgentProcessClient.self] }
        set { self[AgentProcessClient.self] = newValue }
    }
}

extension AgentProcessClient: DependencyKey {
    static let liveValue: AgentProcessClient = {
        let manager = AgentProcessLiveManager()
        return AgentProcessClient(
            execute: { request in await manager.execute(request) },
            cancel: { runID in await manager.cancel(runID) }
        )
    }()

    static let testValue = AgentProcessClient(
        execute: { _ in AsyncStream { $0.finish() } },
        cancel: { _ in }
    )
}

private actor AgentProcessLiveManager {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func execute(_ request: AgentProcessRequest) -> AsyncStream<AgentEvent> {
        tasks[request.runID]?.cancel()

        let (stream, continuation) = AsyncStream<AgentEvent>.makeStream()

        let task = Task.detached { [weak self] in
            await Self.run(request: request, continuation: continuation)
            await self?.removeTask(request.runID)
        }

        tasks[request.runID] = task

        continuation.onTermination = { [weak self] _ in
            task.cancel()
            Task { await self?.removeTask(request.runID) }
        }

        return stream
    }

    func cancel(_ runID: UUID) {
        tasks[runID]?.cancel()
        tasks.removeValue(forKey: runID)
    }

    private func removeTask(_ runID: UUID) {
        tasks.removeValue(forKey: runID)
    }

    @concurrent
    private static func run(
        request: AgentProcessRequest,
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async {
        do {
            let configuration = AgentCommandConfiguration(request: request)
            if configuration.ignoredArguments.isEmpty == false {
                logger.warning(
                    "[AgentProcess:\(request.runID.uuidString.prefix(8))] ignored agent command arguments: \(configuration.ignoredArguments.joined(separator: " "))"
                )
            }

            logger.info(
                "[AgentProcess:\(request.runID.uuidString.prefix(8))] launching via SDK: \(configuration.executableDescription)"
            )

            let runLog = RunLogWriter(path: request.logPath)
            runLog.writeHeader(command: configuration.executableDescription)

            let query = try ClaudeAgentSDK.query(
                prompt: request.taskDescription,
                options: configuration.optionsWithStderrLogger(runID: request.runID)
            )

            var didReceiveResult = false

            try await withTaskCancellationHandler {
                defer { query.close() }

                for try await message in query {
                    for event in AgentSDKMessageMapper.events(from: message) {
                        if case .result = event {
                            didReceiveResult = true
                        }
                        runLog.write(event)
                        continuation.yield(event)
                    }
                }
            } onCancel: {
                query.close()
            }

            if Task.isCancelled {
                continuation.yield(cancelledResult())
            } else if didReceiveResult == false {
                logger.error("[AgentProcess:\(request.runID.uuidString.prefix(8))] completed without a result event")
                continuation.yield(errorResult("Agent exited without producing a result"))
            }
        } catch {
            if Task.isCancelled {
                continuation.yield(cancelledResult())
            } else {
                logger.error("[AgentProcess:\(request.runID.uuidString.prefix(8))] failed: \(String(describing: error), privacy: .public)")
                continuation.yield(errorResult("Agent failed: \(String(describing: error))"))
            }
        }

        continuation.finish()
    }
}

private extension AgentCommandConfiguration {
    func optionsWithStderrLogger(runID: UUID) -> Options {
        var options = self.options
        options.stderr = { stderr in
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }
            logger.debug("[AgentProcess:\(runID.uuidString.prefix(8))][stderr] \(message, privacy: .public)")
        }
        return options
    }
}

/// Appends human-readable agent events to the run log so the run terminal
/// (which tails this file) shows the agent working live. Best-effort:
/// logging must never fail the run.
private struct RunLogWriter: Sendable {
    private let path: String?

    init(path: String?) {
        self.path = path
        guard let path else { return }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
    }

    func writeHeader(command: String) {
        append("\u{1B}[2m── run started · \(command) ──\u{1B}[0m\n")
    }

    func write(_ event: AgentEvent) {
        switch event {
        case let .initialized(sessionID, model):
            append("\u{1B}[2msession \(sessionID) · \(model)\u{1B}[0m\n")

        case let .toolUse(name, inputSummary):
            let summary = inputSummary.isEmpty ? name : "\(name) \(inputSummary)"
            append("\u{1B}[36m→ \(summary)\u{1B}[0m\n")

        case let .toolResult(isError):
            if isError {
                append("\u{1B}[31m✗ tool call failed\u{1B}[0m\n")
            }

        case let .text(text):
            append(text.hasSuffix("\n") ? text : text + "\n")

        case let .result(result):
            let seconds = Double(result.durationMs) / 1000
            let verdict = result.isError ? "\u{1B}[31mfailed\u{1B}[0m" : "\u{1B}[32msucceeded\u{1B}[0m"
            append(
                "\u{1B}[2m── run \u{1B}[0m\(verdict)\u{1B}[2m · \(String(format: "%.0f", seconds))s · $\(String(format: "%.4f", result.costUSD)) · \(result.numTurns) turns ──\u{1B}[0m\n"
            )
            if result.isError, !result.resultText.isEmpty {
                append("\u{1B}[31m\(result.resultText)\u{1B}[0m\n")
            }
        }
    }

    private func append(_ text: String) {
        guard let path else { return }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }
}

private func cancelledResult() -> AgentEvent {
    .result(errorResultPayload("Agent was cancelled"))
}

private func errorResult(_ message: String) -> AgentEvent {
    .result(errorResultPayload(message))
}

private func errorResultPayload(_ message: String) -> AgentResult {
    AgentResult(
        sessionID: "",
        isError: true,
        durationMs: 0,
        costUSD: 0,
        numTurns: 0,
        resultText: message
    )
}
