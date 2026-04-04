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

// MARK: - Live manager

private actor AgentProcessLiveManager {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func execute(_ request: AgentProcessRequest) -> AsyncStream<AgentEvent> {
        // Cancel any existing run with same ID
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

    // MARK: - Process execution

    @concurrent
    private static func run(
        request: AgentProcessRequest,
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async {
        let args = buildArguments(for: request)

        logger.info("[AgentProcess:\(request.runID.uuidString.prefix(8))] launching: claude \(args.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: request.workingDirectory)
        process.environment = buildEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            logger.error("[AgentProcess:\(request.runID.uuidString.prefix(8))] failed to launch: \(error)")
            continuation.yield(.result(AgentResult(
                sessionID: "",
                isError: true,
                durationMs: 0,
                costUSD: 0,
                numTurns: 0,
                resultText: "Failed to launch agent: \(error.localizedDescription)"
            )))
            continuation.finish()
            return
        }

        // Read stdout line by line, parse JSONL
        let handle = stdoutPipe.fileHandleForReading
        do {
            for try await line in handle.bytes.lines {
                if Task.isCancelled {
                    process.terminate()
                    break
                }
                if let event = AgentStreamParser.parse(line) {
                    continuation.yield(event)
                }
            }
        } catch {
            logger.error("[AgentProcess:\(request.runID.uuidString.prefix(8))] read error: \(error)")
        }

        process.waitUntilExit()

        let exitCode = process.terminationStatus
        logger.info("[AgentProcess:\(request.runID.uuidString.prefix(8))] exited with code \(exitCode)")

        // If no result event was received (e.g. process killed), synthesize one
        if Task.isCancelled {
            continuation.yield(.result(AgentResult(
                sessionID: "",
                isError: true,
                durationMs: 0,
                costUSD: 0,
                numTurns: 0,
                resultText: "Agent was cancelled"
            )))
        }

        continuation.finish()
    }

    private static func buildArguments(for request: AgentProcessRequest) -> [String] {
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--dangerously-skip-permissions",
        ]

        // Parse extra flags from agentCommand (e.g. "claude --model sonnet" → ["--model", "sonnet"])
        let commandParts = request.agentCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        // Skip the binary name (first component), keep the rest as extra args
        if commandParts.count > 1 {
            args.append(contentsOf: Array(commandParts.dropFirst()))
        }

        if let sessionID = request.resumeSessionID, !sessionID.isEmpty {
            args.append(contentsOf: ["--resume", sessionID])
        }

        // Task prompt as positional argument
        args.append("--")
        args.append(request.taskDescription)

        return args
    }

    private static func buildEnvironment() -> [String: String] {
        // Inherit current environment, ensure PATH includes common locations
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let missing = extraPaths.filter { !currentPath.contains($0) }
        if !missing.isEmpty {
            env["PATH"] = (missing + [currentPath]).joined(separator: ":")
        }
        return env
    }
}
