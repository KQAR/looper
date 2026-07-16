import ComposableArchitecture
import Foundation

/// Top-level surfaces per INTERACTION.md: Inbox is the default landing,
/// Manage is the legacy sidebar + list + detail layout. (Live Wall comes with M3.)
enum AppSurface: String, Equatable, Sendable {
    case inbox
    case manage
}

/// A run's captured patch, loaded for the diff viewer sheet.
struct PresentedDiff: Equatable, Sendable {
    var taskTitle: String
    var patch: String
}

@Reducer
struct AppFeature {
    @Dependency(\.date.now) var now
    @Dependency(\.environmentSetupClient) var environmentSetupClient
    @Dependency(\.pipelineManagerClient) var pipelineManagerClient
    @Dependency(\.runStoreClient) var runStoreClient
    @Dependency(\.taskProviderClient) var taskProviderClient
    @Dependency(\.pipelineTerminalClient) var pipelineTerminalClient
    @Dependency(\.gitWorktreeClient) var gitWorktreeClient
    @Dependency(\.agentProcessClient) var agentProcessClient
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
        var recoveredInterruptedTaskIDs: Set<LooperTask.ID> = []
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
        var activeSurface: AppSurface = .inbox
        var pendingSteeringNotes: [LooperTask.ID: [SteeringNote]] = [:]
        /// Orphan detection (maintenance card) stays silent until both
        /// pipelines and tasks have actually loaded — an empty list before
        /// bootstrap must not read as "everything is orphaned".
        var hasLoadedPipelines = false
        var hasLoadedTasks = false
        var presentedDiff: PresentedDiff?
        var pipeline = PipelineFeature.State()

        init(
            tasks: IdentifiedArrayOf<LooperTask> = [],
            runs: IdentifiedArrayOf<Run> = [],
            selectedTaskID: LooperTask.ID? = nil,
            pendingRunTaskID: LooperTask.ID? = nil,
            recoveredInterruptedTaskIDs: Set<LooperTask.ID> = [],
            isLoadingTasks: Bool = false,
            updatingTaskIDs: Set<LooperTask.ID> = [],
            taskProviderErrorMessage: String? = nil,
            isSettingsPresented: Bool = false,
            isInspectingTaskProvider: Bool = false,
            taskProviderInspection: TaskProviderInspection? = nil,
            isCheckingEnvironment: Bool = false,
            environmentReport: EnvironmentSetupReport? = nil,
            isSavingSettings: Bool = false,
            isLocalTaskComposerPresented: Bool = false,
            isCreatingLocalTask: Bool = false,
            pipelinePendingDeletionID: Pipeline.ID? = nil,
            activeSurface: AppSurface = .inbox,
            pendingSteeringNotes: [LooperTask.ID: [SteeringNote]] = [:],
            hasLoadedPipelines: Bool = false,
            hasLoadedTasks: Bool = false,
            pipeline: PipelineFeature.State = PipelineFeature.State()
        ) {
            self.tasks = tasks
            self.runs = runs
            self.selectedTaskID = selectedTaskID
            self.pendingRunTaskID = pendingRunTaskID
            self.recoveredInterruptedTaskIDs = recoveredInterruptedTaskIDs
            self.isLoadingTasks = isLoadingTasks
            self.updatingTaskIDs = updatingTaskIDs
            self.taskProviderErrorMessage = taskProviderErrorMessage
            self.isSettingsPresented = isSettingsPresented
            self.isInspectingTaskProvider = isInspectingTaskProvider
            self.taskProviderInspection = taskProviderInspection
            self.isCheckingEnvironment = isCheckingEnvironment
            self.environmentReport = environmentReport
            self.isSavingSettings = isSavingSettings
            self.isLocalTaskComposerPresented = isLocalTaskComposerPresented
            self.isCreatingLocalTask = isCreatingLocalTask
            self.pipelinePendingDeletionID = pipelinePendingDeletionID
            self.activeSurface = activeSurface
            self.pendingSteeringNotes = pendingSteeringNotes
            self.hasLoadedPipelines = hasLoadedPipelines
            self.hasLoadedTasks = hasLoadedTasks
            self.pipeline = pipeline
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case agentEventReceived(runID: UUID, AgentEvent)
        case cancelRunButtonTapped(UUID)
        case cancelDeletePipeline
        case confirmDeletePipeline
        case deletePipelineMenuTapped(Pipeline.ID)
        case dismissTaskProviderError
        case dismissSettingsButtonTapped
        case dismissLocalTaskComposerButtonTapped
        case environmentCheckResponse(EnvironmentSetupReport)
        case createLocalTaskButtonTapped(LocalTaskDraft)
        case localTaskCreateResponse(Result<LooperTask, TaskProviderFailure>)
        case markSelectedTaskInReviewButtonTapped
        case markSelectedTaskDoneButtonTapped
        case newPipelineButtonTapped
        case returnSelectedTaskToTodoButtonTapped
        case onAppear
        case openLocalTaskComposerButtonTapped
        case openSettingsButtonTapped
        case loadRuns
        case saveSettingsButtonTapped
        case selectTaskProvider(TaskProviderKind)
        case refreshTasksButtonTapped
        case runDiffCaptured(runID: UUID, diffPath: String)
        case runPersistenceFailed(RunFailure)
        case runResponse(Result<[Run], RunFailure>)
        case runEnvironmentCheckButtonTapped
        case selectTask(LooperTask.ID?)
        case startSelectedTaskButtonTapped
        case inspectTaskProviderButtonTapped
        case taskProviderInspectionResponse(Result<TaskProviderInspection, TaskProviderFailure>)
        case taskResponse(Result<[LooperTask], TaskProviderFailure>)
        case taskStatusUpdateResponse(Result<TaskStatusUpdate, TaskStatusFailure>)
        case taskWorktreesCleaned(LooperTask.ID)
        case terminalEventReceived(PipelineTerminalEvent)
        case inboxApproveTapped(LooperTask.ID)
        case inboxCleanupCompleted(clearedWorktreeRunIDs: [UUID], deletedRunIDs: [UUID])
        case inboxCleanupTapped
        case inboxViewDiffTapped(LooperTask.ID)
        case inboxDiffLoaded(PresentedDiff?)
        case inboxDiffDismissed
        case inboxSendBackConfirmed(taskID: LooperTask.ID, reason: String)
        case inboxRetryTapped(LooperTask.ID)
        case inboxRevealWorktreeTapped(path: String)
        case pipeline(PipelineFeature.Action)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(state: \.pipeline, action: \.pipeline) {
            PipelineFeature()
        }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case let .agentEventReceived(runID, event):
                return handleAgentEvent(runID: runID, event: event, state: &state)

            case let .cancelRunButtonTapped(runID):
                guard let run = state.runs[id: runID], run.isActive else { return .none }
                return .run { [cancelAgent = agentProcessClient.cancel] _ in
                    await cancelAgent(runID)
                }

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
                        let report = await environmentSetupClient.inspect()
                        await send(.environmentCheckResponse(report))
                    },
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
                let interruptedRuns = runs.filter(\.isActive)
                let recoveredRuns = runs.map { run in
                    guard run.isActive else { return run }
                    return run.finished(
                        status: .failed,
                        exitCode: nil,
                        finishedAt: now
                    )
                }

