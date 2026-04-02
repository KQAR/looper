import Foundation
import GRDB

actor AppDatabase {
    private let databaseQueue: DatabaseQueue

    init(path: String) throws {
        databaseQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(databaseQueue)
    }

    func fetchPipelines() throws -> [Pipeline] {
        try databaseQueue.read { db in
            try PipelineRecord
                .order(Column("createdAt").desc)
                .fetchAll(db)
                .map(\.pipeline)
        }
    }

    func fetchRuns() throws -> [Run] {
        try databaseQueue.read { db in
            try RunRecord
                .order(Column("startedAt").desc)
                .fetchAll(db)
                .map(\.run)
        }
    }

    func savePipeline(_ pipeline: Pipeline) throws {
        try databaseQueue.write { db in
            var record = PipelineRecord(pipeline: pipeline)
            try record.save(db)
        }
    }

    func saveRun(_ run: Run) throws {
        try databaseQueue.write { db in
            var record = RunRecord(run: run)
            try record.save(db)
        }
    }

    func deletePipeline(id: UUID) throws {
        try databaseQueue.write { db in
            _ = try PipelineRecord.deleteOne(db, key: id.uuidString)
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

        migrator.registerMigration("createPipelines") { db in
            try db.create(table: PipelineRecord.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("projectPath", .text).notNull()
                table.column("executionPath", .text).notNull()
                table.column("agentCommand", .text).notNull()
                table.column("tmuxSessionName", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("createRuns") { db in
            try db.create(table: RunRecord.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("pipelineID", .text).notNull().indexed()
                table.column("taskID", .text).notNull().indexed()
                table.column("status", .text).notNull()
                table.column("trigger", .text).notNull()
                table.column("startedAt", .datetime).notNull().indexed()
                table.column("finishedAt", .datetime)
                table.column("exitCode", .integer)
                table.column("logPath", .text).notNull()
            }
        }

        migrator.registerMigration("addParallelRunSupport") { db in
            try db.alter(table: PipelineRecord.databaseTableName) { table in
                table.add(column: "maxConcurrentRuns", .integer)
                    .notNull()
                    .defaults(to: Pipeline.defaultMaxConcurrentRuns)
                table.add(column: "runTimeoutSeconds", .double)
                    .notNull()
                    .defaults(to: Pipeline.defaultRunTimeoutSeconds)
                table.add(column: "resumeCommand", .text)
                    .notNull()
                    .defaults(to: "")
            }
            try db.alter(table: RunRecord.databaseTableName) { table in
                table.add(column: "worktreePath", .text)
                table.add(column: "sessionID", .text)
            }
        }

        return migrator
    }
}
