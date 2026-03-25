import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    @Dependency(\.taskBoardClient) var taskBoardClient

    @ObservableState
    struct State: Equatable {
        var tasks: IdentifiedArrayOf<LooperTask> = []
        var selectedTaskID: LooperTask.ID?
        var isLoadingTasks = false
        var workspace = WorkspaceFeature.State()
    }

    enum Action {
        case onAppear
        case selectTask(LooperTask.ID?)
        case startSelectedTaskButtonTapped
        case taskResponse([LooperTask])
        case workspace(WorkspaceFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.workspace, action: \.workspace) {
            WorkspaceFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoadingTasks = true

                return .merge(
                    .send(.workspace(.onAppear)),
                    .run { send in
                        await send(.taskResponse(taskBoardClient.fetchTasks()))
                    }
                )

            case let .taskResponse(tasks):
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

            case let .selectTask(id):
                state.selectedTaskID = id
                return syncWorkspaceSelection(state: &state)

            case .startSelectedTaskButtonTapped:
                guard let task = selectedTask(state: state) else { return .none }

                if let existingWorkspaceID = workspaceID(for: task, in: state.workspace.workspaces) {
                    state.selectedTaskID = task.id
                    return .merge(
                        .send(.workspace(.selectWorkspace(existingWorkspaceID))),
                        .send(.workspace(.attachSelectedWorkspaceButtonTapped))
                    )
                }

                guard let repoPath = task.repoPath?.path(percentEncoded: false) else {
                    return .none
                }

                updateTaskStatus(id: task.id, status: .developing, state: &state)
                return .send(.workspace(.createWorkspaceFromDefaults(repoPath)))

            case let .workspace(.createWorkspaceResponse(.success(workspace))):
                if let taskID = taskID(matching: workspace, in: state.tasks) {
                    state.selectedTaskID = taskID
                    updateTaskStatus(id: taskID, status: .developing, state: &state)
                }
                return .none

            case .workspace(.bootstrapResponse(.success)):
                if state.selectedTaskID == nil {
                    state.selectedTaskID = taskIDMatchingSelectedWorkspace(state: state) ?? state.tasks.ids.first
                }
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
