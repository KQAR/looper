import Foundation
import GRDB

struct WorkspaceRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    static let databaseTableName = "workspaces"

    var id: String
    var name: String
    var repositoryRootPath: String
    var worktreePath: String
    var branchName: String
    var baseBranch: String
    var agentCommand: String
    var tmuxSessionName: String
    var createdAt: Date

    init(workspace: CodingWorkspace) {
        self.id = workspace.id.uuidString
        self.name = workspace.name
        self.repositoryRootPath = workspace.repositoryRootPath
        self.worktreePath = workspace.worktreePath
        self.branchName = workspace.branchName
        self.baseBranch = workspace.baseBranch
        self.agentCommand = workspace.agentCommand
        self.tmuxSessionName = workspace.tmuxSessionName
        self.createdAt = workspace.createdAt
    }

    var workspace: CodingWorkspace {
        CodingWorkspace(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            repositoryRootPath: repositoryRootPath,
            worktreePath: worktreePath,
            branchName: branchName,
            baseBranch: baseBranch,
            agentCommand: agentCommand,
            tmuxSessionName: tmuxSessionName,
            createdAt: createdAt
        )
    }
}
