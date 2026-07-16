import ComposableArchitecture
import Foundation
import XCTest

@testable import Looper

@MainActor
final class InboxTests: XCTestCase {
    private static func demoPipeline() -> Pipeline {
        Pipeline(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "demo",
            projectPath: "/tmp/demo",
            executionPath: "/tmp/demo",
            agentCommand: "claude",
            tmuxSessionName: "demo"
        )
    }

    // MARK: - Card derivation (pure state)

    func testReviewRequestCardDerivesFromInReviewTask() {
        var state = AppFeature.State()
        state.pipeline.pipelines = [Self.demoPipeline()]
        state.tasks = [
            LooperTask(
                id: "task-1",
                title: "Fix login",
                summary: "Summary",
                status: .inReview,
                source: "Local",
                repoPath: URL(filePath: "/tmp/demo")
            ),
        ]

        let cards = state.inboxCards
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.id, "review-task-1")
        XCTAssertEqual(cards.first?.kind, .reviewRequest(taskID: "task-1"))
    }

    func testStrandedTaskProducesNoCardsAndIsExcludedFromBacklog() {
        // Tasks whose pipeline was deleted are stranded: no cards, no
        // backlog promise. They stay reachable on the Manage surface.
        var state = AppFeature.State()
        state.tasks = [
            LooperTask(
                id: "task-1",
                title: "Stranded review",
                summary: "Summary",
                status: .inReview,
                source: "Local",
                repoPath: URL(filePath: "/tmp/deleted-project")
            ),
            LooperTask(
                id: "task-2",
                title: "Stranded todo",
                summary: "Summary",
                status: .todo,
                source: "Local",
                repoPath: URL(filePath: "/tmp/deleted-project")
            ),
        ]

        XCTAssertTrue(state.inboxCards.isEmpty)
        XCTAssertEqual(state.inboxBacklogCount, 0)

        // The same tasks routed to an existing pipeline produce cards again.
        state.pipeline.pipelines = [Self.demoPipeline()]
        state.tasks[id: "task-1"]?.repoPath = URL(filePath: "/tmp/demo")
        state.tasks[id: "task-2"]?.repoPath = URL(filePath: "/tmp/demo")
        XCTAssertEqual(state.inboxCards.first?.id, "review-task-1")
        XCTAssertEqual(state.inboxBacklogCount, 1)
    }

    func testFailureCardDerivesFromLatestFailedRunWithoutActiveRetry() {
        let pipelineID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!
        let failedRun = Run(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!,
            pipelineID: pipelineID,
            taskID: "task-1",
            status: .failed,
            trigger: .startTask,
            worktreePath: "/tmp/worktrees/run-1",
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 2_000),
            exitCode: 1,
            logPath: "/tmp/logs/run-1.log"
        )

        var state = AppFeature.State()
        state.pipeline.pipelines = [Self.demoPipeline()]
        state.tasks = [
            LooperTask(
                id: "task-1",
                title: "Fix login",
                summary: "Summary",
                status: .todo,
                source: "Local",
                repoPath: URL(filePath: "/tmp/demo")
            ),
        ]
        state.runs = [failedRun]

        XCTAssertEqual(
            state.inboxCards.first?.kind,
            .failureEscalation(
                taskID: "task-1",
                runID: failedRun.id,
                worktreePath: "/tmp/worktrees/run-1"
            )
        )

        // Self-healing: an active retry withdraws the failure card.
        var retryRun = failedRun
        retryRun.id = UUID(uuidString: "AAAA0000-0000-0000-0000-000000000002")!
        retryRun.status = .running
        retryRun.startedAt = Date(timeIntervalSince1970: 3_000)
        state.runs.insert(retryRun, at: 0)
        XCTAssertTrue(state.inboxCards.isEmpty)
    }

    func testSystemCardsFloatAboveRunCards() {
        var state = AppFeature.State()
        state.pipeline.pipelines = [Self.demoPipeline()]
        state.environmentReport = EnvironmentSetupReport(
            git: .init(name: "Git", command: "git", isInstalled: true, resolvedPath: "/usr/bin/git"),
            claude: .init(name: "Claude CLI", command: "claude", isInstalled: false),
            tmux: .init(name: "tmux", command: "tmux", isInstalled: false)
        )
        state.tasks = [
            LooperTask(
                id: "task-1",
                title: "Fix login",
                summary: "Summary",
                status: .inReview,
                source: "Local",
                repoPath: URL(filePath: "/tmp/demo")
            ),
        ]

        let cards = state.inboxCards
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards.first?.id, "system-claude")
        XCTAssertEqual(cards.last?.id, "review-task-1")
        // tmux is optional and never produces a system card.
        XCTAssertFalse(cards.contains { $0.id == "system-tmux" })
    }

    // MARK: - Empty contexts (three distinct meanings)

    func testEmptyContextDistinguishesUnconfiguredIdleHealthy() {
        var state = AppFeature.State()
        XCTAssertEqual(state.inboxEmptyContext, .unconfigured)

        let pipeline = Pipeline(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "demo",
            projectPath: "/tmp/demo",
            executionPath: "/tmp/demo",
            agentCommand: "claude",
            tmuxSessionName: "demo"
        )
        state.pipeline.pipelines = [pipeline]
        XCTAssertEqual(state.inboxEmptyContext, .idle)

        state.runs = [
            Run(
                id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!,
                pipelineID: pipeline.id,
                taskID: "task-1",
                status: .running,
                trigger: .startTask,
                startedAt: Date(timeIntervalSince1970: 1_000),
                logPath: "/tmp/logs/run-1.log"
            ),
        ]
        XCTAssertEqual(state.inboxEmptyContext, .healthy)
        XCTAssertEqual(state.inboxQuietRunCount, 1)
    }

    // MARK: - Diff evidence

    func testRunDiffCapturedUpdatesRunAndCardExposesDiff() async {
        let pipeline = Self.demoPipeline()
        let run = Run(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!,
            pipelineID: pipeline.id,
            taskID: "task-1",
            status: .succeeded,
            trigger: .startTask,
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 2_000),
            logPath: "/tmp/logs/run-1.log"
        )
        let task = LooperTask(
            id: "task-1",
            title: "Fix login",
            summary: "Summary",
            status: .inReview,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let savedRuns = CleanupRecorder()

        var initialState = AppFeature.State(tasks: [task], runs: [run])
        initialState.pipeline.pipelines = [pipeline]

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.runStoreClient.saveRun = { run in await savedRuns.record(run.id.uuidString) }
        }

        await store.send(.runDiffCaptured(runID: run.id, diffPath: "/tmp/looper-runs/run-1.diff")) {
            $0.runs[id: run.id]?.diffPath = "/tmp/looper-runs/run-1.diff"
        }
        await store.finish()

        let saved = await savedRuns.values()
        XCTAssertEqual(saved, [run.id.uuidString])
        XCTAssertEqual(
            store.state.inboxCards[id: "review-task-1"]?.diffPath,
            "/tmp/looper-runs/run-1.diff"
        )
    }

    func testViewDiffLoadsPatchIntoPresentedDiff() async throws {
        let diffPath = NSTemporaryDirectory() + "looper-test-\(UUID().uuidString).diff"
        try "+++ b/File.swift\n+let x = 1".write(toFile: diffPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: diffPath) }

        let pipeline = Self.demoPipeline()
        var run = Run(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!,
            pipelineID: pipeline.id,
            taskID: "task-1",
            status: .succeeded,
            trigger: .startTask,
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 2_000),
            logPath: "/tmp/logs/run-1.log"
        )
        run.diffPath = diffPath
        let task = LooperTask(
            id: "task-1",
            title: "Fix login",
            summary: "Summary",
            status: .inReview,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )

        var initialState = AppFeature.State(tasks: [task], runs: [run])
        initialState.pipeline.pipelines = [pipeline]

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.inboxViewDiffTapped("task-1"))
        await store.receive(\.inboxDiffLoaded) {
            $0.presentedDiff = PresentedDiff(
                taskTitle: "Fix login",
                patch: "+++ b/File.swift\n+let x = 1"
            )
        }

        await store.send(.inboxDiffDismissed) {
            $0.presentedDiff = nil
        }
    }

    // MARK: - Send back queues a steering note

    func testSendBackQueuesSteeringNoteAndReturnsTaskToTodo() async {
        let task = LooperTask(
            id: "task-1",
            title: "Fix login",
            summary: "Summary",
            status: .inReview,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let noteID = UUID(uuidString: "BBBB0000-0000-0000-0000-000000000001")!
        let notedAt = Date(timeIntervalSince1970: 5_000)
        let recorder = TaskStatusRecorder()

        let store = TestStore(
            initialState: AppFeature.State(tasks: [task])
        ) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .constant(noteID)
            $0.date.now = notedAt
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
        }

        await store.send(.inboxSendBackConfirmed(taskID: task.id, reason: "  Cover the timeout branch  ")) {
            $0.selectedTaskID = task.id
            $0.pendingSteeringNotes = [
                task.id: [
                    SteeringNote(
                        id: noteID,
                        taskID: task.id,
                        text: "Cover the timeout branch",
                        origin: .sendBackReason,
                        createdAt: notedAt
                    ),
                ],
            ]
        }
        await store.receive(\.returnSelectedTaskToTodoButtonTapped) {
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .todo
        }

        let events = await recorder.value()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.0, task.id)
        XCTAssertEqual(events.first?.1, .todo)
    }

    func testSendBackWithBlankReasonIsRejected() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.inboxSendBackConfirmed(taskID: "task-1", reason: "   "))
    }

    // MARK: - Steering notes are delivered with the next run and consumed

    func testSteeringNotesInjectedIntoAgentPromptAndConsumed() async {
        let pipeline = Pipeline(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "demo",
            projectPath: "/tmp/demo",
            executionPath: "/tmp/demo",
            agentCommand: "claude",
            tmuxSessionName: "demo"
        )
        let task = LooperTask(
            id: "task-1",
            title: "Fix login",
            summary: "Summary",
            status: .todo,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let note = SteeringNote(
            id: UUID(uuidString: "BBBB0000-0000-0000-0000-000000000001")!,
            taskID: task.id,
            text: "Cover the timeout branch",
            origin: .sendBackReason,
            createdAt: Date(timeIntervalSince1970: 5_000)
        )
        let runID = UUID(uuidString: "CCCC0000-0000-0000-0000-000000000001")!
        let startedAt = Date(timeIntervalSince1970: 6_000)
        let recorder = TaskStatusRecorder()
        let promptPath = Run.defaultPromptPath(for: runID)
        try? FileManager.default.removeItem(atPath: promptPath)
        defer { try? FileManager.default.removeItem(atPath: promptPath) }

        var initialState = AppFeature.State(
            tasks: [task],
            selectedTaskID: task.id,
            pendingSteeringNotes: [task.id: [note]]
        )
        initialState.pipeline.pipelines = [pipeline]

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .constant(runID)
            $0.date.now = startedAt
            $0.runStoreClient.saveRun = { _ in }
            $0.gitWorktreeClient.createWorktree = { _, _ in "/tmp/worktrees/run-1" }
            $0.gitWorktreeClient.writeTaskContext = { _, _ in }
            $0.pipelineTerminalClient.upsertRunSession = { _, _, _, _ in }
            $0.pipelineTerminalClient.bootstrapRunSession = { _ in }
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
        }
        store.exhaustivity = .off

        await store.send(.startSelectedTaskButtonTapped)
        await store.finish()

        XCTAssertNil(store.state.pendingSteeringNotes[task.id])
        // The interactive agent reads its prompt from the per-run file.
        let prompt = try? String(contentsOfFile: promptPath, encoding: .utf8)
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt?.contains("Steering Notes from the owner") == true)
        XCTAssertTrue(prompt?.contains("- Cover the timeout branch") == true)
    }
}

