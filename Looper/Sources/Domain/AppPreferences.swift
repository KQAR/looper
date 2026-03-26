import Foundation

struct AppPreferences: Equatable, Sendable {
    var defaultProjectPath: String = ""
    var defaultAgentCommand: String = "claude"
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
            lastSelectedPipelineID: selectedPipelineID,
            taskProviderConfiguration: base?.taskProviderConfiguration ?? .init(),
            hasCompletedOnboarding: base?.hasCompletedOnboarding ?? false
        )
    }
}
