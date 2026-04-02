import ComposableArchitecture
import Foundation

@DependencyClient
struct GitWorktreeClient {
    var createWorktree: @Sendable (_ projectPath: String, _ branchName: String) async throws -> String
    var removeWorktree: @Sendable (_ projectPath: String, _ worktreePath: String) async throws -> Void
    var writeTaskContext: @Sendable (_ worktreePath: String, _ task: LooperTask) async throws -> Void
}

extension DependencyValues {
    var gitWorktreeClient: GitWorktreeClient {
        get { self[GitWorktreeClient.self] }
        set { self[GitWorktreeClient.self] = newValue }
    }
}

extension GitWorktreeClient: DependencyKey {
    static let liveValue = GitWorktreeClient(
        createWorktree: { projectPath, branchName in
            try GitWorktreeIO.createWorktree(
                projectPath: projectPath,
                branchName: branchName
            )
        },
        removeWorktree: { projectPath, worktreePath in
            try GitWorktreeIO.removeWorktree(
                projectPath: projectPath,
                worktreePath: worktreePath
            )
        },
        writeTaskContext: { worktreePath, task in
            try GitWorktreeIO.writeTaskContext(
                worktreePath: worktreePath,
                task: task
            )
        }
    )

    static let testValue = GitWorktreeClient(
        createWorktree: { _, _ in "/tmp/test-worktree" },
        removeWorktree: { _, _ in },
        writeTaskContext: { _, _ in }
    )
}

private enum GitWorktreeIO {
    static func createWorktree(
        projectPath: String,
        branchName: String
    ) throws -> String {
        let worktreeDir = worktreeBasePath(for: projectPath)
        try FileManager.default.createDirectory(
            atPath: worktreeDir,
            withIntermediateDirectories: true
        )

        let worktreePath = (worktreeDir as NSString)
            .appendingPathComponent(branchName)

        let baseBranch = try detectDefaultBranch(projectPath: projectPath)

        do {
            try runGit(
                in: projectPath,
                args: ["worktree", "add", "-b", branchName, worktreePath, baseBranch]
            )
        } catch {
            // Branch name collision — append timestamp and retry
            let fallbackBranch = "\(branchName)-\(Int(Date().timeIntervalSince1970))"
            try runGit(
                in: projectPath,
                args: ["worktree", "add", "-b", fallbackBranch, worktreePath, baseBranch]
            )
        }

        return worktreePath
    }

    static func removeWorktree(
        projectPath: String,
        worktreePath: String
    ) throws {
        try runGit(
            in: projectPath,
            args: ["worktree", "remove", "--force", worktreePath]
        )
    }

    static func writeTaskContext(
        worktreePath: String,
        task: LooperTask
    ) throws {
        let content = """
        # Task Context

        **ID**: \(task.id)
        **Title**: \(task.title)
        **Source**: \(task.source)

        ## Description

        \(task.summary)
        """

        let taskMDPath = (worktreePath as NSString).appendingPathComponent("TASK.md")
        try content.write(toFile: taskMDPath, atomically: true, encoding: .utf8)
    }

    private static func worktreeBasePath(for projectPath: String) -> String {
        let projectName = (projectPath as NSString).lastPathComponent
        let base = NSTemporaryDirectory() as NSString
        return base.appendingPathComponent("looper-worktrees/\(projectName)")
    }

    private static func detectDefaultBranch(projectPath: String) throws -> String {
        if let output = try? runGit(
            in: projectPath,
            args: ["symbolic-ref", "refs/remotes/origin/HEAD"]
        ) {
            let ref = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if ref.hasPrefix("refs/remotes/") {
                return String(ref.dropFirst("refs/remotes/".count))
            }
        }

        for branch in ["origin/main", "origin/master"] {
            if (try? runGit(
                in: projectPath,
                args: ["rev-parse", "--verify", branch]
            )) != nil {
                return branch
            }
        }

        return "HEAD"
    }

    @discardableResult
    private static func runGit(in directory: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(
            decoding: stdout.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )

        guard process.terminationStatus == 0 else {
            let errorOutput = String(
                decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw GitWorktreeError(
                description: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                    ? "git command failed with exit code \(process.terminationStatus)"
                    : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return output
    }
}

private struct GitWorktreeError: LocalizedError, Sendable {
    let description: String
    var errorDescription: String? { description }
}
