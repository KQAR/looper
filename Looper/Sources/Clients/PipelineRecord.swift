import Foundation
import GRDB

struct PipelineRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    static let databaseTableName = "pipelines"

    var id: String
    var name: String
    var projectPath: String
    var executionPath: String
    var agentCommand: String
    var tmuxSessionName: String
    var maxConcurrentRuns: Int
    var runTimeoutSeconds: Double
    var createdAt: Date

    init(pipeline: Pipeline) {
        self.id = pipeline.id.uuidString
        self.name = pipeline.name
        self.projectPath = pipeline.projectPath
        self.executionPath = pipeline.executionPath
        self.agentCommand = pipeline.agentCommand
        self.tmuxSessionName = pipeline.tmuxSessionName
        self.maxConcurrentRuns = pipeline.maxConcurrentRuns
        self.runTimeoutSeconds = pipeline.runTimeoutSeconds
        self.createdAt = pipeline.createdAt
    }

    var pipeline: Pipeline {
        Pipeline(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            projectPath: projectPath,
            executionPath: executionPath,
            agentCommand: agentCommand,
            tmuxSessionName: tmuxSessionName,
            maxConcurrentRuns: maxConcurrentRuns,
            runTimeoutSeconds: runTimeoutSeconds,
            createdAt: createdAt
        )
    }
}
