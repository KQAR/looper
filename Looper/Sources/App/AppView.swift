import ComposableArchitecture
import SwiftUI

@MainActor
struct AppView: View {
    private let workspaceHorizontalInset: CGFloat = 12
    private let workspaceBottomInset: CGFloat = 12
    private let boardColumnSpacing: CGFloat = 12

    @Bindable var store: StoreOf<AppFeature>
    let terminalRegistry: PipelineTerminalRegistry
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private let lang = AppLanguageManager.shared

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            pipelineSidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 360)
        } detail: {
            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(workspaceBackground)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .animation(.smooth(duration: 0.32, extraBounce: 0), value: columnVisibility)
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
                .frame(width: 800, height: 600)
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
            String(localized: "alert.error", bundle: lang.bundle),
            isPresented: Binding(
                get: { store.taskProviderErrorMessage != nil },
                set: { if !$0 { store.send(.dismissTaskProviderError) } }
            )
        ) {
            Button(String(localized: "alert.ok", bundle: lang.bundle), role: .cancel) {
                store.send(.dismissTaskProviderError)
            }
        } message: {
            Text(store.taskProviderErrorMessage ?? "")
        }
        .confirmationDialog(
            String(localized: "context.deleteConfirm.title", bundle: lang.bundle),
            isPresented: Binding(
                get: { store.pipelinePendingDeletionID != nil },
                set: { if !$0 { store.send(.cancelDeletePipeline) } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "context.deleteConfirm.delete", bundle: lang.bundle), role: .destructive) {
                store.send(.confirmDeletePipeline)
            }
            Button(String(localized: "context.deleteConfirm.cancel", bundle: lang.bundle), role: .cancel) {
                store.send(.cancelDeletePipeline)
            }
        } message: {
            Text("context.deleteConfirm.message", bundle: lang.bundle)
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    private var pipelineSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("sidebar.pipelines", bundle: lang.bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                ForEach(store.pipeline.pipelines) { pipeline in
                    pipelineSidebarButton(for: pipeline)
                }

                Text(sidebarFooter)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Looper")
                    .font(.title)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    store.send(.newPipelineButtonTapped)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(Text("sidebar.newPipeline", bundle: lang.bundle))
            }
            .padding(.top, 8)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: 44)
        }
        .overlay(alignment: .bottomLeading) {
            Button {
                store.send(.openSettingsButtonTapped)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(Text("sidebar.settings", bundle: lang.bundle))
            .padding(.leading, 12)
            .padding(.bottom, 12)
        }
    }

    private func pipelineSidebarButton(for pipeline: Pipeline) -> some View {
        let isSelected = store.pipeline.selectedPipelineID == pipeline.id

        return Button {
            store.send(.pipeline(.selectPipeline(pipeline.id)))
        } label: {
            PipelineSidebarRow(
                pipeline: pipeline,
                taskCount: taskCount(for: pipeline),
                activeRunTitle: activeRun(for: pipeline)?.status.localizedLabel(bundle: lang.bundle)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2))
                    : nil
            )
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                store.send(.pipeline(.revealPipelineInFinderButtonTapped(pipeline.id)))
            } label: {
                Label(String(localized: "context.revealInFinder", bundle: lang.bundle), systemImage: "folder")
            }

            Button {
                store.send(.pipeline(.rebuildPipelineButtonTapped(pipeline.id)))
            } label: {
                Label(String(localized: "context.rebuildTerminal", bundle: lang.bundle), systemImage: "terminal")
            }

            Divider()

            Button(role: .destructive) {
                store.send(.deletePipelineMenuTapped(pipeline.id))
            } label: {
                Label(String(localized: "context.deletePipeline", bundle: lang.bundle), systemImage: "trash")
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
                .padding(.horizontal, workspaceHorizontalInset)
                .padding(.bottom, workspaceBottomInset)
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
                Label {
                    Text("workspace.noPipelineSelected", bundle: lang.bundle)
                } icon: {
                    Image(systemName: "square.stack.3d.up.slash")
                }
            } description: {
                Text(noPipelineSelectedMessage)
            } actions: {
                Button(String(localized: "workspace.newPipeline", bundle: lang.bundle)) {
                    store.send(.newPipelineButtonTapped)
                }

                if !store.pipeline.preferences.hasCompletedOnboarding {
                    Button(String(localized: "workspace.openSettings", bundle: lang.bundle)) {
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
            HStack(alignment: .top, spacing: boardColumnSpacing) {
                boardColumn(
                    title: String(localized: "board.pending.title", bundle: lang.bundle),
                    subtitle: String(localized: "board.pending.subtitle", bundle: lang.bundle),
                    tasks: boardTasks(for: pipeline, statuses: [.pending]),
                    emptyMessage: pendingColumnEmptyMessage
                )

                boardColumn(
                    title: String(localized: "board.developing.title", bundle: lang.bundle),
                    subtitle: String(localized: "board.developing.subtitle", bundle: lang.bundle),
                    tasks: boardTasks(for: pipeline, statuses: [.developing]),
                    emptyMessage: String(localized: "board.developing.empty", bundle: lang.bundle)
                )

                boardColumn(
                    title: String(localized: "board.done.title", bundle: lang.bundle),
                    subtitle: String(localized: "board.done.subtitle", bundle: lang.bundle),
                    tasks: boardTasks(
                        for: pipeline,
                        statuses: [.done, .failed]
                    ),
                    emptyMessage: String(localized: "board.done.empty", bundle: lang.bundle)
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
                    Text("workspace.title", bundle: lang.bundle)
                        .font(.headline)
                    Spacer()
                    Button {
                        store.send(
                            .pipeline(.attachSelectedPipelineButtonTapped)
                        )
                    } label: {
                        Label {
                            Text("workspace.attach", bundle: lang.bundle)
                        } icon: {
                            Image(systemName: "terminal")
                        }
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
                    title: String(localized: "workspace.title", bundle: lang.bundle),
                    subtitle: String(localized: "workspace.startingSession", bundle: lang.bundle)
                )

                ProgressView {
                    Text("workspace.preparingTerminal", bundle: lang.bundle)
                }
                    .controlSize(.small)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer()
                    Button(String(localized: "workspace.attachAgain", bundle: lang.bundle)) {
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
            return String(localized: "sidebar.footer.empty", bundle: lang.bundle)
        }
        return String(localized: "sidebar.footer.count \(store.pipeline.pipelines.count)", bundle: lang.bundle)
    }

    private var noPipelineSelectedMessage: String {
        if !store.pipeline.preferences.hasCompletedOnboarding {
            return String(localized: "workspace.noPipeline.onboarding", bundle: lang.bundle)
        }

        return String(localized: "workspace.noPipeline.default", bundle: lang.bundle)
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
        .help(Text("toolbar.refresh", bundle: lang.bundle))
    }

    private var addTaskToolbarButton: some View {
        Button {
            store.send(.openLocalTaskComposerButtonTapped)
        } label: {
            Image(systemName: "plus")
        }
        .help(Text("toolbar.addTask", bundle: lang.bundle))
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
            return String(localized: "board.pending.empty.local", bundle: lang.bundle)
        case .feishu:
            return String(localized: "board.pending.empty.feishu", bundle: lang.bundle)
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
