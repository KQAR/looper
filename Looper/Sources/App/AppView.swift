import ComposableArchitecture
import SwiftUI

@MainActor
struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    let terminalRegistry: PipelineTerminalRegistry

    var body: some View {
        NavigationSplitView {
            pipelineSidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 360)
        } detail: {
            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(workspaceBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowChromeConfigurator())
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let selectedPipeline {
                    Text(selectedPipeline.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .sharedBackgroundVisibility(.hidden)

            if selectedPipeline != nil {
                ToolbarItem(placement: .primaryAction) {
                    refreshTasksToolbarButton
                }
            }

            if canCreateLocalTask {
                ToolbarItem(placement: .primaryAction) {
                    addTaskToolbarButton
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.isSettingsPresented },
                set: { if !$0 { store.send(.dismissSettingsButtonTapped) } }
            )
        ) {
            SettingsView(store: store)
                .frame(width: 820, height: 760)
                .padding(28)
        }
        .sheet(
            isPresented: Binding(
                get: { store.isLocalTaskComposerPresented },
                set: {
                    if !$0 { store.send(.dismissLocalTaskComposerButtonTapped) }
                }
            )
        ) {
            LocalTaskComposerView(
                projectPath: selectedPipeline?.projectPath
                    ?? store.pipeline.preferences.defaultProjectPath,
                pipelineName: selectedPipeline?.name,
                isCreating: store.isCreatingLocalTask,
                onCancel: { store.send(.dismissLocalTaskComposerButtonTapped) },
                onCreate: { draft in
                    store.send(.createLocalTaskButtonTapped(draft))
                }
            )
            .frame(width: 520)
            .padding(24)
        }
        .alert(
            "Looper Error",
            isPresented: Binding(
                get: { store.taskProviderErrorMessage != nil },
                set: { if !$0 { store.send(.dismissTaskProviderError) } }
            )
        ) {
            Button("OK", role: .cancel) {
                store.send(.dismissTaskProviderError)
            }
        } message: {
            Text(store.taskProviderErrorMessage ?? "")
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    private var pipelineSidebar: some View {
        List(
            selection: Binding(
                get: { store.pipeline.selectedPipelineID },
                set: { store.send(.pipeline(.selectPipeline($0))) }
            )
        ) {
            Section {
                ForEach(store.pipeline.pipelines) { pipeline in
                    PipelineSidebarRow(
                        pipeline: pipeline,
                        taskCount: taskCount(for: pipeline),
                        activeRunTitle: activeRun(for: pipeline)?.status.label
                    )
                    .tag(pipeline.id)
                }
            } header: {
                Text("Pipelines")
            } footer: {
                Text(sidebarFooter)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: 44)
        }
        .overlay(alignment: .bottomLeading) {
            Button {
                store.send(.openSettingsButtonTapped)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .padding(.leading, 12)
            .padding(.bottom, 12)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    store.send(.newPipelineButtonTapped)
                } label: {
                    Label("New Pipeline", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var workspace: some View {
        if let pipeline = selectedPipeline {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 16) {
                    taskBoard(for: pipeline)

                    if shouldDisplayTerminal {
                        terminalWorkspace(for: pipeline)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 0)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .frame(minHeight: geometry.size.height, alignment: .topLeading)
            }
            .background(.regularMaterial)
        } else {
            ContentUnavailableView {
                Label(
                    "No Pipeline Selected",
                    systemImage: "square.stack.3d.up.slash"
                )
            } description: {
                Text(noPipelineSelectedMessage)
            } actions: {
                Button("New Pipeline") {
                    store.send(.newPipelineButtonTapped)
                }

                if !store.pipeline.preferences.hasCompletedOnboarding {
                    Button("Open Settings") {
                        store.send(.openSettingsButtonTapped)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
        }
    }

    private func taskBoard(for pipeline: Pipeline) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                boardColumn(
                    title: "未开始",
                    subtitle: "Ready to start",
                    tasks: boardTasks(for: pipeline, statuses: [.pending]),
                    emptyMessage: pendingColumnEmptyMessage
                )

                boardColumn(
                    title: "进行中",
                    subtitle: "Actively executing",
                    tasks: boardTasks(for: pipeline, statuses: [.developing]),
                    emptyMessage:
                        "No task is currently running in this pipeline."
                )

                boardColumn(
                    title: "已结束",
                    subtitle: "Done or failed",
                    tasks: boardTasks(
                        for: pipeline,
                        statuses: [.done, .failed]
                    ),
                    emptyMessage:
                        "Finished work will accumulate here for quick review."
                )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private func boardColumn(
        title: String,
        subtitle: String,
        tasks: [LooperTask],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                panelHeader(title: title, subtitle: subtitle)
                Spacer()
                AppStatusBadge(title: "\(tasks.count)")
            }

            if tasks.isEmpty {
                Text(emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(tasks) { task in
                        TaskBoardCard(
                            task: task,
                            isSelected: task.id == selectedPipelineTask?.id,
                            isUpdating: store.updatingTaskIDs.contains(task.id),
                            onSelect: {
                                store.send(.selectTask(task.id))
                            },
                            onStart: task.status == .pending
                                ? {
                                    store.send(.selectTask(task.id))
                                    store.send(.startSelectedTaskButtonTapped)
                                } : nil,
                            onMarkDone: task.status == .developing
                                ? {
                                    store.send(.selectTask(task.id))
                                    store.send(
                                        .markSelectedTaskDoneButtonTapped
                                    )
                                } : nil,
                            onMarkFailed: task.status == .developing
                                ? {
                                    store.send(.selectTask(task.id))
                                    store.send(
                                        .markSelectedTaskFailedButtonTapped
                                    )
                                } : nil
                        )
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 20))
    }

    @ViewBuilder
    private func terminalWorkspace(for pipeline: Pipeline) -> some View {
        if let session = activeSession {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Workspace")
                        .font(.headline)
                    Spacer()
                    Button {
                        store.send(
                            .pipeline(.attachSelectedPipelineButtonTapped)
                        )
                    } label: {
                        Label("Attach", systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                }

                PipelineTerminalRepresentable(session: session)
                    .clipShape(.rect(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }
                    .background(
                        Color.black.opacity(0.92),
                        in: .rect(cornerRadius: 22)
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color.primary.opacity(0.04),
                in: .rect(cornerRadius: 18)
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                panelHeader(
                    title: "Workspace",
                    subtitle: "Starting terminal session"
                )

                ProgressView("Preparing terminal surface…")
                    .controlSize(.small)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer()
                    Button("Attach Again") {
                        store.send(
                            .pipeline(.attachSelectedPipelineButtonTapped)
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color.primary.opacity(0.04),
                in: .rect(cornerRadius: 18)
            )
        }
    }

    @ViewBuilder
    private func panelHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var workspaceBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sidebarFooter: String {
        if store.pipeline.pipelines.isEmpty {
            return
                "Create your first pipeline to keep a project workstation warm."
        }
        return "\(store.pipeline.pipelines.count) pipelines available"
    }

    private var noPipelineSelectedMessage: String {
        if !store.pipeline.preferences.hasCompletedOnboarding {
            return
                "Open Settings, choose a task provider, and set local defaults before creating the first pipeline."
        }

        return
            "Create a pipeline first. The entire right side becomes that pipeline's workspace."
    }

    private var refreshTasksToolbarButton: some View {
        Button {
            store.send(.refreshTasksButtonTapped)
        } label: {
            if store.isLoadingTasks {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(
            store.isLoadingTasks
                || !store.pipeline.preferences.hasCompletedOnboarding
        )
        .help("Refresh")
    }

    private var addTaskToolbarButton: some View {
        Button {
            store.send(.openLocalTaskComposerButtonTapped)
        } label: {
            Image(systemName: "plus")
        }
        .help("Add Task")
    }

    private var selectedPipeline: Pipeline? {
        guard let selectedPipelineID = store.pipeline.selectedPipelineID else {
            return nil
        }
        return store.pipeline.pipelines[id: selectedPipelineID]
    }

    private var selectedPipelineTask: LooperTask? {
        guard let selectedPipeline else { return nil }
        guard let selectedTaskID = store.selectedTaskID,
            let task = store.tasks[id: selectedTaskID]
        else {
            return nil
        }
        return pipelineMatchesTask(selectedPipeline, task: task) ? task : nil
    }

    private var selectedSession: PipelineTerminalSession? {
        guard let selectedPipeline else { return nil }
        return terminalRegistry.session(id: selectedPipeline.id)
    }

    private var activeSession: PipelineTerminalSession? {
        guard shouldDisplayTerminal else { return nil }
        return selectedSession
    }

    private var currentRun: Run? {
        guard let selectedPipeline else { return nil }

        if let selectedPipelineTask,
            let matchingRun = store.runs.first(where: {
                $0.pipelineID == selectedPipeline.id
                    && $0.taskID == selectedPipelineTask.id && $0.isActive
            })
        {
            return matchingRun
        }

        return store.runs.first(where: { $0.pipelineID == selectedPipeline.id })
    }

    private var shouldDisplayTerminal: Bool {
        if currentRun?.isActive == true {
            return true
        }

        return selectedPipelineTask?.status == .developing
    }

    private var canCreateLocalTask: Bool {
        store.pipeline.preferences.taskProviderConfiguration.kind == .local
            && selectedPipeline != nil
    }

    private var pendingColumnEmptyMessage: String {
        switch store.pipeline.preferences.taskProviderConfiguration.kind {
        case .local:
            return "No local task has been added to this pipeline yet."
        case .feishu:
            return "No pending task is currently mapped into this pipeline."
        }
    }

    private func pipelineTasks(for pipeline: Pipeline) -> [LooperTask] {
        store.tasks.filter { pipelineMatchesTask(pipeline, task: $0) }
    }

    private func boardTasks(
        for pipeline: Pipeline,
        statuses: [LooperTask.Status]
    ) -> [LooperTask] {
        pipelineTasks(for: pipeline)
            .filter { statuses.contains($0.status) }
    }

    private func pipelineMatchesTask(_ pipeline: Pipeline, task: LooperTask)
        -> Bool
    {
        task.repoPath?.standardizedFileURL.path(percentEncoded: false)
            == pipeline.executionURL.standardizedFileURL.path(
                percentEncoded: false
            )
    }

    private func taskCount(for pipeline: Pipeline) -> Int {
        store.tasks.filter { pipelineMatchesTask(pipeline, task: $0) }.count
    }

    private func activeRun(for pipeline: Pipeline) -> Run? {
        store.runs.first { $0.pipelineID == pipeline.id && $0.isActive }
    }

}