                state.runs = IdentifiedArray(uniqueElements: recoveredRuns)
                state.recoveredInterruptedTaskIDs.formUnion(interruptedRuns.map(\.taskID))

                let saveRecoveredRunsEffect: Effect<Action> = interruptedRuns.isEmpty
                    ? .none
                    : .run { [saveRun = runStoreClient.saveRun] send in
                        for run in recoveredRuns where run.status == .failed && run.finishedAt != nil {
                            do {
                                try await saveRun(run)
                            } catch {
                                await send(.runPersistenceFailed(.init(description: error.localizedDescription)))
                            }
                        }
                    }

                let reconcileEffect = reconcileRecoveredInterruptedTasks(
                    state: &state,
                    updateStatus: taskProviderClient.updateTaskStatus
                )
                return .merge(saveRecoveredRunsEffect, reconcileEffect)

            case let .runResponse(.failure(error)),
                let .runPersistenceFailed(error):
                state.taskProviderErrorMessage = error.description
                return .none

            case let .taskResponse(.success(tasks)):
                state.isLoadingTasks = false
                state.tasks = IdentifiedArray(uniqueElements: tasks)
                state.hasLoadedTasks = true
                // Steering notes queued for tasks the provider no longer
                // returns can never be delivered — drop them.
                state.pendingSteeringNotes = state.pendingSteeringNotes.filter { taskID, _ in
                    state.tasks[id: taskID] != nil
                }
                let reconcileInterruptedTasksEffect = reconcileRecoveredInterruptedTasks(
                    state: &state,
                    updateStatus: taskProviderClient.updateTaskStatus
                )
                let visibleTasks = Array(state.tasks)

                if let selectedTaskID = state.selectedTaskID,
                   state.tasks[id: selectedTaskID] != nil
                {
                    let selectionEffect = syncPipelineSelection(state: &state)
                    let attachEffect = attachTerminalsForDevelopingTasks(
                        tasks: visibleTasks,
                        pipelines: state.pipeline.pipelines,
                        attachSession: pipelineTerminalClient.attachSessionIfNeeded
                    )
                    return .merge(selectionEffect, attachEffect, reconcileInterruptedTasksEffect)
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
                    tasks: visibleTasks,
                    pipelines: state.pipeline.pipelines,
                    attachSession: pipelineTerminalClient.attachSessionIfNeeded
                )
                return .merge(selectionEffect, attachEffect, reconcileInterruptedTasksEffect)

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
                    guard let pipeline = state.pipeline.pipelines[id: existingPipelineID] else {
                        return .none
                    }

                    // Check if this specific task already has an active run
                    if let existingRun = activeRunForTask(
                        taskID: task.id,
                        pipelineID: existingPipelineID,
                        in: state.runs
                    ) {
                        // Task already running — focus its terminal
                        state.selectedTaskID = task.id
                        return .merge(
                            .send(.pipeline(.selectPipeline(existingPipelineID))),
                            .run { [runID = existingRun.id] _ in
                                await pipelineTerminalClient.focusRunSession(runID)
                            }
                        )
                    }

                    // Check concurrency limit
                    let activeCount = activeRunCount(
                        forPipeline: existingPipelineID,
                        in: state.runs
                    )
                    guard activeCount < pipeline.maxConcurrentRuns else {
                        state.taskProviderErrorMessage = String(localized: "error.maxConcurrentRuns", bundle: .localized)
                        return .none
                    }

                    state.selectedTaskID = task.id
                    let runID = uuid()
                    let startedAt = now

