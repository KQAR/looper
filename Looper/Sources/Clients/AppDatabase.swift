import Foundation
import GRDB

actor AppDatabase {
    private let databaseQueue: DatabaseQueue

    init(path: String) throws {
        databaseQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(databaseQueue)
    }

    func fetchWorkspaces() throws -> [CodingWorkspace] {
        try databaseQueue.read { db in
            try WorkspaceRecord
                .order(Column("createdAt").desc)
                .fetchAll(db)
                .map(\.workspace)
        }
    }

    func saveWorkspace(_ workspace: CodingWorkspace) throws {
        try databaseQueue.write { db in
            var record = WorkspaceRecord(workspace: workspace)
            try record.save(db)
        }
    }

    func deleteWorkspace(id: UUID) throws {
        try databaseQueue.write { db in
            _ = try WorkspaceRecord.deleteOne(db, key: id.uuidString)
        }
    }

    static func makeLive() -> AppDatabase {
        do {
            return try AppDatabase(path: defaultDatabasePath())
        } catch {
            fatalError("Failed to open Looper database: \(error)")
        }
    }

    private static func defaultDatabasePath() throws -> String {
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let databaseDirectoryURL = appSupportURL.appendingPathComponent(
            "Looper",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: databaseDirectoryURL,
            withIntermediateDirectories: true
        )

        return databaseDirectoryURL
            .appendingPathComponent("Looper.sqlite")
            .path(percentEncoded: false)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createWorkspaces") { db in
            try db.create(table: WorkspaceRecord.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("repositoryRootPath", .text).notNull()
                table.column("worktreePath", .text).notNull()
                table.column("branchName", .text).notNull()
                table.column("baseBranch", .text).notNull()
                table.column("agentCommand", .text).notNull()
                table.column("tmuxSessionName", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
        }

        return migrator
    }
}
