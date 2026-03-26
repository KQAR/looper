import Foundation

struct WorkspacePreferences: Equatable, Sendable {
    var defaultRepositoryPath: String = ""
    var defaultAgentCommand: String = "claude"
    var lastSelectedWorkspaceID: UUID?
    var taskBoardConfiguration: TaskBoardConfiguration = .init()
    var hasCompletedOnboarding = false

    var draft: WorkspaceDraft {
        WorkspaceDraft(
            name: "",
            repositoryPath: defaultRepositoryPath,
            agentCommand: defaultAgentCommand
        )
    }

    static func from(
        workspace: CodingWorkspace,
        selectedWorkspaceID: UUID?,
        base: WorkspacePreferences? = nil
    ) -> Self {
        Self(
            defaultRepositoryPath: workspace.repositoryRootPath,
            defaultAgentCommand: workspace.agentCommand,
            lastSelectedWorkspaceID: selectedWorkspaceID,
            taskBoardConfiguration: base?.taskBoardConfiguration ?? .init(),
            hasCompletedOnboarding: base?.hasCompletedOnboarding ?? false
        )
    }
}
