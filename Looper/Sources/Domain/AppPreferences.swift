import Foundation

enum PostRunGitAction: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case none
    case pushBranch
    case pushAndPR

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .pushBranch: "Push Branch"
        case .pushAndPR: "Push + Create PR"
        }
    }
}

struct AppPreferences: Equatable, Sendable {
    var defaultProjectPath: String = ""
    var defaultAgentCommand: String = "claude"
    var postRunGitAction: PostRunGitAction = .pushBranch
    var lastSelectedPipelineID: UUID?
    var taskProviderConfiguration: TaskProviderConfiguration = .init()
    var hasCompletedOnboarding = false

    var feishuProviderConfiguration: FeishuTaskProviderConfiguration {
        get { taskProviderConfiguration.feishu }
        set { taskProviderConfiguration.feishu = newValue }
    }

    var draft: PipelineDraft {
        PipelineDraft(
            name: "",
            projectPath: defaultProjectPath,
            agentCommand: defaultAgentCommand
        )
    }

    static func from(
        pipeline: Pipeline,
        selectedPipelineID: UUID?,
        base: AppPreferences? = nil
    ) -> Self {
        Self(
            defaultProjectPath: pipeline.projectPath,
            defaultAgentCommand: pipeline.agentCommand,
            postRunGitAction: base?.postRunGitAction ?? .pushBranch,
            lastSelectedPipelineID: selectedPipelineID,
            taskProviderConfiguration: base?.taskProviderConfiguration ?? .init(),
            hasCompletedOnboarding: base?.hasCompletedOnboarding ?? false
        )
    }
}
