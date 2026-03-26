import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    @Dependency(\.environmentSetupClient) var environmentSetupClient
    @Dependency(\.taskBoardClient) var taskBoardClient
    @Dependency(\.terminalWorkspaceClient) var terminalWorkspaceClient

    enum SetupStep: Int, CaseIterable, Equatable, Sendable {
        case welcome
        case taskBoard
        case environment
        case finish

        var title: String {
            switch self {
            case .welcome:
                "Welcome"
            case .taskBoard:
                "Connect Feishu"
            case .environment:
                "Check Environment"
            case .finish:
                "Run First Task"
            }
        }
    }

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
        var isSetupWizardPresented = false
        var setupStep: SetupStep = .welcome
        var isInspectingTaskBoard = false
        var taskBoardInspection: TaskBoardInspection?
        var isCheckingEnvironment = false
        var environmentReport: EnvironmentSetupReport?
        var isFinishingSetup = false
        var workspace = WorkspaceFeature.State()
    }

    enum Action {
        case advanceSetupStepButtonTapped
        case backSetupStepButtonTapped
        case dismissTaskBoardError
        case dismissSetupWizardButtonTapped
        case environmentCheckResponse(EnvironmentSetupReport)
        case finishSetupButtonTapped
        case markSelectedTaskDoneButtonTapped
        case markSelectedTaskFailedButtonTapped
        case onAppear
        case openSetupButtonTapped
        case refreshTasksButtonTapped
        case runEnvironmentCheckButtonTapped
        case selectTask(LooperTask.ID?)
        case startSelectedTaskButtonTapped
        case testTaskBoardConnectionButtonTapped
        case taskBoardInspectionResponse(Result<TaskBoardInspection, TaskBoardFailure>)
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

            case .openSetupButtonTapped:
                state.isSetupWizardPresented = true
                state.setupStep = state.workspace.preferences.hasCompletedOnboarding ? .taskBoard : .welcome
                return .none

            case .dismissSetupWizardButtonTapped:
                state.isSetupWizardPresented = false
                state.isInspectingTaskBoard = false
                state.isCheckingEnvironment = false
                return .none

            case .advanceSetupStepButtonTapped:
                guard let nextStep = nextSetupStep(after: state.setupStep) else { return .none }
                state.setupStep = nextStep
                return .none

            case .backSetupStepButtonTapped:
                guard let previousStep = previousSetupStep(before: state.setupStep) else { return .none }
                state.setupStep = previousStep
                return .none

            case .runEnvironmentCheckButtonTapped:
                state.isCheckingEnvironment = true
                return .run { send in
                    let report = await environmentSetupClient.inspect()
                    await send(.environmentCheckResponse(report))
                }

            case let .environmentCheckResponse(report):
                state.environmentReport = report
                state.isCheckingEnvironment = false
                return .none

            case .testTaskBoardConnectionButtonTapped:
                let configuration = state.workspace.preferences.taskBoardConfiguration
                guard configuration.minimumConnectionFieldsArePresent else {
                    state.taskBoardErrorMessage = "App ID, app secret, app token, and table ID are required."
                    return .none
                }

                state.isInspectingTaskBoard = true
                state.taskBoardInspection = nil
                state.taskBoardErrorMessage = nil

                return .run { send in
                    do {
                        let inspection = try await taskBoardClient.inspectConfiguration(configuration)
                        await send(.taskBoardInspectionResponse(.success(inspection)))
                    } catch {
                        await send(
                            .taskBoardInspectionResponse(
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case let .taskBoardInspectionResponse(.success(inspection)):
                state.isInspectingTaskBoard = false
                state.taskBoardInspection = inspection
                autofillTaskBoardMappings(
                    inspection: inspection,
                    configuration: &state.workspace.preferences.taskBoardConfiguration
                )
                return .none

            case let .taskBoardInspectionResponse(.failure(error)):
                state.isInspectingTaskBoard = false
                state.taskBoardErrorMessage = error.description
                return .none

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

                if !payload.preferences.hasCompletedOnboarding {
                    state.isSetupWizardPresented = true
                    state.setupStep = .welcome
                    return .none
                }

                guard payload.preferences.taskBoardConfiguration.isConfigured else {
                    return .none
                }

                return .send(.refreshTasksButtonTapped)

            case .workspace(.savePreferencesFinished):
                if state.isFinishingSetup {
                    state.isFinishingSetup = false
                    state.isSetupWizardPresented = false
                    state.setupStep = .finish
                }

                guard state.workspace.preferences.taskBoardConfiguration.isConfigured else {
                    return .none
                }

                return .send(.refreshTasksButtonTapped)

            case .finishSetupButtonTapped:
                guard state.workspace.preferences.taskBoardConfiguration.isConfigured else {
                    state.taskBoardErrorMessage = "Complete the Feishu setup before finishing."
                    return .none
                }
                guard state.environmentReport?.isReady == true else {
                    state.taskBoardErrorMessage = "Install Git and Claude CLI before finishing setup."
                    return .none
                }

                state.workspace.preferences.hasCompletedOnboarding = true
                state.isFinishingSetup = true
                return .send(.workspace(.savePreferencesButtonTapped))

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

private func nextSetupStep(after step: AppFeature.SetupStep) -> AppFeature.SetupStep? {
    AppFeature.SetupStep(rawValue: step.rawValue + 1)
}

private func previousSetupStep(before step: AppFeature.SetupStep) -> AppFeature.SetupStep? {
    AppFeature.SetupStep(rawValue: step.rawValue - 1)
}

private func autofillTaskBoardMappings(
    inspection: TaskBoardInspection,
    configuration: inout TaskBoardConfiguration
) {
    if let field = bestFieldMatch(
        in: inspection.discoveredFieldNames,
        candidates: ["title", "任务标题", "name"]
    ) {
        configuration.titleFieldName = field
    }

    if let field = bestFieldMatch(
        in: inspection.discoveredFieldNames,
        candidates: ["summary", "description", "需求描述", "内容"]
    ) {
        configuration.summaryFieldName = field
    }

    if let field = bestFieldMatch(
        in: inspection.discoveredFieldNames,
        candidates: ["status", "状态", "state"]
    ) {
        configuration.statusFieldName = field
    }

    if let field = bestFieldMatch(
        in: inspection.discoveredFieldNames,
        candidates: ["repository", "repo", "project", "项目", "仓库", "directory"]
    ) {
        configuration.repoPathFieldName = field
    }
}

private func bestFieldMatch(
    in fields: [String],
    candidates: [String]
) -> String? {
    for candidate in candidates {
        if let match = fields.first(where: { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }) {
            return match
        }
    }

    for candidate in candidates {
        if let match = fields.first(where: {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
        }) {
            return match
        }
    }

    return nil
}
