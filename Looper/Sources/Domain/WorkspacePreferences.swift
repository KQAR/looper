import Foundation

struct WorkspacePreferences: Equatable, Sendable {
    var defaultRepositoryPath: String = ""
    var defaultAgentCommand: String = "claude"
    var lastSelectedWorkspaceID: UUID?

    var draft: WorkspaceDraft {
        WorkspaceDraft(
            name: "",
            repositoryPath: defaultRepositoryPath,
            agentCommand: defaultAgentCommand
        )
    }

    static func from(
        workspace: CodingWorkspace,
        selectedWorkspaceID: UUID?
    ) -> Self {
        Self(
            defaultRepositoryPath: workspace.repositoryRootPath,
            defaultAgentCommand: workspace.agentCommand,
            lastSelectedWorkspaceID: selectedWorkspaceID
        )
    }
}
