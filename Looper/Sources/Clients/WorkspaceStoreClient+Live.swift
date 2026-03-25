import Foundation

extension WorkspaceStoreClient {
    static func live(database: AppDatabase) -> Self {
        Self(
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
    }
}
