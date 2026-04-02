import Foundation
import GRDB

struct RunRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    static let databaseTableName = "runs"

    var id: String
    var pipelineID: String
    var taskID: String
    var status: Run.Status
    var trigger: Run.Trigger
    var worktreePath: String?
    var sessionID: String?
    var startedAt: Date
    var finishedAt: Date?
    var exitCode: Int32?
    var logPath: String

    init(run: Run) {
        self.id = run.id.uuidString
        self.pipelineID = run.pipelineID.uuidString
        self.taskID = run.taskID
        self.status = run.status
        self.trigger = run.trigger
        self.worktreePath = run.worktreePath
        self.sessionID = run.sessionID
        self.startedAt = run.startedAt
        self.finishedAt = run.finishedAt
        self.exitCode = run.exitCode
        self.logPath = run.logPath
    }

    var run: Run {
        Run(
            id: UUID(uuidString: id) ?? UUID(),
            pipelineID: UUID(uuidString: pipelineID) ?? UUID(),
            taskID: taskID,
            status: status,
            trigger: trigger,
            worktreePath: worktreePath,
            sessionID: sessionID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            exitCode: exitCode,
            logPath: logPath
        )
    }
}