                    // Check for a previous failed run with preserved worktree → resume
                    let previousFailedRun = mostRecentFailedRun(
                        taskID: task.id,
                        pipelineID: existingPipelineID,
                        in: state.runs
                    )
                    let reuseWorktree = previousFailedRun?.worktreePath
                    let trigger: Run.Trigger = reuseWorktree != nil ? .resumeTask : .startTask

                    var effects: [Effect<Action>] = [
                        .send(.pipeline(.selectPipeline(existingPipelineID))),
                    ]

                    // Create worktree (or reuse), terminal, and start run
                    effects.append(
                        startRunWithWorktree(
                            runID: runID,
                            pipeline: pipeline,
                            task: task,
                            trigger: trigger,
                            reuseWorktreePath: reuseWorktree,
                            startedAt: startedAt,
                            state: &state
                        )
                    )

                    if state.pipeline.preferences.taskProviderConfiguration.canFetchTasks {
                        effects.append(
                            writeTaskStatus(
                                taskID: task.id,
                                status: .inProgress,
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

            case .markSelectedTaskInReviewButtonTapped:
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
                        saveRun: runStoreClient.saveRun,
                        pushBranch: gitWorktreeClient.pushBranch,
                        createPullRequest: gitWorktreeClient.createPullRequest,
                        removeWorktree: gitWorktreeClient.removeWorktree
                    ),
                    writeTaskStatus(
                        taskID: task.id,
                        status: .inReview,
                        configuration: state.pipeline.preferences.taskProviderConfiguration,
                        state: &state,
                        updateStatus: taskProviderClient.updateTaskStatus
                    )
                )

            case .markSelectedTaskDoneButtonTapped:
                guard let task = selectedTask(state: state) else { return .none }
                guard state.pipeline.preferences.taskProviderConfiguration.canFetchTasks else {
                    state.taskProviderErrorMessage = String(localized: "error.configureProvider", bundle: .localized)
                    return .none
                }

                // A finished task's queued steering notes are stale.
                state.pendingSteeringNotes[task.id] = nil

                return .merge(
                    writeTaskStatus(
                        taskID: task.id,
                        status: .done,
                        configuration: state.pipeline.preferences.taskProviderConfiguration,
                        state: &state,
                        updateStatus: taskProviderClient.updateTaskStatus
                    ),
                    cleanupAllWorktreesEffect(
                        taskID: task.id,
                        runs: state.runs,
                        pipelines: state.pipeline.pipelines,
                        removeWorktree: gitWorktreeClient.removeWorktree
                    )
                )

            case .returnSelectedTaskToTodoButtonTapped:
                guard let task = selectedTask(state: state) else { return .none }
                guard state.pipeline.preferences.taskProviderConfiguration.canFetchTasks else {
                    state.taskProviderErrorMessage = String(localized: "error.configureProvider", bundle: .localized)
                    return .none
                }

                return writeTaskStatus(
                    taskID: task.id,
                    status: .todo,
                    configuration: state.pipeline.preferences.taskProviderConfiguration,
                    state: &state,
                    updateStatus: taskProviderClient.updateTaskStatus
                )

            case let .inboxApproveTapped(taskID):
                state.selectedTaskID = taskID
                return .send(.markSelectedTaskDoneButtonTapped)

            case let .inboxSendBackConfirmed(taskID, reason):
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedReason.isEmpty else { return .none }
                state.selectedTaskID = taskID
                // The mandatory reason becomes machine-consumable context:
                // it is delivered to the retry run as a steering note.
                state.pendingSteeringNotes[taskID, default: []].append(
                    SteeringNote(
                        id: uuid(),
                        taskID: taskID,
                        text: trimmedReason,
                        origin: .sendBackReason,
                        createdAt: now
                    )
                )
                return .send(.returnSelectedTaskToTodoButtonTapped)

            case let .inboxRetryTapped(taskID):
                // Retry never resurrects a deleted pipeline: it only runs for
                // tasks still routed to an existing one (the auto-create
                // fallback in startSelectedTaskButtonTapped stays reserved
                // for explicit starts on the Manage surface).
                guard let task = state.tasks[id: taskID],
                      pipelineID(for: task, in: state.pipeline.pipelines) != nil
                else { return .none }
                state.selectedTaskID = taskID
                return .send(.startSelectedTaskButtonTapped)

            case let .inboxRevealWorktreeTapped(path):
                return .run { _ in
                    await pipelineManagerClient.revealInFinder(path)
                }

            case let .runDiffCaptured(runID, diffPath):
                guard var run = state.runs[id: runID] else { return .none }
                run.diffPath = diffPath
                state.runs[id: runID] = run
                let updatedRun = run
                return .run { [saveRun = runStoreClient.saveRun] _ in
                    try? await saveRun(updatedRun)
                }

            case let .inboxViewDiffTapped(taskID):
                guard let task = state.tasks[id: taskID],
                      let diffPath = state.runs
                      .filter({ $0.taskID == taskID })
                      .max(by: { $0.startedAt < $1.startedAt })?
                      .diffPath
                else { return .none }
                return .run { [title = task.title] send in
                    let patch = (try? String(contentsOfFile: diffPath, encoding: .utf8)) ?? ""
                    await send(
                        .inboxDiffLoaded(
                            patch.isEmpty ? nil : PresentedDiff(taskTitle: title, patch: patch)
                        )
                    )
                }

            case let .inboxDiffLoaded(diff):
                state.presentedDiff = diff
                return .none

            case .inboxDiffDismissed:
                state.presentedDiff = nil
                return .none

            case .inboxCleanupTapped:
                guard case let .maintenance(staleWorktreeRunIDs, orphanedRunIDs) =
                    state.inboxCards[id: "maintenance"]?.kind
                else { return .none }

                // Stale worktrees still have their repo: remove via git.
                let staleTargets: [(runID: UUID, projectPath: String, worktreePath: String)] =
                    staleWorktreeRunIDs.compactMap { runID in
                        guard let run = state.runs[id: runID],
                              let worktreePath = run.worktreePath,
                              let pipeline = state.pipeline.pipelines[id: run.pipelineID]
                        else { return nil }
                        return (runID, pipeline.projectPath, worktreePath)
                    }
                // Orphaned runs lost their repo: delete the directory, then the record.
                let orphanedTargets: [(runID: UUID, worktreePath: String?)] =
                    orphanedRunIDs.compactMap { runID in
                        guard let run = state.runs[id: runID] else { return nil }
                        return (runID, run.worktreePath)
                    }

                return .run { [
                    removeWorktree = gitWorktreeClient.removeWorktree,
                    removeWorktreeDirectory = gitWorktreeClient.removeWorktreeDirectory,
                    deleteRuns = runStoreClient.deleteRuns
                ] send in
                    for target in staleTargets {
                        try? await removeWorktree(target.projectPath, target.worktreePath)
                    }
                    for target in orphanedTargets {
                        if let worktreePath = target.worktreePath {
                            try? await removeWorktreeDirectory(worktreePath)
                        }
                    }
                    let deletedRunIDs = orphanedTargets.map(\.runID)
                    try? await deleteRuns(deletedRunIDs)
                    await send(
                        .inboxCleanupCompleted(
                            clearedWorktreeRunIDs: staleTargets.map(\.runID),
                            deletedRunIDs: deletedRunIDs
                        )
                    )
                }

            case let .inboxCleanupCompleted(clearedWorktreeRunIDs, deletedRunIDs):
                var clearedRuns: [Run] = []
                for runID in clearedWorktreeRunIDs {
                    guard var run = state.runs[id: runID] else { continue }
                    run.worktreePath = nil
                    state.runs[id: runID] = run
                    clearedRuns.append(run)
                }
                for runID in deletedRunIDs {
                    state.runs.remove(id: runID)
                }
                guard !clearedRuns.isEmpty else { return .none }
                let runsToSave = clearedRuns
                return .run { [saveRun = runStoreClient.saveRun] _ in
                    for run in runsToSave {
                        try? await saveRun(run)
                    }
                }

            case let .pipeline(.createPipelineResponse(.success(pipeline))):
                defer { state.pendingRunTaskID = nil }

                let pendingRunTaskID = state.pendingRunTaskID
                let matchingTaskID = taskID(matching: pipeline, in: state.tasks)

                if let pendingRunTaskID,
                   let task = state.tasks[id: pendingRunTaskID]
                {
                    state.selectedTaskID = pendingRunTaskID
                    let runID = uuid()

                    var effects: [Effect<Action>] = [
                        startRunWithWorktree(
                            runID: runID,
                            pipeline: pipeline,
                            task: task,
                            trigger: .startTask,
                            startedAt: now,
                            state: &state
                        ),
                    ]

                    if state.pipeline.preferences.taskProviderConfiguration.canFetchTasks {
                        effects.append(
                            writeTaskStatus(
                                taskID: pendingRunTaskID,
                                status: .inProgress,
                                configuration: state.pipeline.preferences.taskProviderConfiguration,
                                state: &state,
                                updateStatus: taskProviderClient.updateTaskStatus
                            )
                        )
                    }

                    return .merge(effects)
                }

                state.selectedTaskID = matchingTaskID
                return .none

            case let .pipeline(.bootstrapResponse(.success(payload))):
                state.hasLoadedPipelines = true
                if state.selectedTaskID == nil {
                    state.selectedTaskID = taskIDMatchingSelectedPipeline(state: state)
                }

                let loadRunsEffect: Effect<Action> = .send(.loadRuns)
                let refreshTasksEffect: Effect<Action> = payload.preferences.taskProviderConfiguration.canFetchTasks
                    ? .send(.refreshTasksButtonTapped)
                    : .none

                return .merge(
                    loadRunsEffect,
                    refreshTasksEffect
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

            case let .taskWorktreesCleaned(taskID):
                let cleanedRuns = state.runs
                    .filter { $0.taskID == taskID && $0.worktreePath != nil && !$0.isActive }
                    .map { run -> Run in
                        var cleaned = run
                        cleaned.worktreePath = nil
                        return cleaned
                    }
                guard !cleanedRuns.isEmpty else { return .none }
                for run in cleanedRuns {
                    state.runs[id: run.id] = run
                }
                return .run { [saveRun = runStoreClient.saveRun] _ in
                    for run in cleanedRuns {
                        try? await saveRun(run)
                    }
                }

            case let .taskStatusUpdateResponse(.failure(error)):
                state.updatingTaskIDs.remove(error.taskID)
                state.taskProviderErrorMessage = error.description
                return .none

            case let .terminalEventReceived(event):
                guard let suggestedStatus = event.suggestedTaskStatus else { return .none }

                // Find the run — prefer runID if available, fall back to pipeline matching
                let matchedRun: Run?
                if let runID = event.runID {
                    matchedRun = state.runs[id: runID]
                } else {
                    matchedRun = state.runs.first {
                        $0.pipelineID == event.pipelineID && $0.isActive
                    }
                }

                guard let run = matchedRun else { return .none }
                let taskID = run.taskID
                guard let task = state.tasks[id: taskID] else { return .none }
                guard task.status == .inProgress else { return .none }

                let runStatus: Run.Status = suggestedStatus == .inReview ? .succeeded : .failed
                let finishedRun = run.finished(
                    status: runStatus,
                    exitCode: event.exitCode,
                    finishedAt: now
                )
                state.runs[id: run.id] = finishedRun

                let saveEffect: Effect<Action> = .run { [saveRun = runStoreClient.saveRun] send in
                    do {
                        try await saveRun(finishedRun)
                    } catch {
                        await send(.runPersistenceFailed(.init(description: error.localizedDescription)))
                    }
                }

                let cleanupEffect: Effect<Action> = {
                    guard let pipeline = state.pipeline.pipelines[id: run.pipelineID] else {
                        return .none
                    }
                    return postRunGitEffect(
                        run: finishedRun,
                        task: task,
                        projectPath: pipeline.projectPath,
                        postRunAction: state.pipeline.preferences.postRunGitAction,
                        pushBranch: gitWorktreeClient.pushBranch,
                        createPullRequest: gitWorktreeClient.createPullRequest,
                        removeWorktree: gitWorktreeClient.removeWorktree
                    )
                }()

                // Check if there are other active runs for this task
                let hasOtherActiveRuns = state.runs.contains {
                    $0.taskID == taskID && $0.isActive && $0.id != run.id
                }

                if state.pipeline.preferences.taskProviderConfiguration.canFetchTasks,
                   !hasOtherActiveRuns
                {
                    return .merge(
                        saveEffect,
                        cleanupEffect,
                        writeTaskStatus(
                            taskID: taskID,
                            status: suggestedStatus,
                            configuration: state.pipeline.preferences.taskProviderConfiguration,
                            state: &state,
                            updateStatus: taskProviderClient.updateTaskStatus
                        )
                    )
                }

                if !hasOtherActiveRuns {
                    updateTaskStatus(id: taskID, status: suggestedStatus, state: &state)
                }
                return .merge(saveEffect, cleanupEffect)

            case .dismissTaskProviderError:
                state.taskProviderErrorMessage = nil
                return .none

            case let .pipeline(.removePipelineButtonTapped(id)):
                // The pipeline is still in state here (removal lands with
                // removePipelineResponse). Release everything its runs hold:
                // agent processes, run terminal sessions, worktrees on disk.
                guard let pipeline = state.pipeline.pipelines[id: id] else { return .none }
                let pipelineRuns = state.runs.filter { $0.pipelineID == id }

                var effects: [Effect<Action>] = []

                // Its in-flight tasks would be stuck inProgress once their
                // agents are cancelled — return them to todo now.
                if state.pipeline.preferences.taskProviderConfiguration.canFetchTasks {
                    let inProgressTaskIDs = state.tasks
                        .filter {
                            $0.status == .inProgress
                                && pipelineID(for: $0, in: state.pipeline.pipelines) == id
                        }
                        .map(\.id)
                    for taskID in inProgressTaskIDs {
                        effects.append(
                            writeTaskStatus(
                                taskID: taskID,
                                status: .todo,
                                configuration: state.pipeline.preferences.taskProviderConfiguration,
                                state: &state,
                                updateStatus: taskProviderClient.updateTaskStatus
                            )
                        )
                    }
                }

                if !pipelineRuns.isEmpty {
                    effects.append(
                        .run { [
                            cancelAgent = agentProcessClient.cancel,
                            removeRunSession = pipelineTerminalClient.removeRunSession,
                            removeWorktree = gitWorktreeClient.removeWorktree,
                            projectPath = pipeline.projectPath
                        ] _ in
                            for run in pipelineRuns {
                                if run.isActive {
                                    await cancelAgent(run.id)
                                }
                                await removeRunSession(run.id)
                                if let worktreePath = run.worktreePath {
                                    try? await removeWorktree(projectPath, worktreePath)
                                }
                            }
                        }
                    )
                }

                return effects.isEmpty ? .none : .merge(effects)

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

            case let .pipeline(.removePipelineResponse(id, .success)):
                state.selectedTaskID = taskIDMatchingSelectedPipeline(state: state)

                // Prune the deleted pipeline's runs from state and the DB so
                // they never linger as orphaned records.
                let removedRunIDs = state.runs.filter { $0.pipelineID == id }.map(\.id)
                guard !removedRunIDs.isEmpty else { return .none }
                for runID in removedRunIDs {
                    state.runs.remove(id: runID)
                }
                return .run { [deleteRuns = runStoreClient.deleteRuns] _ in
                    try? await deleteRuns(removedRunIDs)
                }

            case .pipeline(.createPipelineResponse(.failure)):
                state.pendingRunTaskID = nil
                return .none

            case .pipeline:
                return .none

            }
        }
    }
}

