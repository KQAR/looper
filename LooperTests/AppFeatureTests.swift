import ComposableArchitecture
import XCTest

@testable import Looper

actor PreferencesRecorder {
    private var preferences: WorkspacePreferences?

    func record(_ preferences: WorkspacePreferences) {
        self.preferences = preferences
    }

    func value() -> WorkspacePreferences? {
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
    func testInitialStateHasNoTasksOrWorkspaces() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        XCTAssertTrue(store.state.tasks.isEmpty)
        XCTAssertNil(store.state.selectedTaskID)
        XCTAssertTrue(store.state.workspace.workspaces.isEmpty)
        XCTAssertNil(store.state.workspace.selectedWorkspaceID)
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
        let configuration = TaskBoardConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.taskBoardClient.fetchTasks = { _ in [firstTask, secondTask] }
            $0.workspaceStoreClient.fetchWorkspaces = { [] }
            $0.workspacePreferencesClient.fetchPreferences = {
                WorkspacePreferences(taskBoardConfiguration: configuration)
            }
        }

        await store.send(.onAppear)
        await store.receive(\.workspace.onAppear)
        await store.receive(\.workspace.bootstrapResponse.success) {
            $0.workspace.preferences = WorkspacePreferences(taskBoardConfiguration: configuration)
            $0.workspace.composer = WorkspacePreferences(taskBoardConfiguration: configuration).draft
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

    func testStartSelectedTaskTriggersWorkspaceCreation() async {
        let task = LooperTask(
            id: "task-1",
            title: "Start me",
            summary: "Summary",
            status: .pending,
            source: "Mock Feishu",
            repoPath: URL(filePath: "/tmp/demo")
        )
        let workspace = CodingWorkspace(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "demo",
            repositoryRootPath: "/tmp/demo",
            worktreePath: "/tmp/demo",
            branchName: "",
            baseBranch: "",
            agentCommand: "claude",
            tmuxSessionName: "demo"
        )

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                selectedTaskID: task.id,
                workspace: WorkspaceFeature.State()
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.repoManagerClient.createWorkspace = { _ in workspace }
            $0.workspaceStoreClient.saveWorkspace = { _ in }
            $0.workspacePreferencesClient.savePreferences = { _ in }
            $0.terminalWorkspaceClient.upsertSession = { _ in }
            $0.terminalWorkspaceClient.focusSession = { _ in }
            $0.terminalWorkspaceClient.bootstrapSession = { _ in }
        }

        await store.send(.startSelectedTaskButtonTapped)
        await store.receive(\.workspace.createWorkspaceFromDefaults) {
            $0.workspace.composer = WorkspaceDraft(
                name: "",
                repositoryPath: "/tmp/demo",
                agentCommand: "claude"
            )
            $0.workspace.isCreatingWorkspace = true
        }
        await store.receive(\.workspace.createWorkspaceResponse.success) {
            $0.workspace.isCreatingWorkspace = false
            $0.workspace.workspaces = [workspace]
            $0.workspace.selectedWorkspaceID = workspace.id
            $0.workspace.preferences = WorkspacePreferences(
                defaultRepositoryPath: "/tmp/demo",
                defaultAgentCommand: "claude",
                lastSelectedWorkspaceID: workspace.id
            )
        }
    }

    func testOnAppearLoadsPersistedWorkspaces() async {
        let workspace = CodingWorkspace(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "Persisted Workspace",
            repositoryRootPath: "/tmp/repo",
            worktreePath: "/tmp/.looper-worktrees/repo/persisted-workspace",
            branchName: "looper/persisted-workspace",
            baseBranch: "main",
            agentCommand: "claude",
            tmuxSessionName: "repo-looper-persisted-workspace"
        )

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.workspaceStoreClient.fetchWorkspaces = { [workspace] }
            $0.workspacePreferencesClient.fetchPreferences = {
                WorkspacePreferences(
                    defaultRepositoryPath: "/tmp/repo",
                    defaultAgentCommand: "claude --dangerously-skip-permissions",
                    lastSelectedWorkspaceID: workspace.id
                )
            }
            $0.terminalWorkspaceClient.upsertSession = { _ in }
        }

        await store.send(.workspace(.onAppear))
        await store.receive(\.workspace.bootstrapResponse.success) {
            $0.workspace.workspaces = [workspace]
            $0.workspace.selectedWorkspaceID = workspace.id
            $0.workspace.preferences = WorkspacePreferences(
                defaultRepositoryPath: "/tmp/repo",
                defaultAgentCommand: "claude --dangerously-skip-permissions",
                lastSelectedWorkspaceID: workspace.id
            )
            $0.workspace.composer = WorkspacePreferences(
                defaultRepositoryPath: "/tmp/repo",
                defaultAgentCommand: "claude --dangerously-skip-permissions",
                lastSelectedWorkspaceID: workspace.id
            ).draft
        }
    }

    func testSelectingTaskSelectsMatchingWorkspace() async {
        let task = LooperTask(
            id: "task-1",
            title: "Task",
            summary: "Summary",
            status: .pending,
            source: "Mock Feishu",
            repoPath: URL(filePath: "/tmp/repo")
        )
        let workspaceID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!
        let workspace = CodingWorkspace(
            id: workspaceID,
            name: "Repo",
            repositoryRootPath: "/tmp/repo",
            worktreePath: "/tmp/repo",
            branchName: "",
            baseBranch: "",
            agentCommand: "claude",
            tmuxSessionName: "repo"
        )

        let store = TestStore(
            initialState: AppFeature.State(
                tasks: [task],
                workspace: WorkspaceFeature.State(workspaces: [workspace])
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.workspacePreferencesClient.savePreferences = { _ in }
            $0.terminalWorkspaceClient.focusSession = { _ in }
        }

        await store.send(.selectTask(task.id)) {
            $0.selectedTaskID = task.id
            $0.workspace.selectedWorkspaceID = workspaceID
        }
        await store.receive(\.workspace.selectWorkspace) {
            $0.workspace.preferences.lastSelectedWorkspaceID = workspaceID
        }
    }

    func testSelectingWorkspacePersistsSelection() async {
        let firstID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!
        let secondID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let first = CodingWorkspace(
            id: firstID,
            name: "First",
            repositoryRootPath: "/tmp/repo",
            worktreePath: "/tmp/first",
            branchName: "looper/first",
            baseBranch: "main",
            agentCommand: "claude",
            tmuxSessionName: "repo-first"
        )
        let second = CodingWorkspace(
            id: secondID,
            name: "Second",
            repositoryRootPath: "/tmp/repo",
            worktreePath: "/tmp/second",
            branchName: "looper/second",
            baseBranch: "main",
            agentCommand: "claude",
            tmuxSessionName: "repo-second"
        )
        let recorder = PreferencesRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                workspace: WorkspaceFeature.State(
                    workspaces: [first, second],
                    selectedWorkspaceID: firstID,
                    preferences: WorkspacePreferences(
                        defaultRepositoryPath: "/tmp/repo",
                        defaultAgentCommand: "claude",
                        lastSelectedWorkspaceID: firstID
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.workspacePreferencesClient.savePreferences = { await recorder.record($0) }
            $0.terminalWorkspaceClient.focusSession = { _ in }
        }

        await store.send(.workspace(.selectWorkspace(secondID))) {
            $0.workspace.selectedWorkspaceID = secondID
            $0.workspace.preferences.lastSelectedWorkspaceID = secondID
        }

        let savedPreferences = await recorder.value()
        XCTAssertEqual(savedPreferences?.lastSelectedWorkspaceID, secondID)
    }

    func testBootstrapRestoresLastSelectedWorkspace() async {
        let first = CodingWorkspace(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "First",
            repositoryRootPath: "/tmp/first",
            worktreePath: "/tmp/first",
            branchName: "",
            baseBranch: "",
            agentCommand: "claude",
            tmuxSessionName: "first"
        )
        let second = CodingWorkspace(
            id: UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!,
            name: "Second",
            repositoryRootPath: "/tmp/second",
            worktreePath: "/tmp/second",
            branchName: "",
            baseBranch: "",
            agentCommand: "claude",
            tmuxSessionName: "second"
        )

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.workspaceStoreClient.fetchWorkspaces = { [first, second] }
            $0.workspacePreferencesClient.fetchPreferences = {
                WorkspacePreferences(
                    defaultRepositoryPath: "/tmp",
                    defaultAgentCommand: "claude",
                    lastSelectedWorkspaceID: second.id
                )
            }
            $0.terminalWorkspaceClient.upsertSession = { _ in }
        }

        await store.send(.workspace(.onAppear))
        await store.receive(\.workspace.bootstrapResponse.success) {
            $0.workspace.workspaces = [first, second]
            $0.workspace.selectedWorkspaceID = second.id
            $0.workspace.preferences = WorkspacePreferences(
                defaultRepositoryPath: "/tmp",
                defaultAgentCommand: "claude",
                lastSelectedWorkspaceID: second.id
            )
            $0.workspace.composer = WorkspacePreferences(
                defaultRepositoryPath: "/tmp",
                defaultAgentCommand: "claude",
                lastSelectedWorkspaceID: second.id
            ).draft
        }
    }

    func testQuickSwitchSelectsNextWorkspace() async {
        let firstID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!
        let secondID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let first = CodingWorkspace(
            id: firstID,
            name: "First",
            repositoryRootPath: "/tmp/first",
            worktreePath: "/tmp/first",
            branchName: "",
            baseBranch: "",
            agentCommand: "claude",
            tmuxSessionName: "first"
        )
        let second = CodingWorkspace(
            id: secondID,
            name: "Second",
            repositoryRootPath: "/tmp/second",
            worktreePath: "/tmp/second",
            branchName: "",
            baseBranch: "",
            agentCommand: "claude",
            tmuxSessionName: "second"
        )
        let recorder = PreferencesRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                workspace: WorkspaceFeature.State(
                    workspaces: [first, second],
                    selectedWorkspaceID: firstID,
                    preferences: WorkspacePreferences(
                        defaultRepositoryPath: "/tmp",
                        defaultAgentCommand: "claude",
                        lastSelectedWorkspaceID: firstID
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.workspacePreferencesClient.savePreferences = { await recorder.record($0) }
            $0.terminalWorkspaceClient.focusSession = { _ in }
        }

        await store.send(.workspace(.selectNextWorkspace))
        await store.receive(\.workspace.selectWorkspace) {
            $0.workspace.selectedWorkspaceID = secondID
            $0.workspace.preferences.lastSelectedWorkspaceID = secondID
        }

        let savedPreferences = await recorder.value()
        XCTAssertEqual(savedPreferences?.lastSelectedWorkspaceID, secondID)
    }

    func testOpenProjectUsesDefaultsAndCreatesWorkspace() async {
        let workspace = CodingWorkspace(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "demo",
            repositoryRootPath: "/tmp/demo",
            worktreePath: "/tmp/demo",
            branchName: "",
            baseBranch: "",
            agentCommand: "claude --resume",
            tmuxSessionName: "demo"
        )
        actor RequestRecorder {
            var request: CreateWorkspaceRequest?
            func record(_ request: CreateWorkspaceRequest) { self.request = request }
            func value() -> CreateWorkspaceRequest? { request }
        }
        let recorder = RequestRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                workspace: WorkspaceFeature.State(
                    preferences: WorkspacePreferences(
                        defaultRepositoryPath: "",
                        defaultAgentCommand: "claude --resume",
                        lastSelectedWorkspaceID: nil
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.projectDirectoryPickerClient.pickDirectory = { "/tmp/demo" }
            $0.repoManagerClient.createWorkspace = { request in
                await recorder.record(request)
                return workspace
            }
            $0.workspaceStoreClient.saveWorkspace = { _ in }
            $0.workspacePreferencesClient.savePreferences = { _ in }
            $0.terminalWorkspaceClient.upsertSession = { _ in }
            $0.terminalWorkspaceClient.focusSession = { _ in }
            $0.terminalWorkspaceClient.bootstrapSession = { _ in }
        }

        await store.send(.workspace(.openProjectButtonTapped))
        await store.receive(\.workspace.openProjectResponse)
        await store.receive(\.workspace.createWorkspaceFromDefaults) {
            $0.workspace.composer = WorkspaceDraft(
                name: "",
                repositoryPath: "/tmp/demo",
                agentCommand: "claude --resume"
            )
            $0.workspace.isCreatingWorkspace = true
        }
        await store.receive(\.workspace.createWorkspaceResponse.success) {
            $0.workspace.isCreatingWorkspace = false
            $0.workspace.workspaces = [workspace]
            $0.workspace.selectedWorkspaceID = workspace.id
            $0.workspace.preferences = WorkspacePreferences(
                defaultRepositoryPath: "/tmp/demo",
                defaultAgentCommand: "claude --resume",
                lastSelectedWorkspaceID: workspace.id
            )
        }

        let capturedRequest = await recorder.value()
        XCTAssertEqual(capturedRequest?.repositoryPath, "/tmp/demo")
        XCTAssertEqual(capturedRequest?.agentCommand, "claude --resume")
        XCTAssertEqual(capturedRequest?.name, "demo")
    }

    func testSavingPreferencesPersistsDefaults() async {
        let recorder = PreferencesRecorder()
        let preferences = WorkspacePreferences(
            defaultRepositoryPath: "/tmp/repo",
            defaultAgentCommand: "claude --model sonnet",
            lastSelectedWorkspaceID: nil
        )
        let initialWorkspaceState = WorkspaceFeature.State(
            preferences: preferences
        )
        let initialState = AppFeature.State(
            workspace: initialWorkspaceState
        )

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.workspacePreferencesClient.savePreferences = { await recorder.record($0) }
        }

        await store.send(.workspace(.savePreferencesButtonTapped)) {
            $0.workspace.isSavingPreferences = true
        }
        await store.receive(\.workspace.savePreferencesFinished) {
            $0.workspace.isSavingPreferences = false
        }

        let savedPreferences = await recorder.value()
        XCTAssertEqual(savedPreferences?.defaultRepositoryPath, preferences.defaultRepositoryPath)
        XCTAssertEqual(savedPreferences?.defaultAgentCommand, preferences.defaultAgentCommand)
    }

    func testMarkSelectedTaskDoneWritesBackStatus() async {
        let configuration = TaskBoardConfiguration(
            appID: "cli_xxx",
            appSecret: "secret",
            appToken: "app_token",
            tableID: "tbl_tasks"
        )
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
                workspace: WorkspaceFeature.State(
                    preferences: WorkspacePreferences(taskBoardConfiguration: configuration)
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.taskBoardClient.updateTaskStatus = { taskID, status, _ in
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

    func testWorkspaceBranchNameNormalizesInput() {
        let namedDraft = WorkspaceDraft(
            name: "Payment Hardening",
            repositoryPath: "/tmp/repo",
            agentCommand: "claude"
        )
        let unnamedDraft = WorkspaceDraft(
            name: "",
            repositoryPath: "/tmp/Feature Repo",
            agentCommand: "claude"
        )

        XCTAssertEqual(namedDraft.inferredName, "Payment Hardening")
        XCTAssertEqual(unnamedDraft.inferredName, "Feature Repo")
    }
}
