import AppKit
import ComposableArchitecture
import Foundation

@DependencyClient
struct PipelineManagerClient {
    var createPipeline: @Sendable (CreatePipelineRequest) async throws -> Pipeline
    var removePipeline: @Sendable (Pipeline) async throws -> Void
    var revealInFinder: @Sendable (String) async -> Void
}

extension DependencyValues {
    var pipelineManagerClient: PipelineManagerClient {
        get { self[PipelineManagerClient.self] }
        set { self[PipelineManagerClient.self] = newValue }
    }
}

extension PipelineManagerClient: DependencyKey {
    static let liveValue = PipelineManagerClient(
        createPipeline: { request in
            let projectDirectoryPath = try ProjectDirectoryIO.resolveProjectDirectory(
                from: request.projectPath
            )

            return Pipeline(
                name: request.name,
                projectPath: projectDirectoryPath,
                executionPath: projectDirectoryPath,
                agentCommand: request.agentCommand,
                tmuxSessionName: PipelineNaming.tmuxSessionName(
                    projectPath: projectDirectoryPath,
                    pipelineName: request.name
                )
            )
        },
        removePipeline: { pipeline in
            _ = try? ProcessIO.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["tmux", "kill-session", "-t", pipeline.tmuxSessionName]
            )
        },
        revealInFinder: { path in
            await MainActor.run {
                _ = NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            }
        }
    )
}

private enum ProjectDirectoryIO {
    static func resolveProjectDirectory(from path: String) throws -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw PipelineManagerError(description: "Project directory is required.")
        }

        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        let standardizedPath = URL(fileURLWithPath: expandedPath).standardizedFileURL.path()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedPath, isDirectory: &isDirectory) else {
            throw PipelineManagerError(description: "Project directory does not exist.")
        }
        guard isDirectory.boolValue else {
            throw PipelineManagerError(description: "Project path must point to a directory.")
        }

        return standardizedPath
    }
}

private enum ProcessIO {
    @discardableResult
    static func run(
        executableURL: URL,
        arguments: [String]
    ) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let error = String(decoding: errorData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw PipelineManagerError(
                description: error.trimmingCharacters(in: .whitespacesAndNewlines)
                    .ifEmpty(fallback: output.trimmingCharacters(in: .whitespacesAndNewlines))
                    .ifEmpty(fallback: "Command failed with exit code \(process.terminationStatus).")
            )
        }

        return output
    }
}

private struct PipelineManagerError: LocalizedError, Sendable {
    let description: String

    var errorDescription: String? {
        description
    }
}

private extension String {
    func ifEmpty(fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
