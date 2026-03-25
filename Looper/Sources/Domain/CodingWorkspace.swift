import Foundation

struct CodingWorkspace: Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var repositoryRootPath: String
    var worktreePath: String
    var branchName: String
    var baseBranch: String
    var agentCommand: String
    var tmuxSessionName: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        repositoryRootPath: String,
        worktreePath: String,
        branchName: String,
        baseBranch: String,
        agentCommand: String,
        tmuxSessionName: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.repositoryRootPath = repositoryRootPath
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.baseBranch = baseBranch
        self.agentCommand = agentCommand
        self.tmuxSessionName = tmuxSessionName
        self.createdAt = createdAt
    }

    var repositoryRootURL: URL {
        URL(fileURLWithPath: repositoryRootPath)
    }

    var worktreeURL: URL {
        URL(fileURLWithPath: worktreePath)
    }

    var worktreeDirectoryName: String {
        worktreeURL.lastPathComponent
    }

    var attachScript: String {
        let escapedWorktree = worktreePath.shellQuoted
        let escapedSession = tmuxSessionName.shellQuoted
        let command = agentCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        if command.isEmpty {
            return """
            if command -v tmux >/dev/null 2>&1; then
              tmux new-session -A -s \(escapedSession) -c \(escapedWorktree)
            else
              cd \(escapedWorktree)
            fi
            """
        }

        let launchScript = "cd \(escapedWorktree) && \(command)"
        let escapedLaunchScript = launchScript.shellQuoted

        return """
        if command -v tmux >/dev/null 2>&1; then
          tmux has-session -t \(escapedSession) 2>/dev/null || tmux new-session -d -s \(escapedSession) -c \(escapedWorktree) \(escapedLaunchScript)
          tmux attach-session -t \(escapedSession)
        else
          \(launchScript)
        fi
        """
    }
}

struct WorkspaceDraft: Equatable, Sendable {
    var name: String = ""
    var repositoryPath: String = ""
    var baseBranch: String = "HEAD"
    var branchName: String = ""
    var agentCommand: String = "claude"

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRepositoryPath: String {
        repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedBaseBranch: String {
        let value = baseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "HEAD" : value
    }

    var trimmedBranchName: String {
        branchName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAgentCommand: String {
        agentCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var inferredBranchName: String {
        WorkspaceNaming.branchName(
            name: trimmedName,
            explicitBranchName: trimmedBranchName
        )
    }

    var canCreate: Bool {
        !trimmedName.isEmpty && !trimmedRepositoryPath.isEmpty
    }
}

struct CreateWorkspaceRequest: Equatable, Sendable {
    var name: String
    var repositoryPath: String
    var baseBranch: String
    var branchName: String
    var agentCommand: String

    init(draft: WorkspaceDraft) {
        self.name = draft.trimmedName
        self.repositoryPath = draft.trimmedRepositoryPath
        self.baseBranch = draft.trimmedBaseBranch
        self.branchName = draft.inferredBranchName
        self.agentCommand = draft.trimmedAgentCommand
    }
}

enum WorkspaceNaming {
    static func slug(_ rawValue: String, fallback: String = "workspace") -> String {
        let folded = rawValue.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )
        let replaced = folded.replacingOccurrences(
            of: #"[^a-zA-Z0-9._-]+"#,
            with: "-",
            options: .regularExpression
        )
        let collapsed = replaced.replacingOccurrences(
            of: #"-{2,}"#,
            with: "-",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(
            in: CharacterSet(charactersIn: "-._")
        )
        return trimmed.isEmpty ? fallback : trimmed.lowercased()
    }

    static func branchName(name: String, explicitBranchName: String) -> String {
        let explicit = explicitBranchName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !explicit.isEmpty else {
            return "looper/\(slug(name, fallback: "workspace"))"
        }

        let sanitizedComponents = explicit
            .split(separator: "/")
            .map { slug(String($0), fallback: "workspace") }
            .filter { !$0.isEmpty }

        if sanitizedComponents.isEmpty {
            return "looper/\(slug(name, fallback: "workspace"))"
        }

        let normalized = sanitizedComponents.joined(separator: "/")
        return normalized.contains("/")
            ? normalized
            : "looper/\(normalized)"
    }

    static func tmuxSessionName(
        repositoryRootPath: String,
        branchName: String
    ) -> String {
        let repoName = URL(fileURLWithPath: repositoryRootPath).lastPathComponent
        let branch = branchName.replacingOccurrences(of: "/", with: "-")
        return slug("\(repoName)-\(branch)", fallback: "looper-session")
    }

    static func worktreeContainerURL(for repositoryRootPath: String) -> URL {
        let repositoryRoot = URL(fileURLWithPath: repositoryRootPath)
        return repositoryRoot
            .deletingLastPathComponent()
            .appendingPathComponent(".looper-worktrees", isDirectory: true)
            .appendingPathComponent(repositoryRoot.lastPathComponent, isDirectory: true)
    }

    static func uniqueWorktreeURL(
        repositoryRootPath: String,
        preferredName: String,
        fileManager: FileManager = .default
    ) -> URL {
        let container = worktreeContainerURL(for: repositoryRootPath)
        let baseName = slug(preferredName, fallback: "workspace")

        var attempt = 0
        while true {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let candidate = container.appendingPathComponent(
                "\(baseName)\(suffix)",
                isDirectory: true
            )
            if !fileManager.fileExists(atPath: candidate.path()) {
                return candidate
            }
            attempt += 1
        }
    }
}

extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
