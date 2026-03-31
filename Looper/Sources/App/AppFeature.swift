import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    @Dependency(\.date.now) var now
    @Dependency(\.environmentSetupClient) var environmentSetupClient
    @Dependency(\.runStoreClient) var runStoreClient
    @Dependency(\.taskProviderClient) var taskProviderClient
    @Dependency(\.pipelineTerminalClient) var pipelineTerminalClient
    @Dependency(\.uuid) var uuid

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

    struct RunFailure: LocalizedError, Equatable, Sendable {
        var description: String

        var errorDescription: String? {
            description
        }
    }

    @ObservableState
    struct State: Equatable {
        var tasks: IdentifiedArrayOf<LooperTask> = []
        var runs: IdentifiedArrayOf<Run> = []
        var selectedTaskID: LooperTask.ID?
        var pendingRunTaskID: LooperTask.ID?
        var isLoadingTasks = false
        var updatingTaskIDs: Set<LooperTask.ID> = []
        var taskProviderErrorMessage: String?
        var isSettingsPresented = false
        var isInspectingTaskProvider = false
        var taskProviderInspection: TaskProviderInspection?
        var isCheckingEnvironment = false
        var environmentReport: EnvironmentSetupReport?
        var isSavingSettings = false
        var isLocalTaskComposerPresented = false
        var isCreatingLocalTask = false
        var pipelinePendingDeletionID: Pipeline.ID?
        var pipeline = PipelineFeature.State()
    }

    enum Action {
        case cancelDeletePipeline
        case confirmDeletePipeline
        case deletePipelineMenuTapped(Pipeline.ID)
        case dismissTaskProviderError
        case dismissSettingsButtonTapped
        case dismissLocalTaskComposerButtonTapped
        case environmentCheckResponse(EnvironmentSetupReport)
        case createLocalTaskButtonTapped(LocalTaskDraft)
        case localTaskCreateResponse(Result<LooperTask, TaskProviderFailure>)
        case markSelectedTaskDoneButtonTapped
        case newPipelineButtonTapped
        case markSelectedTaskFailedButtonTapped
        case onAppear
        case openLocalTaskComposerButtonTapped
        case openSettingsButtonTapped
        case loadRuns
        case saveSettingsButtonTapped
        case selectTaskProvider(TaskProviderKind)
        case refreshTasksButtonTapped
        case runPersistenceFailed(RunFailure)
        case runResponse(Result<[Run], RunFailure>)
        case runEnvironmentCheckButtonTapped
        case selectTask(LooperTask.ID?)
        case startSelectedTaskButtonTapped
        case inspectTaskProviderButtonTapped
        case taskProviderInspectionResponse(Result<TaskProviderInspection, TaskProviderFailure>)
        case taskResponse(Result<[LooperTask], TaskProviderFailure>)
        case taskStatusUpdateResponse(Result<TaskStatusUpdate, TaskStatusFailure>)
        case terminalEventReceived(PipelineTerminalEvent)
        case pipeline(PipelineFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.pipeline, action: \.pipeline) {
            PipelineFeature()
        }

        Reduce { state, action in
            switch action {
            case let .deletePipelineMenuTapped(id):
                state.pipelinePendingDeletionID = id
                return .none

            case .confirmDeletePipeline:
                guard let id = state.pipelinePendingDeletionID else { return .none }
                state.pipelinePendingDeletionID = nil
                return .send(.pipeline(.removePipelineButtonTapped(id)))

            case .cancelDeletePipeline:
                state.pipelinePendingDeletionID = nil
                return .none

            case .onAppear:
                return .merge(
                    .send(.pipeline(.onAppear)),
                    .run { send in
                        let events = await pipelineTerminalClient.events()
                        for await event in events {
                            await send(.terminalEventReceived(event))
                        }
                    }
                )

            case .openSettingsButtonTapped:
                state.isSettingsPresented = true
                return .none

            case .newPipelineButtonTapped:
                state.pendingRunTaskID = nil
                return .send(.pipeline(.openProjectButtonTapped))

            case let .selectTaskProvider(kind):
                state.pipeline.preferences.taskProviderConfiguration.kind = kind
                state.taskProviderInspection = nil
                state.taskProviderErrorMessage = nil
                return .none

            case .openLocalTaskComposerButtonTapped:
                guard state.pipeline.preferences.taskProviderConfiguration.kind == .local else {
                    return .none
                }
                guard state.pipeline.selectedPipelineID != nil else {
                    state.taskProviderErrorMessage = String(localized: "error.createPipelineFirst", bundle: .localized)
                    return .none
                }
                state.isLocalTaskComposerPresented = true
                return .none

            case .dismissLocalTaskComposerButtonTapped:
                state.isLocalTaskComposerPresented = false
                state.isCreatingLocalTask = false
                return .none

            case .dismissSettingsButtonTapped:
                state.isSettingsPresented = false
                state.isInspectingTaskProvider = false
                state.isCheckingEnvironment = false
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

            case .inspectTaskProviderButtonTapped:
                let configuration = state.pipeline.preferences.taskProviderConfiguration
                if configuration.kind == .feishu,
                   !configuration.feishu.minimumConnectionFieldsArePresent
                {
                    state.taskProviderErrorMessage = String(localized: "error.feishuFieldsRequired", bundle: .localized)
                    return .none
                }

                state.isInspectingTaskProvider = true
                state.taskProviderInspection = nil
                state.taskProviderErrorMessage = nil

                return .run { send in
                    do {
                        let inspection = try await taskProviderClient.inspectConfiguration(configuration)
                        await send(.taskProviderInspectionResponse(.success(inspection)))
                    } catch {
                        await send(
                            .taskProviderInspectionResponse(
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case let .taskProviderInspectionResponse(.success(inspection)):
                state.isInspectingTaskProvider = false
                state.taskProviderInspection = inspection
                if state.pipeline.preferences.taskProviderConfiguration.kind == .feishu {
                    autofillFeishuMappings(
                        inspection: inspection,
                        configuration: &state.pipeline.preferences.feishuProviderConfiguration
                    )
                }
                return .none

            case let .taskProviderInspectionResponse(.failure(error)):
                state.isInspectingTaskProvider = false
                state.taskProviderErrorMessage = error.description
                return .none

            case .refreshTasksButtonTapped:
                let configuration = state.pipeline.preferences.taskProviderConfiguration
                guard configuration.canFetchTasks else {
                    state.taskProviderErrorMessage = configuration.kind == .feishu
                        ? String(localized: "error.configureFeishu", bundle: .localized)
                        : String(localized: "error.localProviderNotReady", bundle: .localized)
                    return .none
                }

                state.isLoadingTasks = true
                state.taskProviderErrorMessage = nil

                return .run { send in
                    do {
                        let tasks = try await taskProviderClient.fetchTasks(configuration)
                        await send(.taskResponse(.success(tasks)))
                    } catch {
                        await send(
                            .taskResponse(
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case .loadRuns:
                return .run { send in
                    do {
                        let runs = try await runStoreClient.fetchRuns()
                        await send(.runResponse(.success(runs)))
                    } catch {
                        await send(
                            .runResponse(
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case let .runResponse(.success(runs)):
                state.runs = IdentifiedArray(uniqueElements: runs)
                return .none

            case let .runResponse(.failure(error)),
                let .runPersistenceFailed(error):
                state.taskProviderErrorMessage = error.description
                return .none

            case let .taskResponse(.success(tasks)):
                state.isLoadingTasks = false
                state.tasks = IdentifiedArray(uniqueElements: tasks)

                if let selectedTaskID = state.selectedTaskID,
                   state.tasks[id: selectedTaskID] != nil
                {
                    let selectionEffect = syncPipelineSelection(state: &state)
                    let attachEffect = attachTerminalsForDevelopingTasks(
                        tasks: tasks,
                        pipelines: state.pipeline.pipelines,
                        attachSession: pipelineTerminalClient.attachSessionIfNeeded
                    )
                    return .merge(selectionEffect, attachEffect)
                }

                if let matchingTaskID = taskIDMatchingSelectedPipeline(state: state) {
                    state.selectedTaskID = matchingTaskID
                } else if state.pipeline.selectedPipelineID != nil {
                    state.selectedTaskID = nil
                } else {
                    state.selectedTaskID = state.tasks.ids.first
                }

                let selectionEffect = syncPipelineSelection(state: &state)
                let attachEffect = attachTerminalsForDevelopingTasks(
                    tasks: tasks,
                    pipelines: state.pipeline.pipelines,
                    attachSession: pipelineTerminalClient.attachSessionIfNeeded
                )
                return .merge(selectionEffect, attachEffect)

            case let .taskResponse(.failure(error)):
                state.isLoadingTasks = false
                state.taskProviderErrorMessage = error.description
                return .none

            case let .selectTask(id):
                state.selectedTaskID = id
                return syncPipelineSelection(state: &state)

            case let .createLocalTaskButtonTapped(draft):
                guard state.pipeline.preferences.taskProviderConfiguration.kind == .local else {
                    state.taskProviderErrorMessage = String(localized: "error.localTaskOnlyLocal", bundle: .localized)
                    return .none
                }

                state.isCreatingLocalTask = true
                let configuration = state.pipeline.preferences.taskProviderConfiguration
                return .run { send in
                    do {
                        let task = try await taskProviderClient.createTask(draft, configuration)
                        await send(.localTaskCreateResponse(.success(task)))
                    } catch {
                        await send(
                            .localTaskCreateResponse(
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case let .localTaskCreateResponse(.success(task)):
                state.isCreatingLocalTask = false
                state.isLocalTaskComposerPresented = false
                state.tasks.insert(task, at: 0)
                state.selectedTaskID = task.id
                return .none

            case let .localTaskCreateResponse(.failure(error)):
                state.isCreatingLocalTask = false
                state.taskProviderErrorMessage = error.description
                return .none

            case .startSelectedTaskButtonTapped:
                guard let task = selectedTask(state: state) else { return .none }

                if let existingPipelineID = pipelineID(for: task, in: state.pipeline.pipelines) {
                    if let activeRun = activeRun(
                        for: existingPipelineID,
                        in: state.runs
                    ) {
                        guard activeRun.taskID == task.id else {
                            state.taskProviderErrorMessage = String(localized: "error.finishCurrentRun", bundle: .localized)
                            return .none
                        }
                    }

                    state.selectedTaskID = task.id
                    var effects: [Effect<Action>] = [
                        .send(.pipeline(.selectPipeline(existingPipelineID))),
                        .send(.pipeline(.attachSelectedPipelineButtonTapped)),
                    ]

                    if activeRun(for: existingPipelineID, in: state.runs) == nil {
                        effects.insert(
                            beginRun(
                                pipelineID: existingPipelineID,
                                taskID: task.id,
                                trigger: .resumeTask,
                                state: &state,
                                runID: uuid(),
                                startedAt: now,
                                saveRun: runStoreClient.saveRun
                            ),
                            at: 0
                        )
                    }

                    if state.pipeline.preferences.taskProviderConfiguration.canFetchTasks {
                        effects.append(
                            writeTaskStatus(
                                taskID: task.id,
                                status: .developing,
                                configuration: state.pipeline.preferences.taskProviderConfiguration,
                                state: &state,
                                updateStatus: taskProviderClient.updateTaskStatus
                            )
                        )
                    }

                    return .merge(effects)
                }

                guard let repoPath = task.repoPath?.path(percentEncoded: false) else {
                    return .none
                }

                state.pendingRunTaskID = task.id
                return .send(.pipeline(.createPipelineFromDefaults(repoPath)))

            case .markSelectedTaskDoneButtonTapped:
                guard let task = selectedTask(state: state) else { return .none }
                guard state.pipeline.preferences.taskProviderConfiguration.canFetchTasks else {
                    state.taskProviderErrorMessage = String(localized: "error.configureProvider", bundle: .localized)
                    return .none
                }

                return .merge(
                    finishActiveRun(
                        for: task,
                        status: .succeeded,
                        exitCode: nil,
                        state: &state,
                        finishedAt: now,
                        saveRun: runStoreClient.saveRun
                    ),
                    writeTaskStatus(
                        taskID: task.id,
                        status: .done,
                        configuration: state.pipeline.preferences.taskProviderConfiguration,
                        state: &state,
                        updateStatus: taskProviderClient.updateTaskStatus
                    )
                )

            case .markSelectedTaskFailedButtonTapped:
                guard let task = selectedTask(state: state) else { return .none }
                guard state.pipeline.preferences.taskProviderConfiguration.canFetchTasks else {
                    state.taskProviderErrorMessage = String(localized: "error.configureProvider", bundle: .localized)
                    return .none
                }

                return .merge(
                    finishActiveRun(
                        for: task,
                        status: .failed,
                        exitCode: nil,
                        state: &state,
                        finishedAt: now,
                        saveRun: runStoreClient.saveRun
                    ),
                    writeTaskStatus(
                        taskID: task.id,
                        status: .failed,
                        configuration: state.pipeline.preferences.taskProviderConfiguration,
                        state: &state,
                        updateStatus: taskProviderClient.updateTaskStatus
                    )
                )

            case let .pipeline(.createPipelineResponse(.success(pipeline))):
                defer { state.pendingRunTaskID = nil }

                let pendingRunTaskID = state.pendingRunTaskID
                let matchingTaskID = taskID(matching: pipeline, in: state.tasks)

                if let pendingRunTaskID {
                    state.selectedTaskID = pendingRunTaskID
                    let taskID = pendingRunTaskID
                    state.selectedTaskID = taskID
                    let runEffect = beginRun(
                        pipelineID: pipeline.id,
                        taskID: taskID,
                        trigger: .startTask,
                        state: &state,
                        runID: uuid(),
                        startedAt: now,
                        saveRun: runStoreClient.saveRun
                    )

                    if state.pipeline.preferences.taskProviderConfiguration.canFetchTasks {
                        return .merge(
                            runEffect,
                            writeTaskStatus(
                                taskID: taskID,
                                status: .developing,
                                configuration: state.pipeline.preferences.taskProviderConfiguration,
                                state: &state,
                                updateStatus: taskProviderClient.updateTaskStatus
                            )
                        )
                    }

                    return runEffect
                }

                state.selectedTaskID = matchingTaskID
                return .none

            case let .pipeline(.bootstrapResponse(.success(payload))):
                if state.selectedTaskID == nil {
                    state.selectedTaskID = taskIDMatchingSelectedPipeline(state: state)
                }

                let loadRunsEffect: Effect<Action> = .send(.loadRuns)

                if !payload.preferences.hasCompletedOnboarding {
                    state.isSettingsPresented = true
                    return loadRunsEffect
                }

                guard payload.preferences.taskProviderConfiguration.canFetchTasks else {
                    return loadRunsEffect
                }

                return .merge(
                    loadRunsEffect,
                    .send(.refreshTasksButtonTapped)
                )

            case .pipeline(.savePreferencesFinished):
                if state.isSavingSettings {
                    state.isSavingSettings = false
                    state.isSettingsPresented = false
                }

                guard state.pipeline.preferences.taskProviderConfiguration.canFetchTasks else {
                    return .none
                }

                return .send(.refreshTasksButtonTapped)

            case .saveSettingsButtonTapped:
                state.pipeline.preferences.hasCompletedOnboarding = true
                state.isSavingSettings = true
                return .send(.pipeline(.savePreferencesButtonTapped))

            case let .taskStatusUpdateResponse(.success(update)):
                state.updatingTaskIDs.remove(update.taskID)
                updateTaskStatus(id: update.taskID, status: update.status, state: &state)
                return .none

            case let .taskStatusUpdateResponse(.failure(error)):
                state.updatingTaskIDs.remove(error.taskID)
                state.taskProviderErrorMessage = error.description
                return .none

            case let .terminalEventReceived(event):
                guard let suggestedStatus = event.suggestedTaskStatus else { return .none }
                guard let pipeline = state.pipeline.pipelines[id: event.pipelineID] else { return .none }
                guard let taskID = taskID(matching: pipeline, in: state.tasks) else { return .none }
                guard let task = state.tasks[id: taskID] else { return .none }
                guard task.status == .developing else { return .none }

                let runStatus: Run.Status = suggestedStatus == .done ? .succeeded : .failed
                let runEffect = finishActiveRun(
                    pipelineID: event.pipelineID,
                    taskID: taskID,
                    status: runStatus,
                    exitCode: event.exitCode,
                    state: &state,
                    finishedAt: now,
                    saveRun: runStoreClient.saveRun
                )

                if state.pipeline.preferences.taskProviderConfiguration.canFetchTasks {
                    return .merge(
                        runEffect,
                        writeTaskStatus(
                            taskID: taskID,
                            status: suggestedStatus,
                            configuration: state.pipeline.preferences.taskProviderConfiguration,
                            state: &state,
                            updateStatus: taskProviderClient.updateTaskStatus
                        )
                    )
                }

                updateTaskStatus(id: taskID, status: suggestedStatus, state: &state)
                return runEffect

            case .dismissTaskProviderError:
                state.taskProviderErrorMessage = nil
                return .none

            case let .pipeline(.selectPipeline(id)):
                guard let id else {
                    state.selectedTaskID = nil
                    return .none
                }

                if let selectedTask = selectedTask(state: state),
                   pipelineID(for: selectedTask, in: state.pipeline.pipelines) == id
                {
                    return .none
                }

                state.selectedTaskID = taskID(matchingPipelineID: id, state: state)
                return .none

            case .pipeline(.removePipelineResponse(_, .success)):
                state.selectedTaskID = taskIDMatchingSelectedPipeline(state: state)
                return .none

            case .pipeline(.createPipelineResponse(.failure)):
                state.pendingRunTaskID = nil
                return .none

            case .pipeline:
                return .none

            }
        }
    }
}

private func selectedTask(state: AppFeature.State) -> LooperTask? {
    guard let selectedTaskID = state.selectedTaskID else { return nil }
    return state.tasks[id: selectedTaskID]
}

private func selectedPipeline(state: AppFeature.State) -> Pipeline? {
    if let selectedPipelineID = state.pipeline.selectedPipelineID,
       let pipeline = state.pipeline.pipelines[id: selectedPipelineID]
    {
        return pipeline
    }

    guard let task = selectedTask(state: state),
          let pipelineID = pipelineID(for: task, in: state.pipeline.pipelines)
    else {
        return nil
    }

    return state.pipeline.pipelines[id: pipelineID]
}

private func syncPipelineSelection(state: inout AppFeature.State) -> Effect<AppFeature.Action> {
    guard let task = selectedTask(state: state) else {
        return .none
    }

    guard let pipelineID = pipelineID(for: task, in: state.pipeline.pipelines) else {
        guard state.pipeline.selectedPipelineID != nil else {
            return .none
        }
        state.pipeline.selectedPipelineID = nil
        return .send(.pipeline(.selectPipeline(nil)))
    }

    state.pipeline.selectedPipelineID = pipelineID
    return .send(.pipeline(.selectPipeline(pipelineID)))
}

private func pipelineID(
    for task: LooperTask,
    in pipelines: IdentifiedArrayOf<Pipeline>
) -> UUID? {
    guard let taskPath = task.repoPath?.standardizedFileURL.path(percentEncoded: false) else {
        return nil
    }

    return pipelines.first {
        $0.executionURL.standardizedFileURL.path(percentEncoded: false) == taskPath
    }?.id
}

private func taskID(
    matching pipeline: Pipeline,
    in tasks: IdentifiedArrayOf<LooperTask>
) -> LooperTask.ID? {
    let pipelinePath = pipeline.executionURL.standardizedFileURL.path(percentEncoded: false)

    return tasks.first {
        $0.repoPath?.standardizedFileURL.path(percentEncoded: false) == pipelinePath
    }?.id
}

private func taskIDMatchingSelectedPipeline(state: AppFeature.State) -> LooperTask.ID? {
    guard let pipelineID = state.pipeline.selectedPipelineID,
          let pipeline = state.pipeline.pipelines[id: pipelineID]
    else {
        return nil
    }

    return taskID(matching: pipeline, in: state.tasks)
}

private func taskID(
    matchingPipelineID pipelineID: UUID,
    state: AppFeature.State
) -> LooperTask.ID? {
    guard let pipeline = state.pipeline.pipelines[id: pipelineID] else {
        return nil
    }

    return taskID(matching: pipeline, in: state.tasks)
}

private func activeRun(
    for pipelineID: UUID,
    in runs: IdentifiedArrayOf<Run>
) -> Run? {
    runs.first { $0.pipelineID == pipelineID && $0.isActive }
}

private func activeRunID(
    pipelineID: UUID,
    taskID: LooperTask.ID,
    in runs: IdentifiedArrayOf<Run>
) -> UUID? {
    runs.first {
        $0.pipelineID == pipelineID && $0.taskID == taskID && $0.isActive
    }?.id
}

private func updateTaskStatus(
    id: LooperTask.ID,
    status: LooperTask.Status,
    state: inout AppFeature.State
) {
    guard state.tasks[id: id] != nil else { return }
    state.tasks[id: id]?.status = status
}

private func beginRun(
    pipelineID: UUID,
    taskID: LooperTask.ID,
    trigger: Run.Trigger,
    state: inout AppFeature.State,
    runID: UUID,
    startedAt: Date,
    saveRun: @escaping @Sendable (Run) async throws -> Void
) -> Effect<AppFeature.Action> {
    let run = Run(
        id: runID,
        pipelineID: pipelineID,
        taskID: taskID,
        status: .running,
        trigger: trigger,
        startedAt: startedAt,
        finishedAt: nil,
        exitCode: nil,
        logPath: logPath(for: runID)
    )

    state.runs.insert(run, at: 0)

    return .run { send in
        do {
            try await saveRun(run)
        } catch {
            await send(
                .runPersistenceFailed(
                    .init(description: error.localizedDescription)
                )
            )
        }
    }
}

private func finishActiveRun(
    for task: LooperTask,
    status: Run.Status,
    exitCode: Int32?,
    state: inout AppFeature.State,
    finishedAt: Date,
    saveRun: @escaping @Sendable (Run) async throws -> Void
) -> Effect<AppFeature.Action> {
    guard let pipeline = selectedPipeline(state: state) else { return .none }
    return finishActiveRun(
        pipelineID: pipeline.id,
        taskID: task.id,
        status: status,
        exitCode: exitCode,
        state: &state,
        finishedAt: finishedAt,
        saveRun: saveRun
    )
}

private func finishActiveRun(
    pipelineID: UUID,
    taskID: LooperTask.ID,
    status: Run.Status,
    exitCode: Int32?,
    state: inout AppFeature.State,
    finishedAt: Date,
    saveRun: @escaping @Sendable (Run) async throws -> Void
) -> Effect<AppFeature.Action> {
    guard let runID = activeRunID(
        pipelineID: pipelineID,
        taskID: taskID,
        in: state.runs
    ),
    let run = state.runs[id: runID]
    else {
        return .none
    }

    let finishedRun = run.finished(
        status: status,
        exitCode: exitCode,
        finishedAt: finishedAt
    )
    state.runs[id: runID] = finishedRun

    return .run { send in
        do {
            try await saveRun(finishedRun)
        } catch {
            await send(
                .runPersistenceFailed(
                    .init(description: error.localizedDescription)
                )
            )
        }
    }
}

private func logPath(for runID: UUID) -> String {
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("looper-runs", isDirectory: true)
        .appendingPathComponent("\(runID.uuidString).log", isDirectory: false)
        .path(percentEncoded: false)
}

private func writeTaskStatus(
    taskID: LooperTask.ID,
    status: LooperTask.Status,
    configuration: TaskProviderConfiguration,
    state: inout AppFeature.State,
    updateStatus: @escaping @Sendable (LooperTask.ID, LooperTask.Status, TaskProviderConfiguration) async throws -> Void
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

private func autofillFeishuMappings(
    inspection: TaskProviderInspection,
    configuration: inout FeishuTaskProviderConfiguration
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

private func attachTerminalsForDevelopingTasks(
    tasks: [LooperTask],
    pipelines: IdentifiedArrayOf<Pipeline>,
    attachSession: @escaping @Sendable (UUID) async -> Void
) -> Effect<AppFeature.Action> {
    let developingTasks = tasks.filter { $0.status == .developing }
    let developingPipelineIDs: Set<UUID> = Set(
        developingTasks.compactMap { task in
            pipelineID(for: task, in: pipelines)
        }
    )

    guard !developingPipelineIDs.isEmpty else {
        print("[AppFeature] no developing tasks found (total tasks=\(tasks.count))")
        return .none
    }

    print("[AppFeature] attaching terminals for \(developingPipelineIDs.count) pipelines with developing tasks")

    return .run { _ in
        for id in developingPipelineIDs {
            print("[AppFeature] calling attachSessionIfNeeded for pipeline \(id.uuidString.prefix(8))")
            await attachSession(id)
        }
    }
}
