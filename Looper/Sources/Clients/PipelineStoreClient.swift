import ComposableArchitecture
import Foundation

@DependencyClient
struct PipelineStoreClient {
    var fetchPipelines: @Sendable () async throws -> [Pipeline]
    var savePipeline: @Sendable (Pipeline) async throws -> Void
    var deletePipeline: @Sendable (UUID) async throws -> Void
}

extension DependencyValues {
    var pipelineStoreClient: PipelineStoreClient {
        get { self[PipelineStoreClient.self] }
        set { self[PipelineStoreClient.self] = newValue }
    }
}

extension PipelineStoreClient: DependencyKey {
    static let liveValue = {
        let database = AppDatabase.makeLive()

        return PipelineStoreClient(
            fetchPipelines: {
                try await database.fetchPipelines()
            },
            savePipeline: { pipeline in
                try await database.savePipeline(pipeline)
            },
            deletePipeline: { id in
                try await database.deletePipeline(id: id)
            }
        )
    }()
}
