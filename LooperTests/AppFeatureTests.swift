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
        XCTAssertNil(store.state.selectedTaskID)
        XCTAssertTrue(store.state.pipeline.pipelines.isEmpty)
        XCTAssertNil(store.state.pipeline.selectedPipelineID)
    }

    func testOnAppearShowsSetupWizardWhenSetupIncomplete() async {
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
        await store.receive(\.pipeline.bootstrapResponse.success) {
            $0.isSetupWizardPresented = true
            $0.setupStep = .welcome
        }
    }

    func testOnAppearLoadsTasksAndSelectsFirstTask() async {
        let firstTask = LooperTask(
            id: "task-1",
            title: "First",
            summary: "First summary",
            status: .pending,
            source: "Mock Feishu",
            repoPath: URL(filePath: "/tmp/first")
        )
        let secondTask = LooperTask(
            id: "task-2",
            title: "Second",
            summary: "Second summary",
            status: .pending,
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
        await store.receive(\.refreshTasksButtonTapped) {
            $0.isLoadingTasks = true
        }
        await store.receive(\.taskResponse.success) {
            $0.isLoadingTasks = false
            $0.tasks = [firstTask, secondTask]
            $0.selectedTaskID = firstTask.id
        }
    }

    func testStartSelectedTaskTriggersPipelineCreation() async {
        let task = LooperTask(
            id: "task-1",
            title: "Start me",
            summary: "Summary",
            status: .pending,
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
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
        }

        await store.send(.startSelectedTaskButtonTapped)
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
            $0.updatingTaskIDs = [task.id]
            $0.pipeline.preferences = AppPreferences(
                defaultProjectPath: "/tmp/demo",
                defaultAgentCommand: "claude",
                lastSelectedPipelineID: pipeline.id
            )
        }
        await store.receive(\.taskStatusUpdateResponse.success) {
            $0.updatingTaskIDs = []
            $0.tasks[id: task.id]?.status = .developing
        }

        let events = await recorder.value()
        XCTAssertEqual(events.first?.0, task.id)
        XCTAssertEqual(events.first?.1, .developing)
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

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.pipelineStoreClient.fetchPipelines = { [pipeline] }
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
        await store.receive(\.refreshTasksButtonTapped) {
            $0.isLoadingTasks = true
        }
        await store.receive(\.taskResponse.success) {
            $0.isLoadingTasks = false
        }
        await store.receive(\.pipeline.selectPipeline) {
            $0.pipeline.selectedPipelineID = nil
            $0.pipeline.preferences.lastSelectedPipelineID = nil
        }
    }

    func testSelectingTaskSelectsMatchingPipeline() async {
        let task = LooperTask(
            id: "task-1",
            title: "Task",
            summary: "Summary",
            status: .pending,
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
        await store.receive(\.pipeline.selectPipeline)

        let savedPreferences = await recorder.value()
        XCTAssertEqual(savedPreferences?.defaultProjectPath, preferences.defaultProjectPath)
        XCTAssertEqual(savedPreferences?.defaultAgentCommand, preferences.defaultAgentCommand)
    }

    func testFinishSetupPersistsPreferencesAndDismissesWizard() async {
        let recorder = PreferencesRecorder()
        let configuration = FeishuTaskProviderConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
        let providerConfiguration = TaskProviderConfiguration(kind: .feishu, feishu: configuration)
        let environment = EnvironmentSetupReport(
            git: .init(name: "Git", command: "git", isInstalled: true, resolvedPath: "/usr/bin/git"),
            claude: .init(name: "Claude CLI", command: "claude", isInstalled: true, resolvedPath: "/opt/homebrew/bin/claude"),
            tmux: .init(name: "tmux", command: "tmux", isInstalled: false, resolvedPath: nil)
        )

        let store = TestStore(
            initialState: AppFeature.State(
                isSetupWizardPresented: true,
                setupStep: .finish,
                environmentReport: environment,
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

        await store.send(.finishSetupButtonTapped) {
            $0.pipeline.preferences.hasCompletedOnboarding = true
            $0.isFinishingSetup = true
        }
        await store.receive(\.pipeline.savePreferencesButtonTapped) {
            $0.pipeline.isSavingPreferences = true
        }
        await store.receive(\.pipeline.savePreferencesFinished) {
            $0.isFinishingSetup = false
            $0.isSetupWizardPresented = false
            $0.setupStep = .finish
            $0.pipeline.isSavingPreferences = false
        }
        await store.receive(\.refreshTasksButtonTapped) {
            $0.isLoadingTasks = true
        }
        await store.receive(\.taskResponse.success) {
            $0.isLoadingTasks = false
        }
        await store.receive(\.pipeline.selectPipeline)

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
            status: .developing,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let recorder = TaskStatusRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                selectedTaskID: task.id,
                pipeline: PipelineFeature.State(
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

    func testTerminalEventAutoWritesDoneStatus() async {
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
            status: .developing,
            source: "Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let recorder = TaskStatusRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
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
            $0.taskProviderClient.updateTaskStatus = { taskID, status, _ in
                await recorder.record(taskID, status)
            }
        }

        let event = PipelineTerminalEvent(
            pipelineID: pipeline.id,
            suggestedTaskStatus: .done,
            exitCode: 0
        )

        await store.send(.terminalEventReceived(event)) {
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

    func testCreateLocalTaskInsertsTaskAndSelectsIt() async {
        let task = LooperTask(
            id: "local-task-1",
            title: "Local Task",
            summary: "Summary",
            status: .pending,
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
