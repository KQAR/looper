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
                logger.error("[AgentProcess:\(request.runID.uuidString.prefix(8))] failed: \(String(describing: error))")
                continuation.yield(errorResult("Failed to launch agent: \(error.localizedDescription)"))
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
            logger.debug("[AgentProcess:\(runID.uuidString.prefix(8))][stderr] \(message)")
        }
        return options
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