extension AppFeature {
    func startRunWithWorktree(
        runID: UUID,
        pipeline: Pipeline,
        task: LooperTask,
        trigger: Run.Trigger,
        reuseWorktreePath: String? = nil,
        startedAt: Date,
        state: inout State
    ) -> Effect<Action> {
        startRunWithWorktreeEffect(
            runID: runID,
            pipeline: pipeline,
            task: task,
            trigger: trigger,
            reuseWorktreePath: reuseWorktreePath,
            startedAt: startedAt,
            state: &state,
            saveRun: runStoreClient.saveRun,
            createWorktree: gitWorktreeClient.createWorktree,
            writeTaskContext: gitWorktreeClient.writeTaskContext,
            executeAgent: agentProcessClient.execute,
            // Keep terminal for pipeline-level shell (fallback)
            upsertRunSession: pipelineTerminalClient.upsertRunSession,
            bootstrapRunSession: pipelineTerminalClient.bootstrapRunSession
        )
    }

    func handleAgentEvent(
        runID: UUID,
        event: AgentEvent,
        state: inout State
    ) -> Effect<Action> {
        guard var run = state.runs[id: runID] else { return .none }

        switch event {
        case let .initialized(sessionID, _):
            run.sessionID = sessionID
            state.runs[id: runID] = run
            return .none

        case let .toolUse(name, inputSummary):
            run.toolCallCount = (run.toolCallCount ?? 0) + 1
            let summary = inputSummary.isEmpty ? name : "\(name): \(inputSummary)"
            run.currentActivity = String(summary.prefix(120))
            state.runs[id: runID] = run
            return .none

        case .toolResult:
            return .none

        case .text:
            return .none

        case let .result(agentResult):
            // A cancellation triggered by pipeline deletion must not write
            // the run back to the DB — its record is being deleted, and a
            // late save would resurrect it as an orphan.
            if state.pipeline.removingPipelineIDs.contains(run.pipelineID) {
                state.runs.remove(id: runID)
                return .none
            }

            run.sessionID = agentResult.sessionID.isEmpty ? run.sessionID : agentResult.sessionID
            run.costUSD = agentResult.costUSD
            run.currentActivity = nil

            let runStatus: Run.Status = agentResult.isError ? .failed : .succeeded
            let suggestedTaskStatus: LooperTask.Status = agentResult.isError ? .todo : .inReview

            let finishedRun = run.finished(
                status: runStatus,
                exitCode: agentResult.isError ? 1 : 0,
                finishedAt: now
            )
            state.runs[id: runID] = finishedRun

            let taskID = run.taskID

            guard let task = state.tasks[id: taskID], task.status == .inProgress else {
                // No task context — just save and do basic worktree removal
                let basicCleanup: Effect<Action> = {
                    guard finishedRun.status == .succeeded,
                          let worktreePath = finishedRun.worktreePath,
                          let pipeline = state.pipeline.pipelines[id: run.pipelineID]
                    else { return .none }
                    return .run { [removeWorktree = gitWorktreeClient.removeWorktree] _ in
                        try? await removeWorktree(pipeline.projectPath, worktreePath)
                    }
                }()

                return .merge(
                    .run { [saveRun = runStoreClient.saveRun] send in
                        do { try await saveRun(finishedRun) } catch {
                            await send(.runPersistenceFailed(.init(description: error.localizedDescription)))
                        }
                    },
                    basicCleanup
                )
            }

            let cleanupEffect: Effect<Action> = {
                guard let pipeline = state.pipeline.pipelines[id: run.pipelineID] else {
                    return .none
                }
                // Capture the run's diff before any worktree cleanup can
                // destroy the evidence — concatenate guarantees the order.
                return .concatenate(
                    captureRunDiffEffect(
                        run: finishedRun,
                        projectPath: pipeline.projectPath,
                        captureDiff: gitWorktreeClient.captureDiff
                    ),
                    postRunGitEffect(
                        run: finishedRun,
                        task: task,
                        projectPath: pipeline.projectPath,
                        postRunAction: state.pipeline.preferences.postRunGitAction,
                        pushBranch: gitWorktreeClient.pushBranch,
                        createPullRequest: gitWorktreeClient.createPullRequest,
                        removeWorktree: gitWorktreeClient.removeWorktree
                    )
                )
            }()

            let hasOtherActiveRuns = state.runs.contains {
                $0.taskID == taskID && $0.isActive && $0.id != runID
            }

            let saveEffect: Effect<Action> = .run { [saveRun = runStoreClient.saveRun] send in
                do { try await saveRun(finishedRun) } catch {
                    await send(.runPersistenceFailed(.init(description: error.localizedDescription)))
                }
            }

            if state.pipeline.preferences.taskProviderConfiguration.canFetchTasks,
               !hasOtherActiveRuns
            {
                return .merge(
                    saveEffect,
                    cleanupEffect,
                    writeTaskStatus(
                        taskID: taskID,
                        status: suggestedTaskStatus,
                        configuration: state.pipeline.preferences.taskProviderConfiguration,
                        state: &state,
                        updateStatus: taskProviderClient.updateTaskStatus
                    )
                )
            }

            if !hasOtherActiveRuns {
                updateTaskStatus(id: taskID, status: suggestedTaskStatus, state: &state)
            }
            return .merge(saveEffect, cleanupEffect)
        }
    }
}

