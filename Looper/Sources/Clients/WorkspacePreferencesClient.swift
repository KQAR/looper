import ComposableArchitecture
import Foundation

@DependencyClient
struct WorkspacePreferencesClient {
    var fetchPreferences: @Sendable () async -> WorkspacePreferences = { .init() }
    var savePreferences: @Sendable (WorkspacePreferences) async -> Void
}

extension DependencyValues {
    var workspacePreferencesClient: WorkspacePreferencesClient {
        get { self[WorkspacePreferencesClient.self] }
        set { self[WorkspacePreferencesClient.self] = newValue }
    }
}

extension WorkspacePreferencesClient: DependencyKey {
    static let liveValue = {
        enum Keys {
            static let defaultRepositoryPath = "workspacePreferences.defaultRepositoryPath"
            static let defaultAgentCommand = "workspacePreferences.defaultAgentCommand"
            static let lastSelectedWorkspaceID = "workspacePreferences.lastSelectedWorkspaceID"
            static let taskBoardConfiguration = "workspacePreferences.taskBoardConfiguration"
            static let hasCompletedOnboarding = "workspacePreferences.hasCompletedOnboarding"
        }

        return WorkspacePreferencesClient(
            fetchPreferences: {
                let defaults = UserDefaults.standard
                let taskBoardConfiguration = defaults.data(forKey: Keys.taskBoardConfiguration)
                    .flatMap { try? JSONDecoder().decode(TaskBoardConfiguration.self, from: $0) }
                    ?? .init()
                let hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding)
                    .flatMap { _ in defaults.bool(forKey: Keys.hasCompletedOnboarding) }
                    ?? taskBoardConfiguration.isConfigured

                return WorkspacePreferences(
                    defaultRepositoryPath: defaults.string(forKey: Keys.defaultRepositoryPath) ?? "",
                    defaultAgentCommand: defaults.string(forKey: Keys.defaultAgentCommand) ?? "claude",
                    lastSelectedWorkspaceID: defaults.string(forKey: Keys.lastSelectedWorkspaceID)
                        .flatMap(UUID.init(uuidString:)),
                    taskBoardConfiguration: taskBoardConfiguration,
                    hasCompletedOnboarding: hasCompletedOnboarding
                )
            },
            savePreferences: { preferences in
                let defaults = UserDefaults.standard
                defaults.set(preferences.defaultRepositoryPath, forKey: Keys.defaultRepositoryPath)
                defaults.set(preferences.defaultAgentCommand, forKey: Keys.defaultAgentCommand)
                defaults.set(
                    preferences.lastSelectedWorkspaceID?.uuidString,
                    forKey: Keys.lastSelectedWorkspaceID
                )
                defaults.set(
                    try? JSONEncoder().encode(preferences.taskBoardConfiguration),
                    forKey: Keys.taskBoardConfiguration
                )
                defaults.set(
                    preferences.hasCompletedOnboarding,
                    forKey: Keys.hasCompletedOnboarding
                )
            }
        )
    }()
}
