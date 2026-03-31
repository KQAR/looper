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
    @State private var expandedTerminalPipelineID: UUID?
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
                Text(toolbarTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .sharedBackgroundVisibility(.hidden)

            if hasPipelines {
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

    // MARK: - Sidebar

    private var pipelineSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("sidebar.pipelines", bundle: lang.bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                if hasPipelines {
                    allPipelinesSidebarButton
                }

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

    private var allPipelinesSidebarButton: some View {
        let isSelected = isAllPipelinesMode

        return Button {
            store.send(.pipeline(.selectPipeline(nil)))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("sidebar.allPipelines", bundle: lang.bundle)
                        .font(.headline)
                    Spacer()
                    if activeRunCount > 0 {
                        AppStatusBadge(title: "\(activeRunCount) active")
                    }
                }

                Text(String(localized: "sidebar.linkedTasks \(store.tasks.count)", bundle: lang.bundle))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
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
    }

    private func pipelineSidebarButton(for pipeline: Pipeline) -> some View {
        let isSelected = !isAllPipelinesMode && store.pipeline.selectedPipelineID == pipeline.id

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

    // MARK: - Workspace

    @ViewBuilder
    private var workspace: some View {
        if hasPipelines {
            ZStack {
                GeometryReader { geometry in
                    taskBoard(for: selectedPipeline)
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

                expandedTerminalOverlay
                    .opacity(isTerminalOverlayVisible ? 1 : 0)
                    .allowsHitTesting(isTerminalOverlayVisible)
                    .animation(.easeInOut(duration: 0.2), value: isTerminalOverlayVisible)
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

    private func taskBoard(for pipeline: Pipeline?) -> some View {
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
                    emptyMessage: String(localized: "board.developing.empty", bundle: lang.bundle),
                    sessionForTask: { task in terminalSession(for: task) }
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
        emptyMessage: String,
        sessionForTask: ((LooperTask) -> PipelineTerminalSession?)? = nil
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
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(tasks) { task in
                            let session = sessionForTask?(task)
                            let taskPipelineID = pipelineForTask(task)?.id
                            let hasSession = session != nil
                            TaskBoardCard(
                                task: task,
                                isSelected: task.id == selectedPipelineTask?.id,
                                isUpdating: store.updatingTaskIDs.contains(task.id),
                                hasTerminal: hasSession,
                                isTerminalExpanded: taskPipelineID != nil && taskPipelineID == expandedTerminalPipelineID,
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
                                    } : nil,
                                onAttach: hasSession
                                    ? {
                                        if let pipeline = pipelineForTask(task) {
                                            store.send(.pipeline(.selectPipeline(pipeline.id)))
                                            store.send(.pipeline(.attachSelectedPipelineButtonTapped))
                                        }
                                    } : nil,
                                onExpandTerminal: hasSession
                                    ? {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            expandedTerminalPipelineID = taskPipelineID
                                        }
                                    } : nil
                            )
                        }
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


    private var expandedTerminalOverlay: some View {
        let sessionName = expandedTerminalPipelineID
            .flatMap { terminalRegistry.session(id: $0) }?.displayTitle ?? ""

        return VStack(spacing: 0) {
            HStack {
                Text(sessionName)
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedTerminalPipelineID = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            TerminalHostRepresentable(
                registry: terminalRegistry,
                activeSessionID: expandedTerminalPipelineID
            )
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .padding(24)
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

    // MARK: - Computed Properties

    private var hasPipelines: Bool {
        !store.pipeline.pipelines.isEmpty
    }

    private var isTerminalOverlayVisible: Bool {
        expandedTerminalPipelineID != nil
    }

    private var isAllPipelinesMode: Bool {
        store.pipeline.selectedPipelineID == nil && hasPipelines
    }

    private var toolbarTitle: String {
        if let selectedPipeline {
            return selectedPipeline.name
        }
        if isAllPipelinesMode {
            return String(localized: "sidebar.allPipelines", bundle: lang.bundle)
        }
        return ""
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
        guard let selectedTaskID = store.selectedTaskID,
            let task = store.tasks[id: selectedTaskID]
        else {
            return nil
        }

        // In "all pipelines" mode, any task is valid
        guard let selectedPipeline else {
            return task
        }

        return pipelineMatchesTask(selectedPipeline, task: task) ? task : nil
    }

    private func terminalSession(for task: LooperTask) -> PipelineTerminalSession? {
        guard task.status == .developing else { return nil }
        guard let pipeline = pipelineForTask(task) else { return nil }
        return terminalRegistry.session(id: pipeline.id)
    }

    private func pipelineForTask(_ task: LooperTask) -> Pipeline? {
        store.pipeline.pipelines.first(where: { pipelineMatchesTask($0, task: task) })
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

    private var activeRunCount: Int {
        store.runs.filter(\.isActive).count
    }

    private func pipelineTasks(for pipeline: Pipeline) -> [LooperTask] {
        store.tasks.filter { pipelineMatchesTask(pipeline, task: $0) }
    }

    private func boardTasks(
        for pipeline: Pipeline?,
        statuses: [LooperTask.Status]
    ) -> [LooperTask] {
        if let pipeline {
            return pipelineTasks(for: pipeline)
                .filter { statuses.contains($0.status) }
        }
        return store.tasks.filter { statuses.contains($0.status) }
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