private func captureRunDiffEffect(
    run: Run,
    projectPath: String,
    captureDiff: @escaping @Sendable (String, String) async throws -> String
) -> Effect<AppFeature.Action> {
    guard let worktreePath = run.worktreePath else { return .none }
    let runID = run.id
    return .run { send in
        guard let diff = try? await captureDiff(projectPath, worktreePath),
              !diff.isEmpty
        else { return }
        let diffPath = Run.defaultDiffPath(for: runID)
        let directory = (diffPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        do {
            try diff.write(toFile: diffPath, atomically: true, encoding: .utf8)
            await send(.runDiffCaptured(runID: runID, diffPath: diffPath))
        } catch {
            // Evidence capture is best-effort; the run outcome stands.
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

private func activeRunForTask(
    taskID: LooperTask.ID,
    pipelineID: UUID,
    in runs: IdentifiedArrayOf<Run>
) -> Run? {
    runs.first {
        $0.pipelineID == pipelineID && $0.taskID == taskID && $0.isActive
    }
}

private func activeRunCount(
    forPipeline pipelineID: UUID,
    in runs: IdentifiedArrayOf<Run>
) -> Int {
    runs.filter { $0.pipelineID == pipelineID && $0.isActive }.count
}

private func mostRecentFailedRun(
    taskID: LooperTask.ID,
    pipelineID: UUID,
    in runs: IdentifiedArrayOf<Run>
) -> Run? {
    runs.first {
        $0.pipelineID == pipelineID
            && $0.taskID == taskID
            && $0.status == .failed
            && $0.worktreePath != nil
    }
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
    saveRun: @escaping @Sendable (Run) async throws -> Void,
    pushBranch: @escaping @Sendable (String) async throws -> Void,
    createPullRequest: @escaping @Sendable (String, String, String) async throws -> String,
    removeWorktree: @escaping @Sendable (String, String) async throws -> Void
) -> Effect<AppFeature.Action> {
    guard let pipeline = selectedPipeline(state: state) else { return .none }
    return finishActiveRun(
        task: task,
        pipelineID: pipeline.id,
        status: status,
        exitCode: exitCode,
        state: &state,
        finishedAt: finishedAt,
        saveRun: saveRun,
        pushBranch: pushBranch,
        createPullRequest: createPullRequest,
        removeWorktree: removeWorktree,
        projectPath: pipeline.projectPath
    )
}

private func finishActiveRun(
    task: LooperTask,
    pipelineID: UUID,
    status: Run.Status,
    exitCode: Int32?,
    state: inout AppFeature.State,
    finishedAt: Date,
    saveRun: @escaping @Sendable (Run) async throws -> Void,
    pushBranch: @escaping @Sendable (String) async throws -> Void,
    createPullRequest: @escaping @Sendable (String, String, String) async throws -> String,
    removeWorktree: @escaping @Sendable (String, String) async throws -> Void,
    projectPath: String
) -> Effect<AppFeature.Action> {
    guard let runID = activeRunID(
        pipelineID: pipelineID,
        taskID: task.id,
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

    let saveEffect: Effect<AppFeature.Action> = .run { send in
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

    let cleanupEffect = postRunGitEffect(
        run: finishedRun,
        task: task,
        projectPath: projectPath,
        postRunAction: state.pipeline.preferences.postRunGitAction,
        pushBranch: pushBranch,
        createPullRequest: createPullRequest,
        removeWorktree: removeWorktree
    )

    return .merge(saveEffect, cleanupEffect)
}

private func startRunWithWorktreeEffect(
    runID: UUID,
    pipeline: Pipeline,
    task: LooperTask,
    trigger: Run.Trigger,
    reuseWorktreePath: String?,
    startedAt: Date,
    state: inout AppFeature.State,
    saveRun: @escaping @Sendable (Run) async throws -> Void,
    createWorktree: @escaping @Sendable (String, String) async throws -> String,
    writeTaskContext: @escaping @Sendable (String, LooperTask) async throws -> Void,
    executeAgent: @escaping @Sendable (AgentProcessRequest) async -> AsyncStream<AgentEvent>,
    upsertRunSession: @escaping @Sendable (UUID, Pipeline, String, Bool) async -> Void,
    bootstrapRunSession: @escaping @Sendable (UUID) async -> Void
) -> Effect<AppFeature.Action> {
    let branchName = worktreeBranchName(taskID: task.id, runID: runID)
    let isResume = trigger == .resumeTask && reuseWorktreePath != nil
    let previousSessionID = isResume
        ? state.runs.first(where: {
            $0.taskID == task.id && $0.pipelineID == pipeline.id && $0.status == .failed
        })?.sessionID
        : nil

    // Create the run record immediately (worktreePath set later via effect)
    let run = Run(
        id: runID,
        pipelineID: pipeline.id,
        taskID: task.id,
        status: .running,
        trigger: trigger,
        worktreePath: reuseWorktreePath,
        startedAt: startedAt,
        finishedAt: nil,
        exitCode: nil,
        logPath: logPath(for: runID)
    )
    state.runs.insert(run, at: 0)

    let agentCommand = pipeline.agentCommand
    // The environment check's resolution of "claude" — lets bare-name agent
    // commands launch even when the binary is outside the GUI process PATH.
    let resolvedAgentPath = state.environmentReport?.claude.resolvedPath

    // Deliver queued steering notes with this run (boundary delivery,
    // INTERACTION.md level-1 intervention); consume them on delivery.
    let steeringNotes = state.pendingSteeringNotes[task.id] ?? []
    state.pendingSteeringNotes[task.id] = nil

    let steeringNotesSection = steeringNotes.isEmpty ? "" : """
    \n
    ## Steering Notes from the owner

    Honor these before anything else:

    \(steeringNotes.map { "- \($0.text)" }.joined(separator: "\n"))
    """
    let taskDescription = """
    # Task Context

    **ID**: \(task.id)
    **Title**: \(task.title)
    **Source**: \(task.source)

    ## Description

    \(task.summary)
    """ + steeringNotesSection

    return .run { send in
        do {
            // 1. Create or reuse git worktree
            let worktreePath: String
            if let reuseWorktreePath {
                worktreePath = reuseWorktreePath
            } else {
                worktreePath = try await createWorktree(pipeline.projectPath, branchName)
            }

            // 2. Write/refresh TASK.md context
            try await writeTaskContext(worktreePath, task)

            // 3. Persist run with worktreePath
            var updatedRun = run
            updatedRun.worktreePath = worktreePath
            try await saveRun(updatedRun)

            // 4. Create the run's observation terminal and mark it for
            //    attach — without the bootstrap call the observation script
            //    is never injected and the terminal stays a bare shell.
            await upsertRunSession(runID, pipeline, worktreePath, isResume)
            await bootstrapRunSession(runID)

            // 5. Launch agent process with structured JSON output
            let request = AgentProcessRequest(
                runID: runID,
                workingDirectory: worktreePath,
                taskDescription: taskDescription,
                agentCommand: agentCommand,
                resumeSessionID: previousSessionID,
                resolvedExecutablePath: resolvedAgentPath,
                logPath: run.logPath
            )

            let events = await executeAgent(request)
            for await event in events {
                await send(.agentEventReceived(runID: runID, event))
            }
        } catch {
            await send(
                .runPersistenceFailed(.init(description: error.localizedDescription))
            )
        }
    }
}

private func worktreeBranchName(taskID: String, runID: UUID) -> String {
    let sanitized = taskID
        .replacingOccurrences(of: #"[^a-zA-Z0-9._-]+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        .prefix(40)
    return "looper/\(sanitized)-\(runID.uuidString.prefix(8))"
}

private func logPath(for runID: UUID) -> String {
    Run.defaultLogPath(for: runID)
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

private func postRunGitEffect(
    run: Run,
    task: LooperTask,
    projectPath: String,
    postRunAction: PostRunGitAction,
    pushBranch: @escaping @Sendable (String) async throws -> Void,
    createPullRequest: @escaping @Sendable (String, String, String) async throws -> String,
    removeWorktree: @escaping @Sendable (String, String) async throws -> Void
) -> Effect<AppFeature.Action> {
    guard run.status == .succeeded, let worktreePath = run.worktreePath else {
        return .none
    }

    return .run { _ in
        // 1. Push branch to remote (both pushBranch and pushAndPR need this)
        if postRunAction == .pushBranch || postRunAction == .pushAndPR {
            try? await pushBranch(worktreePath)
        }

        // 2. Create PR if configured
        if postRunAction == .pushAndPR {
            _ = try? await createPullRequest(
                worktreePath,
                task.title,
                task.summary.isEmpty ? task.title : task.summary
            )
        }

        // 3. Remove worktree (code is safe on remote now)
        try? await removeWorktree(projectPath, worktreePath)
    }
}

private func cleanupAllWorktreesEffect(
    taskID: LooperTask.ID,
    runs: IdentifiedArrayOf<Run>,
    pipelines: IdentifiedArrayOf<Pipeline>,
    removeWorktree: @escaping @Sendable (String, String) async throws -> Void
) -> Effect<AppFeature.Action> {
    let worktreeRuns = runs.filter { $0.taskID == taskID && $0.worktreePath != nil && !$0.isActive }
    guard !worktreeRuns.isEmpty else { return .none }

    return .run { send in
        for run in worktreeRuns {
            guard let worktreePath = run.worktreePath,
                  let pipeline = pipelines[id: run.pipelineID]
            else { continue }
            try? await removeWorktree(pipeline.projectPath, worktreePath)
        }
        // Clear worktreePath on the affected run records so nothing keeps
        // pointing at paths that no longer exist.
        await send(.taskWorktreesCleaned(taskID))
    }
}

private func reconcileRecoveredInterruptedTasks(
    state: inout AppFeature.State,
    updateStatus: @escaping @Sendable (LooperTask.ID, LooperTask.Status, TaskProviderConfiguration) async throws -> Void
) -> Effect<AppFeature.Action> {
    let taskIDs = state.recoveredInterruptedTaskIDs.filter { taskID in
        state.tasks[id: taskID]?.status == .inProgress
    }

    guard !taskIDs.isEmpty else { return .none }

    for taskID in taskIDs {
        state.tasks[id: taskID]?.status = .todo
    }
    state.recoveredInterruptedTaskIDs.subtract(taskIDs)

    guard state.pipeline.preferences.taskProviderConfiguration.canFetchTasks else {
        return .none
    }

    var effects: [Effect<AppFeature.Action>] = []
    for taskID in taskIDs {
        effects.append(
            writeTaskStatus(
                taskID: taskID,
                status: .todo,
                configuration: state.pipeline.preferences.taskProviderConfiguration,
                state: &state,
                updateStatus: updateStatus
            )
        )
    }

    return .merge(effects)
}

private func attachTerminalsForDevelopingTasks(
    tasks: [LooperTask],
    pipelines: IdentifiedArrayOf<Pipeline>,
    attachSession: @escaping @Sendable (UUID) async -> Void
) -> Effect<AppFeature.Action> {
    let developingTasks = tasks.filter { $0.status == .inProgress }
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