// MARK: - Cleanup

@MainActor
final class CleanupTests: XCTestCase {
    private static let pipelineID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!

    private static func makePipeline() -> Pipeline {
        Pipeline(
            id: pipelineID,
            name: "demo",
            projectPath: "/tmp/demo",
            executionPath: "/tmp/demo",
            agentCommand: "claude",
            tmuxSessionName: "demo"
        )
    }

    private static func makeRun(
        id: String,
        status: Run.Status,
        worktreePath: String? = nil,
        pipelineID: UUID = CleanupTests.pipelineID,
        taskID: String = "task-1"
    ) -> Run {
        Run(
            id: UUID(uuidString: id)!,
            pipelineID: pipelineID,
            taskID: taskID,
            status: status,
            trigger: .startTask,
            worktreePath: worktreePath,
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: status == .running ? nil : Date(timeIntervalSince1970: 2_000),
            exitCode: nil,
            logPath: "/tmp/logs/\(id).log"
        )
    }

    func testPipelineDeletionCancelsRunsRemovesWorktreesAndPrunesRecords() async {
        let pipeline = Self.makePipeline()
        let activeRun = Self.makeRun(
            id: "AAAA0000-0000-0000-0000-000000000001",
            status: .running,
            worktreePath: "/tmp/looper-worktrees/demo/run-1"
        )
        let failedRun = Self.makeRun(
            id: "AAAA0000-0000-0000-0000-000000000002",
            status: .failed,
            worktreePath: "/tmp/looper-worktrees/demo/run-2"
        )
        let inProgressTask = LooperTask(
            id: "task-1",
            title: "In flight",
            summary: "Summary",
            status: .inProgress,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )

        let cancelled = CleanupRecorder()
        let removedSessions = CleanupRecorder()
        let removedWorktrees = CleanupRecorder()
        let deletedRuns = CleanupRecorder()
        let statusRecorder = TaskStatusRecorder()

        var initialState = AppFeature.State(tasks: [inProgressTask], runs: [activeRun, failedRun])
        initialState.pipeline.pipelines = [pipeline]
        initialState.pipeline.selectedPipelineID = pipeline.id

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.agentProcessClient.cancel = { runID in await cancelled.record(runID.uuidString) }
            $0.pipelineTerminalClient.removeSession = { _ in }
            $0.pipelineTerminalClient.removeRunSession = { runID in
                await removedSessions.record(runID.uuidString)
            }
            $0.gitWorktreeClient.removeWorktree = { _, worktreePath in
                await removedWorktrees.record(worktreePath)
            }
            $0.pipelineManagerClient.removePipeline = { _ in }
            $0.pipelineStoreClient.deletePipeline = { _ in }
            $0.runStoreClient.deleteRuns = { ids in
                for id in ids { await deletedRuns.record(id.uuidString) }
            }
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await statusRecorder.record(taskID, status)
            }
            $0.appPreferencesClient.savePreferences = { _ in }
        }

        await store.send(.pipeline(.removePipelineButtonTapped(pipeline.id))) {
            $0.pipeline.removingPipelineIDs = [pipeline.id]
            $0.updatingTaskIDs = [inProgressTask.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: inProgressTask.id]?.status = .todo
        }
        await store.receive(\.pipeline.removePipelineResponse) {
            $0.pipeline.removingPipelineIDs = []
            $0.pipeline.pipelines = []
            $0.pipeline.selectedPipelineID = nil
            $0.pipeline.preferences.lastSelectedPipelineID = nil
            $0.runs = []
        }
        await store.finish()

        let statusEvents = await statusRecorder.value()
        XCTAssertEqual(statusEvents.count, 1)
        XCTAssertEqual(statusEvents.first?.0, inProgressTask.id)
        XCTAssertEqual(statusEvents.first?.1, .todo)

        let cancelledIDs = await cancelled.values()
        XCTAssertEqual(cancelledIDs, [activeRun.id.uuidString])
        let sessionIDs = await removedSessions.values()
        XCTAssertEqual(
            Set(sessionIDs),
            [activeRun.id.uuidString, failedRun.id.uuidString]
        )
        let worktrees = await removedWorktrees.values()
        XCTAssertEqual(
            Set(worktrees),
            ["/tmp/looper-worktrees/demo/run-1", "/tmp/looper-worktrees/demo/run-2"]
        )
        let deleted = await deletedRuns.values()
        XCTAssertEqual(
            Set(deleted),
            [activeRun.id.uuidString, failedRun.id.uuidString]
        )
    }

    func testRetryOnStrandedTaskDoesNotRecreatePipeline() async {
        // Regression: retry on a task whose pipeline was deleted used to
        // fall through to the auto-create fallback and resurrect it.
        let strandedTask = LooperTask(
            id: "task-1",
            title: "Stranded",
            summary: "Summary",
            status: .todo,
            source: "Local",
            repoPath: URL(filePath: "/tmp/deleted-project")
        )

        let store = TestStore(initialState: AppFeature.State(tasks: [strandedTask])) {
            AppFeature()
        }

        // No state change, no startSelectedTaskButtonTapped, no pipeline creation.
        await store.send(.inboxRetryTapped(strandedTask.id))
    }

    func testAgentResultDuringPipelineRemovalDoesNotResurrectRun() async {
        let pipeline = Self.makePipeline()
        let activeRun = Self.makeRun(
            id: "AAAA0000-0000-0000-0000-000000000001",
            status: .running,
            worktreePath: "/tmp/looper-worktrees/demo/run-1"
        )

        var initialState = AppFeature.State(runs: [activeRun])
        initialState.pipeline.pipelines = [pipeline]
        initialState.pipeline.removingPipelineIDs = [pipeline.id]

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.runStoreClient.saveRun = { _ in
                XCTFail("A run of a pipeline being removed must not be saved")
            }
        }

        let result = AgentResult(
            sessionID: "",
            isError: true,
            durationMs: 0,
            costUSD: 0,
            numTurns: 0,
            resultText: "Agent was cancelled"
        )
        await store.send(.agentEventReceived(runID: activeRun.id, .result(result))) {
            $0.runs = []
        }
    }

    func testMarkDoneDropsNotesAndClearsWorktreePaths() async {
        let pipeline = Self.makePipeline()
        let task = LooperTask(
            id: "task-1",
            title: "Fix login",
            summary: "Summary",
            status: .inReview,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let failedRun = Self.makeRun(
            id: "AAAA0000-0000-0000-0000-000000000002",
            status: .failed,
            worktreePath: "/tmp/looper-worktrees/demo/run-2"
        )
        let note = SteeringNote(
            id: UUID(uuidString: "BBBB0000-0000-0000-0000-000000000001")!,
            taskID: task.id,
            text: "stale note",
            origin: .user,
            createdAt: Date(timeIntervalSince1970: 4_000)
        )
        let recorder = TaskStatusRecorder()
        let savedRuns = CleanupRecorder()

        var initialState = AppFeature.State(
            tasks: [task],
            runs: [failedRun],
            selectedTaskID: task.id,
            pendingSteeringNotes: [task.id: [note]]
        )
        initialState.pipeline.pipelines = [pipeline]

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
            $0.gitWorktreeClient.removeWorktree = { _, _ in }
            $0.runStoreClient.saveRun = { run in await savedRuns.record(run.id.uuidString) }
        }

        await store.send(.markSelectedTaskDoneButtonTapped) {
            $0.pendingSteeringNotes = [:]
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .done
        }
        await store.receive(\.taskWorktreesCleaned) {
            $0.runs[id: failedRun.id]?.worktreePath = nil
        }
        await store.finish()

        let saved = await savedRuns.values()
        XCTAssertEqual(saved, [failedRun.id.uuidString])
    }

    func testMaintenanceCardRequiresLoadedSourcesAndAggregatesLeftovers() {
        let pipeline = Self.makePipeline()
        let staleRun = Self.makeRun(
            id: "AAAA0000-0000-0000-0000-000000000001",
            status: .succeeded,
            worktreePath: "/tmp/looper-worktrees/demo/run-1"
        )
        let orphanedRun = Self.makeRun(
            id: "AAAA0000-0000-0000-0000-000000000002",
            status: .failed,
            worktreePath: "/tmp/looper-worktrees/gone/run-2",
            pipelineID: UUID(uuidString: "DEAD0000-0000-0000-0000-000000000000")!,
            taskID: "task-2"
        )
        let doneTask = LooperTask(
            id: "task-1",
            title: "Done task",
            summary: "Summary",
            status: .done,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )

        var state = AppFeature.State(tasks: [doneTask], runs: [staleRun, orphanedRun])
        state.pipeline.pipelines = [pipeline]

        // Silent until both sources have loaded.
        XCTAssertNil(state.inboxCards[id: "maintenance"])

        state.hasLoadedPipelines = true
        state.hasLoadedTasks = true
        XCTAssertEqual(
            state.inboxCards[id: "maintenance"]?.kind,
            .maintenance(
                staleWorktreeRunIDs: [staleRun.id],
                orphanedRunIDs: [orphanedRun.id]
            )
        )
        // Maintenance sinks to the bottom.
        XCTAssertEqual(state.inboxCards.last?.id, "maintenance")
    }

    func testInboxCleanupRemovesLeftoversAndPrunesState() async {
        let pipeline = Self.makePipeline()
        let staleRun = Self.makeRun(
            id: "AAAA0000-0000-0000-0000-000000000001",
            status: .succeeded,
            worktreePath: "/tmp/looper-worktrees/demo/run-1"
        )
        let orphanedRun = Self.makeRun(
            id: "AAAA0000-0000-0000-0000-000000000002",
            status: .failed,
            worktreePath: "/tmp/looper-worktrees/gone/run-2",
            pipelineID: UUID(uuidString: "DEAD0000-0000-0000-0000-000000000000")!,
            taskID: "task-2"
        )
        let doneTask = LooperTask(
            id: "task-1",
            title: "Done task",
            summary: "Summary",
            status: .done,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )

        let removedWorktrees = CleanupRecorder()
        let removedDirectories = CleanupRecorder()
        let deletedRuns = CleanupRecorder()
        let savedRuns = CleanupRecorder()

        var initialState = AppFeature.State(
            tasks: [doneTask],
            runs: [staleRun, orphanedRun],
            hasLoadedPipelines: true,
            hasLoadedTasks: true
        )
        initialState.pipeline.pipelines = [pipeline]

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.gitWorktreeClient.removeWorktree = { _, worktreePath in
                await removedWorktrees.record(worktreePath)
            }
            $0.gitWorktreeClient.removeWorktreeDirectory = { worktreePath in
                await removedDirectories.record(worktreePath)
            }
            $0.runStoreClient.deleteRuns = { ids in
                for id in ids { await deletedRuns.record(id.uuidString) }
            }
            $0.runStoreClient.saveRun = { run in await savedRuns.record(run.id.uuidString) }
        }

        await store.send(.inboxCleanupTapped)
        await store.receive(\.inboxCleanupCompleted) {
            $0.runs[id: staleRun.id]?.worktreePath = nil
            $0.runs.remove(id: orphanedRun.id)
        }
        await store.finish()

        let worktrees = await removedWorktrees.values()
        XCTAssertEqual(worktrees, ["/tmp/looper-worktrees/demo/run-1"])
        let directories = await removedDirectories.values()
        XCTAssertEqual(directories, ["/tmp/looper-worktrees/gone/run-2"])
        let deleted = await deletedRuns.values()
        XCTAssertEqual(deleted, [orphanedRun.id.uuidString])
        let saved = await savedRuns.values()
        XCTAssertEqual(saved, [staleRun.id.uuidString])
        XCTAssertNil(store.state.inboxCards[id: "maintenance"])
    }
}

actor CleanupRecorder {
    private var recorded: [String] = []

    func record(_ value: String) {
        recorded.append(value)
    }

    func values() -> [String] {
        recorded
    }
}

