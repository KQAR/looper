import ComposableArchitecture
import Foundation

@DependencyClient
struct WorkspaceStoreClient {
    var fetchWorkspaces: @Sendable () async throws -> [CodingWorkspace]
    var saveWorkspace: @Sendable (CodingWorkspace) async throws -> Void
    var deleteWorkspace: @Sendable (UUID) async throws -> Void
}

extension DependencyValues {
    var workspaceStoreClient: WorkspaceStoreClient {
        get { self[WorkspaceStoreClient.self] }
        set { self[WorkspaceStoreClient.self] = newValue }
    }
}

extension WorkspaceStoreClient: DependencyKey {
    static let liveValue = {
        let database = AppDatabase.makeLive()

        return WorkspaceStoreClient(
            fetchWorkspaces: {
                try await database.fetchWorkspaces()
            },
            saveWorkspace: { workspace in
                try await database.saveWorkspace(workspace)
            },
            deleteWorkspace: { id in
                try await database.deleteWorkspace(id: id)
            }
        )
    }()
}
