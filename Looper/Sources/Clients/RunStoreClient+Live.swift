import Foundation

extension RunStoreClient {
    static func live(database: AppDatabase) -> Self {
        Self(
            fetchRuns: {
                try await database.fetchRuns()
            },
            saveRun: { run in
                try await database.saveRun(run)
            }
        )
    }
}
