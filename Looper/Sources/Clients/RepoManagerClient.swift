import AppKit
import ComposableArchitecture
import Foundation

@DependencyClient
struct RepoManagerClient {
    var createWorkspace: @Sendable (CreateWorkspaceRequest) async throws -> CodingWorkspace
    var removeWorkspace: @Sendable (CodingWorkspace) async throws -> Void
    var revealInFinder: @Sendable (String) async -> Void
}

extension DependencyValues {
    var repoManagerClient: RepoManagerClient {
        get { self[RepoManagerClient.self] }
        set { self[RepoManagerClient.self] = newValue }
    }
}

extension RepoManagerClient: DependencyKey {
    static let liveValue = RepoManagerClient(
        createWorkspace: { request in
            let projectDirectoryPath = try ProjectDirectoryIO.resolveProjectDirectory(
                from: request.repositoryPath
            )

            return CodingWorkspace(
                name: request.name,
                repositoryRootPath: projectDirectoryPath,
                worktreePath: projectDirectoryPath,
                branchName: "",
                baseBranch: "",
                agentCommand: request.agentCommand,
                tmuxSessionName: WorkspaceNaming.tmuxSessionName(
                    repositoryRootPath: projectDirectoryPath,
                    workspaceName: request.name
                )
            )
        },
        removeWorkspace: { workspace in
            _ = try? GitWorkspaceIO.killTmuxSession(named: workspace.tmuxSessionName)

            guard !workspace.launchesProjectDirectoryDirectly else {
                return
            }

            _ = try GitWorkspaceIO.runGit(
                arguments: [
                    "-C",
                    workspace.repositoryRootPath,
                    "worktree",
                    "remove",
                    "--force",
                    workspace.worktreePath,
                ]
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
            throw RepoManagerError(description: "Project directory is required.")
        }

        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        let standardizedPath = URL(fileURLWithPath: expandedPath).standardizedFileURL.path()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedPath, isDirectory: &isDirectory) else {
            throw RepoManagerError(description: "Project directory does not exist.")
        }
        guard isDirectory.boolValue else {
            throw RepoManagerError(description: "Project path must point to a directory.")
        }

        return standardizedPath
    }
}

private enum GitWorkspaceIO {
    static func branchExists(
        _ branchName: String,
        repositoryRootPath: String
    ) throws -> Bool {
        do {
            _ = try runGit(
                arguments: [
                    "-C",
                    repositoryRootPath,
                    "show-ref",
                    "--verify",
                    "--quiet",
                    "refs/heads/\(branchName)",
                ]
            )
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func killTmuxSession(named sessionName: String) throws -> String {
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["tmux", "kill-session", "-t", sessionName]
        )
    }

    @discardableResult
    static func runGit(arguments: [String]) throws -> String {
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git"] + arguments
        )
    }

    @discardableResult
    static func runProcess(
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
            throw RepoManagerError(
                description: error.trimmingCharacters(in: .whitespacesAndNewlines)
                    .ifEmpty(fallback: output.trimmingCharacters(in: .whitespacesAndNewlines))
                    .ifEmpty(fallback: "Command failed with exit code \(process.terminationStatus).")
            )
        }

        return output
    }
}

private struct RepoManagerError: LocalizedError, Sendable {
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
