import Foundation

struct Pipeline: Equatable, Identifiable, Sendable {
    static let defaultMaxConcurrentRuns = 3
    static let defaultRunTimeoutSeconds: TimeInterval = 2 * 60 * 60 // 2 hours

    let id: UUID
    var name: String
    var projectPath: String
    var executionPath: String
    var agentCommand: String
    /// Command used when resuming a failed run. If empty, agentCommand is used (no resume behavior).
    /// Examples: "claude --continue", "codex --resume"
    var resumeCommand: String
    var tmuxSessionName: String
    var maxConcurrentRuns: Int
    var runTimeoutSeconds: TimeInterval
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        projectPath: String,
        executionPath: String,
        agentCommand: String,
        resumeCommand: String = "",
        tmuxSessionName: String,
        maxConcurrentRuns: Int = Pipeline.defaultMaxConcurrentRuns,
        runTimeoutSeconds: TimeInterval = Pipeline.defaultRunTimeoutSeconds,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.executionPath = executionPath
        self.agentCommand = agentCommand
        self.resumeCommand = resumeCommand
        self.tmuxSessionName = tmuxSessionName
        self.maxConcurrentRuns = maxConcurrentRuns
        self.runTimeoutSeconds = runTimeoutSeconds
        self.createdAt = createdAt
    }

    var executionURL: URL {
        URL(fileURLWithPath: executionPath)
    }

    var executionDirectoryName: String {
        executionURL.lastPathComponent
    }

    var exitStatusFileURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "looper-pipeline-\(id.uuidString)-exit-status")
    }

    var tracksAgentLifecycle: Bool {
        !agentCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var usesProjectDirectoryAsExecutionRoot: Bool {
        projectPath == executionPath
    }

    var attachScript: String {
        runAttachScript(executionPath: executionPath, resume: false)
    }

    func runAttachScript(executionPath: String, resume: Bool) -> String {
        let escapedExecutionPath = executionPath.shellQuoted
        let baseCommand = agentCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let resumeCmd = resumeCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        if baseCommand.isEmpty {
            return "cd \(escapedExecutionPath)"
        }

        // Use resumeCommand if set and resuming; otherwise fall back to agentCommand
        let command = (resume && !resumeCmd.isEmpty) ? resumeCmd : baseCommand
        let escapedStatusFile = exitStatusFileURL.path.shellQuoted

        let wrappedScript = """
        rm -f \(escapedStatusFile); \
        cd \(escapedExecutionPath) && \(command); \
        s=$?; printf '%s' "$s" > \(escapedStatusFile); exit "$s"
        """

        return "/bin/zsh -lc \(wrappedScript.shellQuoted)"
    }
}

struct PipelineDraft: Equatable, Sendable {
    var name: String = ""
    var projectPath: String = ""
    var agentCommand: String = "claude"

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedProjectPath: String {
        projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAgentCommand: String {
        agentCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var inferredName: String {
        let explicitName = trimmedName
        guard !explicitName.isEmpty else {
            let lastPathComponent = URL(fileURLWithPath: trimmedProjectPath).lastPathComponent
            return lastPathComponent.isEmpty ? "Pipeline" : lastPathComponent
        }
        return explicitName
    }

    var canCreate: Bool {
        !trimmedProjectPath.isEmpty
    }
}

struct CreatePipelineRequest: Equatable, Sendable {
    var name: String
    var projectPath: String
    var agentCommand: String

    init(draft: PipelineDraft) {
        self.name = draft.inferredName
        self.projectPath = draft.trimmedProjectPath
        self.agentCommand = draft.trimmedAgentCommand
    }
}

enum PipelineNaming {
    static func slug(_ rawValue: String, fallback: String = "pipeline") -> String {
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
        projectPath: String,
        pipelineName: String
    ) -> String {
        let repoName = URL(fileURLWithPath: projectPath).lastPathComponent
        return slug("\(repoName)-\(pipelineName)", fallback: "looper-session")
    }
}

extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
