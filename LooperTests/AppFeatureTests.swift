import ComposableArchitecture
import XCTest

@testable import Looper

actor PreferencesRecorder {
    private var preferences: AppPreferences?

    func record(_ preferences: AppPreferences) {
        self.preferences = preferences
    }

    func value() -> AppPreferences? {
        preferences
    }
}

actor TaskStatusRecorder {
    private var events: [(String, LooperTask.Status)] = []

    func record(_ taskID: String, _ status: LooperTask.Status) {
        events.append((taskID, status))
    }

    func value() -> [(String, LooperTask.Status)] {
        events
    }
}

@MainActor
final class AppFeatureTests: XCTestCase {
    func testInitialStateHasNoTasksOrPipelines() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        XCTAssertTrue(store.state.tasks.isEmpty)
        XCTAssertTrue(store.state.runs.isEmpty)
        XCTAssertNil(store.state.selectedTaskID)
        XCTAssertTrue(store.state.pipeline.pipelines.isEmpty)
        XCTAssertNil(store.state.pipeline.selectedPipelineID)
    }

    func testOnAppearDoesNotAutoPresentSettingsWhenSetupIncomplete() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.pipelineStoreClient.fetchPipelines = { [] }
            $0.appPreferencesClient.fetchPreferences = { .init() }
            $0.pipelineTerminalClient.events = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }

        await store.send(.onAppear)
        await store.receive(\.pipeline.onAppear)
        await store.receive(\.pipeline.bootstrapResponse.success)
        await store.receive(\.loadRuns)
        await store.receive(\.refreshTasksButtonTapped) {
            $0.isLoadingTasks = true
        }
        await store.receive(\.runResponse.success)
        await store.receive(\.taskResponse.success) {
            $0.isLoadingTasks = false
        }
        XCTAssertFalse(store.state.isSettingsPresented)
    }

    func testOnAppearLoadsTasksAndSelectsFirstTask() async {
        let firstTask = LooperTask(
            id: "task-1",
            title: "First",
            summary: "First summary",
            status: .todo,
            source: "Mock Feishu",
            repoPath: URL(filePath: "/tmp/first")
        )
        let secondTask = LooperTask(
            id: "task-2",
            title: "Second",
            summary: "Second summary",
            status: .todo,
            source: "Mock Feishu",
            repoPath: URL(filePath: "/tmp/second")
        )
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.taskProviderClient.fetchTasks = { _ in [firstTask, secondTask] }
            $0.pipelineStoreClient.fetchPipelines = { [] }
            $0.appPreferencesClient.fetchPreferences = {
                AppPreferences(
                    taskProviderConfiguration: providerConfiguration,
                    hasCompletedOnboarding: true
                )
            }
            $0.pipelineTerminalClient.events = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }

        await store.send(.onAppear)
        await store.receive(\.pipeline.onAppear)
        await store.receive(\.pipeline.bootstrapResponse.success) {
            $0.pipeline.preferences = AppPreferences(
                taskProviderConfiguration: providerConfiguration,
                hasCompletedOnboarding: true
            )
            $0.pipeline.composer = AppPreferences(
                taskProviderConfiguration: providerConfiguration,
                hasCompletedOnboarding: true
            ).draft
        }
        await store.receive(\.loadRuns)
        await store.receive(\.refreshTasksButtonTapped) {
            $0.isLoadingTasks = true
        }
        await store.receive(\.runResponse.success)
        await store.receive(\.taskResponse.success) {
            $0.isLoadingTasks = false
            $0.tasks = [firstTask, secondTask]
            $0.selectedTaskID = firstTask.id
        }
    }

    func testOnAppearInterruptsRecoveredInProgressRun() async {
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
            title: "Recovered task",
            summary: "Summary",
            status: .inProgress,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let activeRun = Run(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .running,
            trigger: .startTask,
            worktreePath: "/tmp/worktrees/run-1",
            startedAt: Date(timeIntervalSince1970: 1_234_567_000),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/logs/run-1.log"
        )
        let finishedAt = Date(timeIntervalSince1970: 1_234_567_999)
        let recorder = TaskStatusRecorder()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.pipelineStoreClient.fetchPipelines = { [pipeline] }
            $0.runStoreClient.fetchRuns = { [activeRun] }
            $0.runStoreClient.saveRun = { _ in }
            $0.appPreferencesClient.fetchPreferences = {
                var preferences = AppPreferences()
                preferences.hasCompletedOnboarding = true
                return preferences
            }
            $0.taskProviderClient.fetchTasks = { _ in [task] }
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
            $0.pipelineTerminalClient.events = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.pipelineTerminalClient.attachSessionIfNeeded = { _ in
                XCTFail("Recovered interrupted tasks should not auto-attach terminals")
            }
            $0.date.now = finishedAt
        }

        await store.send(.onAppear)
        await store.receive(\.pipeline.onAppear)
        await store.receive(\.pipeline.bootstrapResponse.success) {
            $0.pipeline.pipelines = [pipeline]
            $0.pipeline.selectedPipelineID = pipeline.id
            $0.pipeline.preferences.hasCompletedOnboarding = true
        }
        await store.receive(\.loadRuns)
        await store.receive(\.refreshTasksButtonTapped) {
            $0.isLoadingTasks = true
        }
        await store.receive(\.runResponse.success) {
            var interruptedRun = activeRun
            interruptedRun.status = .failed
            interruptedRun.finishedAt = finishedAt
            $0.runs = [interruptedRun]
            $0.recoveredInterruptedTaskIDs = [task.id]
        }
        await store.receive(\.taskResponse.success) {
            $0.isLoadingTasks = false
            $0.tasks = [task]
            $0.tasks[id: task.id]?.status = .todo
            $0.selectedTaskID = task.id
            $0.recoveredInterruptedTaskIDs = []
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.pipeline.selectPipeline) {
            $0.pipeline.preferences.lastSelectedPipelineID = pipeline.id
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .todo
        }

        let events = await recorder.value()
        XCTAssertEqual(events.first?.0, task.id)
        XCTAssertEqual(events.first?.1, .todo)
    }

    func testStartSelectedTaskTriggersPipelineCreation() async {
        let task = LooperTask(
            id: "task-1",
            title: "Start me",
            summary: "Summary",
            status: .todo,
            source: "Mock Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let pipeline = Pipeline(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "demo",
            projectPath: "/tmp/demo",
            executionPath: "/tmp/demo",
            agentCommand: "claude",
            tmuxSessionName: "demo"
        )
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let runID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let run = Run(
            id: runID,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .running,
            trigger: .startTask,
            startedAt: startedAt,
            finishedAt: nil,
            exitCode: nil,
            logPath: "\(NSTemporaryDirectory())looper-runs/\(runID.uuidString).log"
        )
        let recorder = TaskStatusRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State()
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.pipelineManagerClient.createPipeline = { _ in pipeline }
            $0.pipelineStoreClient.savePipeline = { _ in }
            $0.appPreferencesClient.savePreferences = { _ in }
            $0.pipelineTerminalClient.upsertSession = { _ in }
            $0.pipelineTerminalClient.focusSession = { _ in }
            $0.pipelineTerminalClient.bootstrapSession = { _ in }
            $0.runStoreClient.saveRun = { _ in }
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
            $0.uuid = .constant(runID)
            $0.date.now = startedAt
        }

        await store.send(.startSelectedTaskButtonTapped) {
            $0.pendingRunTaskID = task.id
        }
        await store.receive(\.pipeline.createPipelineFromDefaults) {
            $0.pipeline.composer = PipelineDraft(
                name: "",
                projectPath: "/tmp/demo",
                agentCommand: "claude"
            )
            $0.pipeline.isCreatingPipeline = true
        }
        await store.receive(\.pipeline.createPipelineResponse.success) {
            $0.pipeline.isCreatingPipeline = false
            $0.pipeline.pipelines = [pipeline]
            $0.pipeline.selectedPipelineID = pipeline.id
            $0.runs = [run]
            $0.updatingTaskIDs = [task.id]
            $0.pendingRunTaskID = nil
            $0.pipeline.preferences = AppPreferences(
                defaultProjectPath: "/tmp/demo",
                defaultAgentCommand: "claude",
                lastSelectedPipelineID: pipeline.id
            )
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .inProgress
        }

        let events = await recorder.value()
        XCTAssertEqual(events.first?.0, task.id)
        XCTAssertEqual(events.first?.1, .inProgress)
    }

    func testOnAppearLoadsPersistedPipelines() async {
        let pipeline = Pipeline(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "Persisted Pipeline",
            projectPath: "/tmp/repo",
            executionPath: "/tmp/repo",
            agentCommand: "claude",
            tmuxSessionName: "repo-persisted-pipeline"
        )
        let persistedRun = Run(
            id: UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!,
            pipelineID: pipeline.id,
            taskID: "task-1",
            status: .running,
            trigger: .resumeTask,
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/looper-runs/persisted.log"
        )
        let recoveredAt = Date(timeIntervalSince1970: 1_234_568_000)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.pipelineStoreClient.fetchPipelines = { [pipeline] }
            $0.runStoreClient.fetchRuns = { [persistedRun] }
            $0.appPreferencesClient.fetchPreferences = {
                AppPreferences(
                    defaultProjectPath: "/tmp/repo",
                    defaultAgentCommand: "claude --dangerously-skip-permissions",
                    lastSelectedPipelineID: pipeline.id,
                    hasCompletedOnboarding: true
                )
            }
            $0.pipelineTerminalClient.upsertSession = { _ in }
            $0.taskProviderClient.fetchTasks = { _ in [] }
            $0.date.now = recoveredAt
        }

        await store.send(.pipeline(.onAppear))
        await store.receive(\.pipeline.bootstrapResponse.success) {
            $0.pipeline.pipelines = [pipeline]
            $0.pipeline.selectedPipelineID = pipeline.id
            $0.pipeline.preferences = AppPreferences(
                defaultProjectPath: "/tmp/repo",
                defaultAgentCommand: "claude --dangerously-skip-permissions",
                lastSelectedPipelineID: pipeline.id,
                hasCompletedOnboarding: true
            )
            $0.pipeline.composer = AppPreferences(
                defaultProjectPath: "/tmp/repo",
                defaultAgentCommand: "claude --dangerously-skip-permissions",
                lastSelectedPipelineID: pipeline.id,
                hasCompletedOnboarding: true
            ).draft
        }
        await store.receive(\.loadRuns)
        await store.receive(\.refreshTasksButtonTapped) {
            $0.isLoadingTasks = true
        }
        await store.receive(\.runResponse.success) {
            var recoveredRun = persistedRun
            recoveredRun.status = .failed
            recoveredRun.finishedAt = recoveredAt
            $0.runs = [recoveredRun]
            $0.recoveredInterruptedTaskIDs = [persistedRun.taskID]
        }
        await store.receive(\.taskResponse.success) {
            $0.isLoadingTasks = false
        }
    }

    func testSelectingTaskSelectsMatchingPipeline() async {
        let task = LooperTask(
            id: "task-1",
            title: "Task",
            summary: "Summary",
            status: .todo,
            source: "Mock Feishu",
            repoPath: URL(filePath: "/tmp/repo")
        )
        let pipelineID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!
        let pipeline = Pipeline(
            id: pipelineID,
            name: "Repo",
            projectPath: "/tmp/repo",
            executionPath: "/tmp/repo",
            agentCommand: "claude",
            tmuxSessionName: "repo"
        )

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                pipeline: PipelineFeature.State(pipelines: [pipeline])
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.appPreferencesClient.savePreferences = { _ in }
            $0.pipelineTerminalClient.focusSession = { _ in }
        }

        await store.send(.selectTask(task.id)) {
            $0.selectedTaskID = task.id
            $0.pipeline.selectedPipelineID = pipelineID
        }
        await store.receive(\.pipeline.selectPipeline) {
            $0.pipeline.preferences.lastSelectedPipelineID = pipelineID
        }
    }

    func testSelectingPipelinePersistsSelection() async {
        let firstID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!
        let secondID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let first = Pipeline(
            id: firstID,
            name: "First",
            projectPath: "/tmp/repo",
            executionPath: "/tmp/first",
            agentCommand: "claude",
            tmuxSessionName: "repo-first"
        )
        let second = Pipeline(
            id: secondID,
            name: "Second",
            projectPath: "/tmp/repo",
            executionPath: "/tmp/second",
            agentCommand: "claude",
            tmuxSessionName: "repo-second"
        )
        let recorder = PreferencesRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                pipeline: PipelineFeature.State(
                    pipelines: [first, second],
                    selectedPipelineID: firstID,
                    preferences: AppPreferences(
                        defaultProjectPath: "/tmp/repo",
                        defaultAgentCommand: "claude",
                        lastSelectedPipelineID: firstID
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.appPreferencesClient.savePreferences = { await recorder.record($0) }
            $0.pipelineTerminalClient.focusSession = { _ in }
        }

        await store.send(.pipeline(.selectPipeline(secondID))) {
            $0.pipeline.selectedPipelineID = secondID
            $0.pipeline.preferences.lastSelectedPipelineID = secondID
        }

        let savedPreferences = await recorder.value()
        XCTAssertEqual(savedPreferences?.lastSelectedPipelineID, secondID)
    }

    func testSelectingPipelineSelectsMatchingTask() async {
        let pipelineID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!
        let pipeline = Pipeline(
            id: pipelineID,
            name: "Repo",
            projectPath: "/tmp/repo",
            executionPath: "/tmp/repo",
            agentCommand: "claude",
            tmuxSessionName: "repo"
        )
        let matchingTask = LooperTask(
            id: "task-1",
            title: "Match",
            summary: "Summary",
            status: .todo,
            source: "Local",
            repoPath: URL(filePath: "/tmp/repo")
        )
        let otherTask = LooperTask(
            id: "task-2",
            title: "Other",
            summary: "Summary",
            status: .todo,
            source: "Local",
            repoPath: URL(filePath: "/tmp/other")
        )

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [matchingTask, otherTask],
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline]
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.appPreferencesClient.savePreferences = { _ in }
            $0.pipelineTerminalClient.focusSession = { _ in }
        }

        await store.send(.pipeline(.selectPipeline(pipelineID))) {
            $0.selectedTaskID = matchingTask.id
            $0.pipeline.selectedPipelineID = pipelineID
            $0.pipeline.preferences.lastSelectedPipelineID = pipelineID
        }
    }

    func testQuickSwitchSelectsNextPipeline() async {
        let firstID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!
        let secondID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let first = Pipeline(
            id: firstID,
            name: "First",
            projectPath: "/tmp/first",
            executionPath: "/tmp/first",
            agentCommand: "claude",
            tmuxSessionName: "first"
        )
        let second = Pipeline(
            id: secondID,
            name: "Second",
            projectPath: "/tmp/second",
            executionPath: "/tmp/second",
            agentCommand: "claude",
            tmuxSessionName: "second"
        )
        let recorder = PreferencesRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                pipeline: PipelineFeature.State(
                    pipelines: [first, second],
                    selectedPipelineID: firstID,
                    preferences: AppPreferences(
                        defaultProjectPath: "/tmp",
                        defaultAgentCommand: "claude",
                        lastSelectedPipelineID: firstID
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.appPreferencesClient.savePreferences = { await recorder.record($0) }
            $0.pipelineTerminalClient.focusSession = { _ in }
        }

        await store.send(.pipeline(.selectNextPipeline))
        await store.receive(\.pipeline.selectPipeline) {
            $0.pipeline.selectedPipelineID = secondID
            $0.pipeline.preferences.lastSelectedPipelineID = secondID
        }

        let savedPreferences = await recorder.value()
        XCTAssertEqual(savedPreferences?.lastSelectedPipelineID, secondID)
    }

    func testOpenProjectUsesDefaultsAndCreatesPipeline() async {
        let pipeline = Pipeline(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "demo",
            projectPath: "/tmp/demo",
            executionPath: "/tmp/demo",
            agentCommand: "claude --resume",
            tmuxSessionName: "demo"
        )
        actor RequestRecorder {
            var request: CreatePipelineRequest?
            func record(_ request: CreatePipelineRequest) { self.request = request }
            func value() -> CreatePipelineRequest? { request }
        }
        let recorder = RequestRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                pipeline: PipelineFeature.State(
                    preferences: AppPreferences(
                        defaultProjectPath: "",
                        defaultAgentCommand: "claude --resume",
                        lastSelectedPipelineID: nil
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.projectDirectoryPickerClient.pickDirectory = { "/tmp/demo" }
            $0.pipelineManagerClient.createPipeline = { request in
                await recorder.record(request)
                return pipeline
            }
            $0.pipelineStoreClient.savePipeline = { _ in }
            $0.appPreferencesClient.savePreferences = { _ in }
            $0.pipelineTerminalClient.upsertSession = { _ in }
            $0.pipelineTerminalClient.focusSession = { _ in }
            $0.pipelineTerminalClient.bootstrapSession = { _ in }
        }

        await store.send(.pipeline(.openProjectButtonTapped))
        await store.receive(\.pipeline.openProjectResponse)
        await store.receive(\.pipeline.createPipelineFromDefaults) {
            $0.pipeline.composer = PipelineDraft(
                name: "",
                projectPath: "/tmp/demo",
                agentCommand: "claude --resume"
            )
            $0.pipeline.isCreatingPipeline = true
        }
        await store.receive(\.pipeline.createPipelineResponse.success) {
            $0.pipeline.isCreatingPipeline = false
            $0.pipeline.pipelines = [pipeline]
            $0.pipeline.selectedPipelineID = pipeline.id
            $0.pipeline.preferences = AppPreferences(
                defaultProjectPath: "/tmp/demo",
                defaultAgentCommand: "claude --resume",
                lastSelectedPipelineID: pipeline.id
            )
        }

        let capturedRequest = await recorder.value()
        XCTAssertEqual(capturedRequest?.projectPath, "/tmp/demo")
        XCTAssertEqual(capturedRequest?.agentCommand, "claude --resume")
        XCTAssertEqual(capturedRequest?.name, "demo")
    }

    func testNewPipelineButtonDoesNotStartSelectedTask() async {
        let task = LooperTask(
            id: "task-1",
            title: "Inbox Task",
            summary: "Summary",
            status: .todo,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let pipeline = Pipeline(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "demo",
            projectPath: "/tmp/demo",
            executionPath: "/tmp/demo",
            agentCommand: "claude --resume",
            tmuxSessionName: "demo"
        )

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    preferences: AppPreferences(
                        defaultProjectPath: "",
                        defaultAgentCommand: "claude --resume",
                        hasCompletedOnboarding: true
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.projectDirectoryPickerClient.pickDirectory = { "/tmp/demo" }
            $0.pipelineManagerClient.createPipeline = { _ in pipeline }
            $0.pipelineStoreClient.savePipeline = { _ in }
            $0.appPreferencesClient.savePreferences = { _ in }
            $0.pipelineTerminalClient.upsertSession = { _ in }
            $0.pipelineTerminalClient.focusSession = { _ in }
            $0.pipelineTerminalClient.bootstrapSession = { _ in }
        }

        await store.send(.newPipelineButtonTapped)
        await store.receive(\.pipeline.openProjectButtonTapped)
        await store.receive(\.pipeline.openProjectResponse)
        await store.receive(\.pipeline.createPipelineFromDefaults) {
            $0.pipeline.composer = PipelineDraft(
                name: "",
                projectPath: "/tmp/demo",
                agentCommand: "claude --resume"
            )
            $0.pipeline.isCreatingPipeline = true
        }
        await store.receive(\.pipeline.createPipelineResponse.success) {
            $0.pipeline.isCreatingPipeline = false
            $0.pipeline.pipelines = [pipeline]
            $0.pipeline.selectedPipelineID = pipeline.id
            $0.pipeline.preferences = AppPreferences(
                defaultProjectPath: "/tmp/demo",
                defaultAgentCommand: "claude --resume",
                lastSelectedPipelineID: pipeline.id,
                hasCompletedOnboarding: true
            )
            $0.selectedTaskID = task.id
        }

        XCTAssertTrue(store.state.runs.isEmpty)
        XCTAssertEqual(store.state.tasks[id: task.id]?.status, .todo)
    }

    func testOpenLocalTaskComposerRequiresSelectedPipeline() async {
        let store = TestStore(
            initialState: AppFeature.State(
                pipeline: PipelineFeature.State(
                    preferences: AppPreferences(
                        taskProviderConfiguration: TaskProviderConfiguration(kind: .local),
                        hasCompletedOnboarding: true
                    )
                )
            )
        ) {
            AppFeature()
        }

        await store.send(.openLocalTaskComposerButtonTapped) {
            $0.taskProviderErrorMessage = "Create or select a pipeline before adding a local task."
        }
    }

    func testSavingPreferencesPersistsDefaults() async {
        let recorder = PreferencesRecorder()
        let preferences = AppPreferences(
            defaultProjectPath: "/tmp/repo",
            defaultAgentCommand: "claude --model sonnet",
            lastSelectedPipelineID: nil
        )
        let initialPipelineState = PipelineFeature.State(
            preferences: preferences
        )
        let initialState = AppFeature.State(
            pipeline: initialPipelineState
        )

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.appPreferencesClient.savePreferences = { await recorder.record($0) }
            $0.taskProviderClient.fetchTasks = { _ in [] }
        }

        await store.send(.pipeline(.savePreferencesButtonTapped)) {
            $0.pipeline.isSavingPreferences = true
        }
        await store.receive(\.pipeline.savePreferencesFinished) {
            $0.pipeline.isSavingPreferences = false
        }
        await store.receive(\.refreshTasksButtonTapped) {
            $0.isLoadingTasks = true
        }
        await store.receive(\.taskResponse.success) {
            $0.isLoadingTasks = false
        }

        let savedPreferences = await recorder.value()
        XCTAssertEqual(savedPreferences?.defaultProjectPath, preferences.defaultProjectPath)
        XCTAssertEqual(savedPreferences?.defaultAgentCommand, preferences.defaultAgentCommand)
    }

    func testSaveSettingsPersistsPreferencesAndDismissesSheet() async {
        let recorder = PreferencesRecorder()
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)

        let store = TestStore(
            initialState: AppFeature.State(
                isSettingsPresented: true,
                pipeline: PipelineFeature.State(
                    preferences: AppPreferences(
                        taskProviderConfiguration: providerConfiguration
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.appPreferencesClient.savePreferences = { await recorder.record($0) }
            $0.taskProviderClient.fetchTasks = { _ in [] }
        }

        await store.send(.saveSettingsButtonTapped) {
            $0.pipeline.preferences.hasCompletedOnboarding = true
            $0.isSavingSettings = true
        }
        await store.receive(\.pipeline.savePreferencesButtonTapped) {
            $0.pipeline.isSavingPreferences = true
        }
        await store.receive(\.pipeline.savePreferencesFinished) {
            $0.isSavingSettings = false
            $0.isSettingsPresented = false
            $0.pipeline.isSavingPreferences = false
        }
        await store.receive(\.refreshTasksButtonTapped) {
            $0.isLoadingTasks = true
        }
        await store.receive(\.taskResponse.success) {
            $0.isLoadingTasks = false
        }

        let savedPreferences = await recorder.value()
        XCTAssertEqual(savedPreferences?.hasCompletedOnboarding, true)
        XCTAssertEqual(savedPreferences?.taskProviderConfiguration.kind, .feishu)
        XCTAssertEqual(savedPreferences?.feishuProviderConfiguration.appID, configuration.appID)
    }

    func testMarkSelectedTaskDoneWritesBackStatus() async {
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)
        let task = LooperTask(
            id: "task-1",
            title: "Done me",
            summary: "Summary",
            status: .inReview,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let pipelineID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!
        let recorder = TaskStatusRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    pipelines: [
                        Pipeline(
                            id: pipelineID,
                            name: "demo",
                            projectPath: "/tmp/demo",
                            executionPath: "/tmp/demo",
                            agentCommand: "claude",
                            tmuxSessionName: "demo"
                        )
                    ],
                    selectedPipelineID: pipelineID,
                    preferences: AppPreferences(taskProviderConfiguration: providerConfiguration)
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
        }

        await store.send(.markSelectedTaskDoneButtonTapped) {
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .done
        }

        let events = await recorder.value()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.0, task.id)
        XCTAssertEqual(events.first?.1, .done)
    }

    func testTerminalEventAutoWritesInReviewStatus() async {
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)
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
            title: "Ship it",
            summary: "Summary",
            status: .inProgress,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let runningRun = Run(
            id: UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .running,
            trigger: .startTask,
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/looper-runs/running.log"
        )
        let finishedAt = Date(timeIntervalSince1970: 1_234_567_999)
        let finishedRun = runningRun.finished(
            status: .succeeded,
            exitCode: 0,
            finishedAt: finishedAt
        )
        let recorder = TaskStatusRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                runs: [runningRun],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline],
                    selectedPipelineID: pipeline.id,
                    preferences: AppPreferences(taskProviderConfiguration: providerConfiguration)
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.runStoreClient.saveRun = { _ in }
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
            $0.date.now = finishedAt
        }

        let event = PipelineTerminalEvent(
            pipelineID: pipeline.id,
            suggestedTaskStatus: .inReview,
            exitCode: 0
        )

        await store.send(.terminalEventReceived(event)) {
            $0.runs = [finishedRun]
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .inReview
        }

        let events = await recorder.value()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.0, task.id)
        XCTAssertEqual(events.first?.1, .inReview)
    }

    func testCreateLocalTaskInsertsTaskAndSelectsIt() async {
        let task = LooperTask(
            id: "local-task-1",
            title: "Local Task",
            summary: "Summary",
            status: .todo,
            source: "Local",
            repoPath: URL(filePath: "/tmp/local-project")
        )
        let draft = LocalTaskDraft(
            title: "Local Task",
            summary: "Summary",
            projectPath: "/tmp/local-project"
        )

        let store = TestStore(
            initialState: AppFeature.State(
                pipeline: PipelineFeature.State(
                    preferences: AppPreferences(
                        taskProviderConfiguration: TaskProviderConfiguration(kind: .local),
                        hasCompletedOnboarding: true
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.taskProviderClient.createTask = { _, _ in task }
        }

        await store.send(.createLocalTaskButtonTapped(draft)) {
            $0.isCreatingLocalTask = true
        }
        await store.receive(\.localTaskCreateResponse.success) {
            $0.isCreatingLocalTask = false
            $0.isLocalTaskComposerPresented = false
            $0.tasks = [task]
            $0.selectedTaskID = task.id
        }
    }

    // MARK: - Agent Process Events

    func testAgentToolUseUpdatesRunActivity() async {
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
            title: "Fix bug",
            summary: "Summary",
            status: .inProgress,
            source: "Local",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let runID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let run = Run(
            id: runID,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .running,
            trigger: .startTask,
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/looper-runs/\(runID.uuidString).log"
        )

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                runs: [run],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline],
                    selectedPipelineID: pipeline.id
                )
            )
        ) {
            AppFeature()
        }

        await store.send(.agentEventReceived(runID: runID, .initialized(sessionID: "sess-1", model: "opus"))) {
            $0.runs[id: runID]?.sessionID = "sess-1"
        }

        await store.send(.agentEventReceived(runID: runID, .toolUse(name: "Read", inputSummary: "/src/main.swift"))) {
            $0.runs[id: runID]?.toolCallCount = 1
            $0.runs[id: runID]?.currentActivity = "Read: /src/main.swift"
        }

        await store.send(.agentEventReceived(runID: runID, .toolResult(isError: false)))

        await store.send(.agentEventReceived(runID: runID, .toolUse(name: "Edit", inputSummary: "/src/main.swift"))) {
            $0.runs[id: runID]?.toolCallCount = 2
            $0.runs[id: runID]?.currentActivity = "Edit: /src/main.swift"
        }
    }

    func testAgentResultSuccessTransitionsToInReview() async {
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)
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
            title: "Fix bug",
            summary: "Summary",
            status: .inProgress,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let runID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let run = Run(
            id: runID,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .running,
            trigger: .startTask,
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/looper-runs/\(runID.uuidString).log"
        )
        let finishedAt = Date(timeIntervalSince1970: 1_234_567_999)
        let recorder = TaskStatusRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                runs: [run],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline],
                    selectedPipelineID: pipeline.id,
                    preferences: AppPreferences(taskProviderConfiguration: providerConfiguration)
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.runStoreClient.saveRun = { _ in }
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
            $0.date.now = finishedAt
        }

        let agentResult = AgentResult(
            sessionID: "sess-1",
            isError: false,
            durationMs: 12345,
            costUSD: 0.05,
            numTurns: 3,
            resultText: "Done"
        )

        await store.send(.agentEventReceived(runID: runID, .result(agentResult))) {
            var finished = run
            finished.sessionID = "sess-1"
            finished.costUSD = 0.05
            finished.currentActivity = nil
            finished.status = .succeeded
            finished.exitCode = 0
            finished.finishedAt = finishedAt
            $0.runs[id: runID] = finished
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .inReview
        }

        let events = await recorder.value()
        XCTAssertEqual(events.first?.1, .inReview)
    }

    func testAgentResultFailureTransitionsToTodo() async {
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)
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
            title: "Fix bug",
            summary: "Summary",
            status: .inProgress,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let runID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let run = Run(
            id: runID,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .running,
            trigger: .startTask,
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/looper-runs/\(runID.uuidString).log"
        )
        let finishedAt = Date(timeIntervalSince1970: 1_234_567_999)
        let recorder = TaskStatusRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                runs: [run],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline],
                    selectedPipelineID: pipeline.id,
                    preferences: AppPreferences(taskProviderConfiguration: providerConfiguration)
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.runStoreClient.saveRun = { _ in }
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
            $0.date.now = finishedAt
        }

        let agentResult = AgentResult(
            sessionID: "sess-1",
            isError: true,
            durationMs: 500,
            costUSD: 0.01,
            numTurns: 1,
            resultText: "Error"
        )

        await store.send(.agentEventReceived(runID: runID, .result(agentResult))) {
            var finished = run
            finished.sessionID = "sess-1"
            finished.costUSD = 0.01
            finished.currentActivity = nil
            finished.status = .failed
            finished.exitCode = 1
            finished.finishedAt = finishedAt
            $0.runs[id: runID] = finished
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .todo
        }

        let events = await recorder.value()
        XCTAssertEqual(events.first?.1, .todo)
    }

    func testCancelRunCallsAgentProcessCancel() async {
        let pipeline = Pipeline(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "demo",
            projectPath: "/tmp/demo",
            executionPath: "/tmp/demo",
            agentCommand: "claude",
            tmuxSessionName: "demo"
        )
        let runID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let run = Run(
            id: runID,
            pipelineID: pipeline.id,
            taskID: "task-1",
            status: .running,
            trigger: .startTask,
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/looper-runs/\(runID.uuidString).log"
        )

        actor CancelRecorder {
            var cancelledIDs: [UUID] = []
            func record(_ id: UUID) { cancelledIDs.append(id) }
            func value() -> [UUID] { cancelledIDs }
        }
        let cancelRecorder = CancelRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                runs: [run],
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline],
                    selectedPipelineID: pipeline.id
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.agentProcessClient.cancel = { runID in
                await cancelRecorder.record(runID)
            }
        }

        await store.send(.cancelRunButtonTapped(runID))

        let cancelled = await cancelRecorder.value()
        XCTAssertEqual(cancelled, [runID])
    }

    func testCancelInactiveRunIsNoOp() async {
        let runID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let run = Run(
            id: runID,
            pipelineID: UUID(),
            taskID: "task-1",
            status: .succeeded,
            trigger: .startTask,
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: Date(timeIntervalSince1970: 1_234_567_999),
            exitCode: 0,
            logPath: "/tmp/looper-runs/\(runID.uuidString).log"
        )

        let store = TestStore(
            initialState: AppFeature.State(runs: [run])
        ) {
            AppFeature()
        }

        // Should not call agentProcessClient.cancel since run is not active
        await store.send(.cancelRunButtonTapped(runID))
    }

    // MARK: - Worktree Cleanup

    func testAgentSuccessRemovesWorktree() async {
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)
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
            title: "Fix bug",
            summary: "Summary",
            status: .inProgress,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let runID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let run = Run(
            id: runID,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .running,
            trigger: .startTask,
            worktreePath: "/tmp/looper-worktrees/demo/looper/task-1-9E24E1C8",
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/looper-runs/\(runID.uuidString).log"
        )
        let finishedAt = Date(timeIntervalSince1970: 1_234_567_999)

        actor WorktreeRecorder {
            var removedPaths: [String] = []
            func record(_ path: String) { removedPaths.append(path) }
            func value() -> [String] { removedPaths }
        }
        let recorder = WorktreeRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                runs: [run],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline],
                    selectedPipelineID: pipeline.id,
                    preferences: AppPreferences(taskProviderConfiguration: providerConfiguration)
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.runStoreClient.saveRun = { _ in }
            $0.taskProviderClient.updateTaskStatus = { _, _, _ in }
            $0.gitWorktreeClient.removeWorktree = { _, worktreePath in
                await recorder.record(worktreePath)
            }
            $0.date.now = finishedAt
        }

        let agentResult = AgentResult(
            sessionID: "sess-1",
            isError: false,
            durationMs: 12345,
            costUSD: 0.05,
            numTurns: 3,
            resultText: "Done"
        )

        await store.send(.agentEventReceived(runID: runID, .result(agentResult))) {
            var finished = run
            finished.sessionID = "sess-1"
            finished.costUSD = 0.05
            finished.currentActivity = nil
            finished.status = .succeeded
            finished.exitCode = 0
            finished.finishedAt = finishedAt
            $0.runs[id: runID] = finished
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .inReview
        }

        let removed = await recorder.value()
        XCTAssertEqual(removed, ["/tmp/looper-worktrees/demo/looper/task-1-9E24E1C8"])
    }

    func testAgentFailurePreservesWorktree() async {
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)
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
            title: "Fix bug",
            summary: "Summary",
            status: .inProgress,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let runID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let run = Run(
            id: runID,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .running,
            trigger: .startTask,
            worktreePath: "/tmp/looper-worktrees/demo/looper/task-1-9E24E1C8",
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/looper-runs/\(runID.uuidString).log"
        )
        let finishedAt = Date(timeIntervalSince1970: 1_234_567_999)

        actor WorktreeRecorder {
            var removedPaths: [String] = []
            func record(_ path: String) { removedPaths.append(path) }
            func value() -> [String] { removedPaths }
        }
        let recorder = WorktreeRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                runs: [run],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline],
                    selectedPipelineID: pipeline.id,
                    preferences: AppPreferences(taskProviderConfiguration: providerConfiguration)
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.runStoreClient.saveRun = { _ in }
            $0.taskProviderClient.updateTaskStatus = { _, _, _ in }
            $0.gitWorktreeClient.removeWorktree = { _, worktreePath in
                await recorder.record(worktreePath)
            }
            $0.date.now = finishedAt
        }

        let agentResult = AgentResult(
            sessionID: "sess-1",
            isError: true,
            durationMs: 500,
            costUSD: 0.01,
            numTurns: 1,
            resultText: "Out of tokens"
        )

        await store.send(.agentEventReceived(runID: runID, .result(agentResult))) {
            var finished = run
            finished.sessionID = "sess-1"
            finished.costUSD = 0.01
            finished.currentActivity = nil
            finished.status = .failed
            finished.exitCode = 1
            finished.finishedAt = finishedAt
            $0.runs[id: runID] = finished
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .todo
        }

        let removed = await recorder.value()
        XCTAssertTrue(removed.isEmpty, "Failed run worktree should be preserved for debugging")
    }

    func testMarkDoneCleansUpAllWorktrees() async {
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)
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
            title: "Fix bug",
            summary: "Summary",
            status: .inReview,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let failedRun = Run(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .failed,
            trigger: .startTask,
            worktreePath: "/tmp/worktrees/run-1",
            startedAt: Date(timeIntervalSince1970: 1_234_567_000),
            finishedAt: Date(timeIntervalSince1970: 1_234_567_100),
            exitCode: 1,
            logPath: "/tmp/logs/run-1.log"
        )
        let succeededRun = Run(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000002")!,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .succeeded,
            trigger: .resumeTask,
            worktreePath: "/tmp/worktrees/run-2",
            startedAt: Date(timeIntervalSince1970: 1_234_567_200),
            finishedAt: Date(timeIntervalSince1970: 1_234_567_300),
            exitCode: 0,
            logPath: "/tmp/logs/run-2.log"
        )

        actor WorktreeRecorder {
            var removedPaths: [String] = []
            func record(_ path: String) { removedPaths.append(path) }
            func value() -> [String] { removedPaths }
        }
        let recorder = WorktreeRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                runs: [failedRun, succeededRun],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline],
                    selectedPipelineID: pipeline.id,
                    preferences: AppPreferences(taskProviderConfiguration: providerConfiguration)
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.taskProviderClient.updateTaskStatus = { _, _, _ in }
            $0.gitWorktreeClient.removeWorktree = { _, worktreePath in
                await recorder.record(worktreePath)
            }
        }

        await store.send(.markSelectedTaskDoneButtonTapped) {
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .done
        }

        let removed = await recorder.value()
        XCTAssertEqual(Set(removed), Set(["/tmp/worktrees/run-1", "/tmp/worktrees/run-2"]))
    }

    func testAgentSuccessPushesAndCreatesPR() async {
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)
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
            title: "Fix login bug",
            summary: "Users can't log in after password reset",
            status: .inProgress,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let runID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let run = Run(
            id: runID,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .running,
            trigger: .startTask,
            worktreePath: "/tmp/looper-worktrees/demo/looper/task-1-9E24E1C8",
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/looper-runs/\(runID.uuidString).log"
        )
        let finishedAt = Date(timeIntervalSince1970: 1_234_567_999)

        actor GitActionRecorder {
            var pushedPaths: [String] = []
            var prCalls: [(path: String, title: String, body: String)] = []
            var removedPaths: [String] = []
            func recordPush(_ path: String) { pushedPaths.append(path) }
            func recordPR(_ path: String, _ title: String, _ body: String) { prCalls.append((path, title, body)) }
            func recordRemove(_ path: String) { removedPaths.append(path) }
        }
        let recorder = GitActionRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                runs: [run],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline],
                    selectedPipelineID: pipeline.id,
                    preferences: AppPreferences(
                        postRunGitAction: .pushAndPR,
                        taskProviderConfiguration: providerConfiguration
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.runStoreClient.saveRun = { _ in }
            $0.taskProviderClient.updateTaskStatus = { _, _, _ in }
            $0.gitWorktreeClient.pushBranch = { path in
                await recorder.recordPush(path)
            }
            $0.gitWorktreeClient.createPullRequest = { path, title, body in
                await recorder.recordPR(path, title, body)
                return "https://github.com/test/repo/pull/1"
            }
            $0.gitWorktreeClient.removeWorktree = { _, path in
                await recorder.recordRemove(path)
            }
            $0.date.now = finishedAt
        }

        let agentResult = AgentResult(
            sessionID: "sess-1",
            isError: false,
            durationMs: 12345,
            costUSD: 0.05,
            numTurns: 3,
            resultText: "Done"
        )

        await store.send(.agentEventReceived(runID: runID, .result(agentResult))) {
            var finished = run
            finished.sessionID = "sess-1"
            finished.costUSD = 0.05
            finished.currentActivity = nil
            finished.status = .succeeded
            finished.exitCode = 0
            finished.finishedAt = finishedAt
            $0.runs[id: runID] = finished
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .inReview
        }

        let worktreePath = "/tmp/looper-worktrees/demo/looper/task-1-9E24E1C8"
        let pushed = await recorder.pushedPaths
        XCTAssertEqual(pushed, [worktreePath], "Branch should be pushed to remote")

        let prCalls = await recorder.prCalls
        XCTAssertEqual(prCalls.count, 1, "PR should be created")
        XCTAssertEqual(prCalls.first?.title, "Fix login bug")
        XCTAssertEqual(prCalls.first?.body, "Users can't log in after password reset")

        let removed = await recorder.removedPaths
        XCTAssertEqual(removed, [worktreePath], "Worktree should be cleaned up after push")
    }

    func testAgentSuccessWithNoneActionSkipsPush() async {
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)
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
            title: "Fix bug",
            summary: "Summary",
            status: .inProgress,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let runID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let run = Run(
            id: runID,
            pipelineID: pipeline.id,
            taskID: task.id,
            status: .running,
            trigger: .startTask,
            worktreePath: "/tmp/looper-worktrees/demo/looper/task-1-9E24E1C8",
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            finishedAt: nil,
            exitCode: nil,
            logPath: "/tmp/looper-runs/\(runID.uuidString).log"
        )
        let finishedAt = Date(timeIntervalSince1970: 1_234_567_999)

        actor GitActionRecorder {
            var pushedPaths: [String] = []
            var removedPaths: [String] = []
            func recordPush(_ path: String) { pushedPaths.append(path) }
            func recordRemove(_ path: String) { removedPaths.append(path) }
        }
        let recorder = GitActionRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                runs: [run],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
                    pipelines: [pipeline],
                    selectedPipelineID: pipeline.id,
                    preferences: AppPreferences(
                        postRunGitAction: .none,
                        taskProviderConfiguration: providerConfiguration
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.runStoreClient.saveRun = { _ in }
            $0.taskProviderClient.updateTaskStatus = { _, _, _ in }
            $0.gitWorktreeClient.pushBranch = { path in
                await recorder.recordPush(path)
            }
            $0.gitWorktreeClient.removeWorktree = { _, path in
                await recorder.recordRemove(path)
            }
            $0.date.now = finishedAt
        }

        let agentResult = AgentResult(
            sessionID: "sess-1",
            isError: false,
            durationMs: 12345,
            costUSD: 0.05,
            numTurns: 3,
            resultText: "Done"
        )

        await store.send(.agentEventReceived(runID: runID, .result(agentResult))) {
            var finished = run
            finished.sessionID = "sess-1"
            finished.costUSD = 0.05
            finished.currentActivity = nil
            finished.status = .succeeded
            finished.exitCode = 0
            finished.finishedAt = finishedAt
            $0.runs[id: runID] = finished
            $0.updatingTaskIDs = [task.id]
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .inReview
        }

        let pushed = await recorder.pushedPaths
        XCTAssertTrue(pushed.isEmpty, "Should not push when action is .none")

        let removed = await recorder.removedPaths
        XCTAssertEqual(removed, ["/tmp/looper-worktrees/demo/looper/task-1-9E24E1C8"],
                       "Worktree should still be cleaned up even with .none action")
    }

    func testPipelineDraftInfersNameFromInput() {
        let namedDraft = PipelineDraft(
            name: "Payment Hardening",
            projectPath: "/tmp/repo",
            agentCommand: "claude"
        )
        let unnamedDraft = PipelineDraft(
            name: "",
            projectPath: "/tmp/Feature Repo",
            agentCommand: "claude"
        )

        XCTAssertEqual(namedDraft.inferredName, "Payment Hardening")
        XCTAssertEqual(unnamedDraft.inferredName, "Feature Repo")
    }
}
