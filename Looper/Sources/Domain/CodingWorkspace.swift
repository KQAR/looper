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

    var exitStatusFileURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "looper-workspace-\(id.uuidString)-exit-status")
    }

    var tracksAgentLifecycle: Bool {
        !agentCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var launchesProjectDirectoryDirectly: Bool {
        repositoryRootPath == worktreePath
            && branchName.isEmpty
            && baseBranch.isEmpty
    }

    var attachScript: String {
        let escapedWorktree = worktreePath.shellQuoted
        let escapedSession = tmuxSessionName.shellQuoted
        let command = agentCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedStatusFile = exitStatusFileURL.path.shellQuoted

        if command.isEmpty {
            return """
            if command -v tmux >/dev/null 2>&1; then
              tmux new-session -A -s \(escapedSession) -c \(escapedWorktree)
            else
              cd \(escapedWorktree)
            fi
            """
        }

        let wrappedLaunchScript = """
        rm -f \(escapedStatusFile)
        cd \(escapedWorktree) && \(command)
        status=$?
        printf '%s' "$status" > \(escapedStatusFile)
        exit "$status"
        """
        let escapedWrappedLaunchScript = wrappedLaunchScript.shellQuoted

        return """
        if command -v tmux >/dev/null 2>&1; then
          tmux has-session -t \(escapedSession) 2>/dev/null || tmux new-session -d -s \(escapedSession) -c \(escapedWorktree) /bin/zsh -lc \(escapedWrappedLaunchScript)
          tmux attach-session -t \(escapedSession)
        else
          /bin/zsh -lc \(escapedWrappedLaunchScript)
        fi
        """
    }
}

struct WorkspaceDraft: Equatable, Sendable {
    var name: String = ""
    var repositoryPath: String = ""
    var agentCommand: String = "claude"

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRepositoryPath: String {
        repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAgentCommand: String {
        agentCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var inferredName: String {
        let explicitName = trimmedName
        guard !explicitName.isEmpty else {
            let lastPathComponent = URL(fileURLWithPath: trimmedRepositoryPath).lastPathComponent
            return lastPathComponent.isEmpty ? "Workspace" : lastPathComponent
        }
        return explicitName
    }

    var canCreate: Bool {
        !trimmedRepositoryPath.isEmpty
    }
}

struct CreateWorkspaceRequest: Equatable, Sendable {
    var name: String
    var repositoryPath: String
    var agentCommand: String

    init(draft: WorkspaceDraft) {
        self.name = draft.inferredName
        self.repositoryPath = draft.trimmedRepositoryPath
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

    static func tmuxSessionName(
        repositoryRootPath: String,
        workspaceName: String
    ) -> String {
        let repoName = URL(fileURLWithPath: repositoryRootPath).lastPathComponent
        return slug("\(repoName)-\(workspaceName)", fallback: "looper-session")
    }
}

extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
