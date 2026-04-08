import Foundation

enum PostRunGitAction: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case none
    case pushBranch
    case pushAndPR

    var id: String { rawValue }

    func localizedLabel(bundle: Bundle) -> String {
        switch self {
        case .none:
            String(localized: "settings.general.postRunGitAction.none", bundle: bundle)
        case .pushBranch:
            String(localized: "settings.general.postRunGitAction.pushBranch", bundle: bundle)
        case .pushAndPR:
            String(localized: "settings.general.postRunGitAction.pushAndPR", bundle: bundle)
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
