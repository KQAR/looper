import Foundation

extension PipelineStoreClient {
    static func live(database: AppDatabase) -> Self {
        Self(
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
    }
}
