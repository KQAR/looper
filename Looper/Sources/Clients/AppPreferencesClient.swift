import ComposableArchitecture
import Foundation

@DependencyClient
struct AppPreferencesClient {
    var fetchPreferences: @Sendable () async -> AppPreferences = { .init() }
    var savePreferences: @Sendable (AppPreferences) async -> Void
}

extension DependencyValues {
    var appPreferencesClient: AppPreferencesClient {
        get { self[AppPreferencesClient.self] }
        set { self[AppPreferencesClient.self] = newValue }
    }
}

extension AppPreferencesClient: DependencyKey {
    static let testValue = AppPreferencesClient(
        fetchPreferences: { .init() },
        savePreferences: { _ in }
    )

    static let liveValue = {
        enum Keys {
            static let defaultProjectPath = "pipelinePreferences.defaultProjectPath"
            static let defaultAgentCommand = "pipelinePreferences.defaultAgentCommand"
            static let lastSelectedPipelineID = "pipelinePreferences.lastSelectedPipelineID"
            static let taskProviderConfiguration = "pipelinePreferences.taskProviderConfiguration"
            static let hasCompletedOnboarding = "pipelinePreferences.hasCompletedOnboarding"
            static let postRunGitAction = "pipelinePreferences.postRunGitAction"
        }

        return AppPreferencesClient(
            fetchPreferences: {
                let defaults = UserDefaults.standard
                let taskProviderConfiguration = defaults.data(forKey: Keys.taskProviderConfiguration)
                    .flatMap { try? JSONDecoder().decode(TaskProviderConfiguration.self, from: $0) }
                    ?? .init()
                let postRunGitAction = defaults.string(forKey: Keys.postRunGitAction)
                    .flatMap(PostRunGitAction.init(rawValue:))
                    ?? .pushBranch

                return AppPreferences(
                    defaultProjectPath: defaults.string(forKey: Keys.defaultProjectPath) ?? "",
                    defaultAgentCommand: defaults.string(forKey: Keys.defaultAgentCommand) ?? "claude",
                    postRunGitAction: postRunGitAction,
                    lastSelectedPipelineID: defaults.string(forKey: Keys.lastSelectedPipelineID)
                        .flatMap(UUID.init(uuidString:)),
                    taskProviderConfiguration: taskProviderConfiguration,
                    hasCompletedOnboarding: defaults.bool(forKey: Keys.hasCompletedOnboarding)
                )
            },
            savePreferences: { preferences in
                let defaults = UserDefaults.standard
                defaults.set(preferences.defaultProjectPath, forKey: Keys.defaultProjectPath)
                defaults.set(preferences.defaultAgentCommand, forKey: Keys.defaultAgentCommand)
                defaults.set(preferences.postRunGitAction.rawValue, forKey: Keys.postRunGitAction)
                defaults.set(
                    preferences.lastSelectedPipelineID?.uuidString,
                    forKey: Keys.lastSelectedPipelineID
                )
                defaults.set(
                    try? JSONEncoder().encode(preferences.taskProviderConfiguration),
                    forKey: Keys.taskProviderConfiguration
                )
                defaults.set(
                    preferences.hasCompletedOnboarding,
                    forKey: Keys.hasCompletedOnboarding
                )
            }
        )
    }()
}
