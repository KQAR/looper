import ComposableArchitecture
import Foundation

@DependencyClient
struct RunStoreClient {
    var fetchRuns: @Sendable () async throws -> [Run]
    var saveRun: @Sendable (Run) async throws -> Void
}

extension DependencyValues {
    var runStoreClient: RunStoreClient {
        get { self[RunStoreClient.self] }
        set { self[RunStoreClient.self] = newValue }
    }
}

extension RunStoreClient: DependencyKey {
    static let testValue = RunStoreClient(
        fetchRuns: { [] },
        saveRun: { _ in }
    )

    static let liveValue = {
        let database = AppDatabase.makeLive()
        return RunStoreClient.live(database: database)
    }()
}
