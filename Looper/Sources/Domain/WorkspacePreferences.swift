import Foundation

struct WorkspacePreferences: Equatable, Sendable {
    var defaultRepositoryPath: String = ""
    var defaultBaseBranch: String = "HEAD"
    var defaultAgentCommand: String = "claude"
    var lastSelectedWorkspaceID: UUID?

    var draft: WorkspaceDraft {
        WorkspaceDraft(
            name: "",
            repositoryPath: defaultRepositoryPath,
            baseBranch: defaultBaseBranch,
            branchName: "",
            agentCommand: defaultAgentCommand
        )
    }

    static func from(
        workspace: CodingWorkspace,
        selectedWorkspaceID: UUID?
    ) -> Self {
        Self(
            defaultRepositoryPath: workspace.repositoryRootPath,
            defaultBaseBranch: workspace.baseBranch,
            defaultAgentCommand: workspace.agentCommand,
            lastSelectedWorkspaceID: selectedWorkspaceID
        )
    }
}
