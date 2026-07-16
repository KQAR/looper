import ComposableArchitecture
import Foundation
import XCTest

@testable import Looper

@MainActor
final class InboxTests: XCTestCase {
    // MARK: - Card derivation (pure state)

    func testReviewRequestCardDerivesFromInReviewTask() {
        var state = AppFeature.State()
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
                repoPath: nil
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
        let promptRecorder = AgentPromptRecorder()
        let recorder = TaskStatusRecorder()

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
            $0.agentProcessClient.execute = { request in
                await promptRecorder.record(request.taskDescription)
                return AsyncStream { $0.finish() }
            }
            $0.pipelineTerminalClient.upsertRunSession = { _, _, _, _ in }
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
        }
        store.exhaustivity = .off

        await store.send(.startSelectedTaskButtonTapped)
        await store.finish()

        XCTAssertNil(store.state.pendingSteeringNotes[task.id])
        let prompt = await promptRecorder.value()
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt?.contains("Steering Notes from the owner") == true)
        XCTAssertTrue(prompt?.contains("- Cover the timeout branch") == true)
    }
}

actor AgentPromptRecorder {
    private var prompt: String?

    func record(_ prompt: String) {
        self.prompt = prompt
    }

    func value() -> String? {
        prompt
    }
}
