import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    @Dependency(\.taskBoardClient) var taskBoardClient
    @Dependency(\.terminalWorkspaceClient) var terminalWorkspaceClient

    struct TaskStatusUpdate: Equatable, Sendable {
        var taskID: LooperTask.ID
        var status: LooperTask.Status
    }

    struct TaskStatusFailure: LocalizedError, Equatable, Sendable {
        var taskID: LooperTask.ID
        var description: String

        var errorDescription: String? {
            description
        }
    }

    @ObservableState
    struct State: Equatable {
        var tasks: IdentifiedArrayOf<LooperTask> = []
        var selectedTaskID: LooperTask.ID?
        var isLoadingTasks = false
        var updatingTaskIDs: Set<LooperTask.ID> = []
        var taskBoardErrorMessage: String?
        var workspace = WorkspaceFeature.State()
    }

    enum Action {
        case dismissTaskBoardError
        case markSelectedTaskDoneButtonTapped
        case markSelectedTaskFailedButtonTapped
        case onAppear
        case refreshTasksButtonTapped
        case selectTask(LooperTask.ID?)
        case startSelectedTaskButtonTapped
        case taskResponse(Result<[LooperTask], TaskBoardFailure>)
        case taskStatusUpdateResponse(Result<TaskStatusUpdate, TaskStatusFailure>)
        case terminalEventReceived(WorkspaceTerminalEvent)
        case workspace(WorkspaceFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.workspace, action: \.workspace) {
            WorkspaceFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    .send(.workspace(.onAppear)),
                    .run { send in
                        let events = await terminalWorkspaceClient.events()
                        for await event in events {
                            await send(.terminalEventReceived(event))
                        }
                    }
                )

            case .refreshTasksButtonTapped:
                let configuration = state.workspace.preferences.taskBoardConfiguration
                guard configuration.isConfigured else {
                    state.taskBoardErrorMessage = "Configure Feishu App ID, secret, app token, and table ID first."
                    return .none
                }

                state.isLoadingTasks = true
                state.taskBoardErrorMessage = nil

                return .run { send in
                    do {
                        let tasks = try await taskBoardClient.fetchTasks(configuration)
                        await send(.taskResponse(.success(tasks)))
                    } catch {
                        await send(
                            .taskResponse(
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case let .taskResponse(.success(tasks)):
                state.isLoadingTasks = false
                state.tasks = IdentifiedArray(uniqueElements: tasks)

                if let selectedTaskID = state.selectedTaskID,
                   state.tasks[id: selectedTaskID] != nil
                {
                    return syncWorkspaceSelection(state: &state)
                }

                if let matchingTaskID = taskIDMatchingSelectedWorkspace(state: state) {
                    state.selectedTaskID = matchingTaskID
                } else {
                    state.selectedTaskID = state.tasks.ids.first
                }

                return syncWorkspaceSelection(state: &state)

            case let .taskResponse(.failure(error)):
                state.isLoadingTasks = false
                state.taskBoardErrorMessage = error.description
                return .none

            case let .selectTask(id):
                state.selectedTaskID = id
                return syncWorkspaceSelection(state: &state)

            case .startSelectedTaskButtonTapped:
                guard let task = selectedTask(state: state) else { return .none }

                if let existingWorkspaceID = workspaceID(for: task, in: state.workspace.workspaces) {
                    state.selectedTaskID = task.id
                    var effects: [Effect<Action>] = [
                        .send(.workspace(.selectWorkspace(existingWorkspaceID))),
                        .send(.workspace(.attachSelectedWorkspaceButtonTapped)),
                    ]

                    if state.workspace.preferences.taskBoardConfiguration.isConfigured {
                        effects.append(
                            writeTaskStatus(
                                taskID: task.id,
                                status: .developing,
                                configuration: state.workspace.preferences.taskBoardConfiguration,
                                state: &state,
                                updateStatus: taskBoardClient.updateTaskStatus
                            )
                        )
                    }

                    return .merge(effects)
                }

                guard let repoPath = task.repoPath?.path(percentEncoded: false) else {
                    return .none
                }

                return .send(.workspace(.createWorkspaceFromDefaults(repoPath)))

            case let .workspace(.createWorkspaceResponse(.success(workspace))):
                if let taskID = taskID(matching: workspace, in: state.tasks) {
                    state.selectedTaskID = taskID

                    if state.workspace.preferences.taskBoardConfiguration.isConfigured {
                        return writeTaskStatus(
                            taskID: taskID,
                            status: .developing,
                            configuration: state.workspace.preferences.taskBoardConfiguration,
                            state: &state,
                            updateStatus: taskBoardClient.updateTaskStatus
                        )
                    }
                }
                return .none

            case let .workspace(.bootstrapResponse(.success(payload))):
                if state.selectedTaskID == nil {
                    state.selectedTaskID = taskIDMatchingSelectedWorkspace(state: state) ?? state.tasks.ids.first
                }

                guard payload.preferences.taskBoardConfiguration.isConfigured else {
                    return .none
                }

                return .send(.refreshTasksButtonTapped)

            case .workspace(.savePreferencesFinished):
                guard state.workspace.preferences.taskBoardConfiguration.isConfigured else {
                    return .none
                }

                return .send(.refreshTasksButtonTapped)

            case .markSelectedTaskDoneButtonTapped:
                guard let task = selectedTask(state: state) else { return .none }
                guard state.workspace.preferences.taskBoardConfiguration.isConfigured else {
                    state.taskBoardErrorMessage = "Configure Feishu task board settings before writing status back."
                    return .none
                }

                return writeTaskStatus(
                    taskID: task.id,
                    status: .done,
                    configuration: state.workspace.preferences.taskBoardConfiguration,
                    state: &state,
                    updateStatus: taskBoardClient.updateTaskStatus
                )

            case .markSelectedTaskFailedButtonTapped:
                guard let task = selectedTask(state: state) else { return .none }
                guard state.workspace.preferences.taskBoardConfiguration.isConfigured else {
                    state.taskBoardErrorMessage = "Configure Feishu task board settings before writing status back."
                    return .none
                }

                return writeTaskStatus(
                    taskID: task.id,
                    status: .failed,
                    configuration: state.workspace.preferences.taskBoardConfiguration,
                    state: &state,
                    updateStatus: taskBoardClient.updateTaskStatus
                )

            case let .taskStatusUpdateResponse(.success(update)):
                state.updatingTaskIDs.remove(update.taskID)
                updateTaskStatus(id: update.taskID, status: update.status, state: &state)
                return .none

            case let .taskStatusUpdateResponse(.failure(error)):
                state.updatingTaskIDs.remove(error.taskID)
                state.taskBoardErrorMessage = error.description
                return .none

            case let .terminalEventReceived(event):
                guard let suggestedStatus = event.suggestedTaskStatus else { return .none }
                guard let workspace = state.workspace.workspaces[id: event.workspaceID] else { return .none }
                guard let taskID = taskID(matching: workspace, in: state.tasks) else { return .none }
                guard let task = state.tasks[id: taskID] else { return .none }
                guard task.status == .developing else { return .none }

                if state.workspace.preferences.taskBoardConfiguration.isConfigured {
                    return writeTaskStatus(
                        taskID: taskID,
                        status: suggestedStatus,
                        configuration: state.workspace.preferences.taskBoardConfiguration,
                        state: &state,
                        updateStatus: taskBoardClient.updateTaskStatus
                    )
                }

                updateTaskStatus(id: taskID, status: suggestedStatus, state: &state)
                return .none

            case .dismissTaskBoardError:
                state.taskBoardErrorMessage = nil
                return .none

            case .workspace:
                return .none
            }
        }
    }
}

private func selectedTask(state: AppFeature.State) -> LooperTask? {
    guard let selectedTaskID = state.selectedTaskID else { return nil }
    return state.tasks[id: selectedTaskID]
}

private func syncWorkspaceSelection(state: inout AppFeature.State) -> Effect<AppFeature.Action> {
    guard let task = selectedTask(state: state) else {
        return .send(.workspace(.selectWorkspace(nil)))
    }

    guard let workspaceID = workspaceID(for: task, in: state.workspace.workspaces) else {
        state.workspace.selectedWorkspaceID = nil
        return .none
    }

    state.workspace.selectedWorkspaceID = workspaceID
    return .send(.workspace(.selectWorkspace(workspaceID)))
}

private func workspaceID(
    for task: LooperTask,
    in workspaces: IdentifiedArrayOf<CodingWorkspace>
) -> UUID? {
    guard let taskPath = task.repoPath?.standardizedFileURL.path(percentEncoded: false) else {
        return nil
    }

    return workspaces.first {
        $0.worktreeURL.standardizedFileURL.path(percentEncoded: false) == taskPath
    }?.id
}

private func taskID(
    matching workspace: CodingWorkspace,
    in tasks: IdentifiedArrayOf<LooperTask>
) -> LooperTask.ID? {
    let workspacePath = workspace.worktreeURL.standardizedFileURL.path(percentEncoded: false)

    return tasks.first {
        $0.repoPath?.standardizedFileURL.path(percentEncoded: false) == workspacePath
    }?.id
}

private func taskIDMatchingSelectedWorkspace(state: AppFeature.State) -> LooperTask.ID? {
    guard let workspaceID = state.workspace.selectedWorkspaceID,
          let workspace = state.workspace.workspaces[id: workspaceID]
    else {
        return nil
    }

    return taskID(matching: workspace, in: state.tasks)
}

private func updateTaskStatus(
    id: LooperTask.ID,
    status: LooperTask.Status,
    state: inout AppFeature.State
) {
    guard state.tasks[id: id] != nil else { return }
    state.tasks[id: id]?.status = status
}

private func writeTaskStatus(
    taskID: LooperTask.ID,
    status: LooperTask.Status,
    configuration: TaskBoardConfiguration,
    state: inout AppFeature.State,
    updateStatus: @escaping @Sendable (LooperTask.ID, LooperTask.Status, TaskBoardConfiguration) async throws -> Void
) -> Effect<AppFeature.Action> {
    guard !state.updatingTaskIDs.contains(taskID) else {
        return .none
    }

    state.updatingTaskIDs.insert(taskID)

    return .run { send in
        do {
            try await updateStatus(taskID, status, configuration)
            await send(
                .taskStatusUpdateResponse(
                    .success(.init(taskID: taskID, status: status))
                )
            )
        } catch {
            await send(
                .taskStatusUpdateResponse(
                    .failure(.init(taskID: taskID, description: error.localizedDescription))
                )
            )
        }
    }
}
