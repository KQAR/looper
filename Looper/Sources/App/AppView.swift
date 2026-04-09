import ComposableArchitecture
import SwiftUI

@MainActor
struct AppView: View {
    private let workspaceInset: CGFloat = 14

    @Bindable var store: StoreOf<AppFeature>
    let terminalRegistry: PipelineTerminalRegistry
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var taskFilter: TaskStreamFilter = .all
    @State private var taskSearchText = ""
    @State private var selectedDetailTab: TaskDetailTab = .console
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
            if !toolbarTitle.isEmpty {
                ToolbarItem(placement: .principal) {
                    Text(toolbarTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .sharedBackgroundVisibility(.hidden)
            }

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
            syncVisibleTaskSelection()
        }
        .onChange(of: taskFilter) {
            syncVisibleTaskSelection()
        }
        .onChange(of: taskSearchText) {
            syncVisibleTaskSelection()
        }
        .onChange(of: visibleTaskIDs) {
            syncVisibleTaskSelection()
        }
        .onChange(of: store.pipeline.selectedPipelineID) {
            syncVisibleTaskSelection()
        }
        .onChange(of: store.selectedTaskID) {
            selectedDetailTab = .console
        }
    }

    // MARK: - Sidebar

    private var pipelineSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
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
            .padding(.bottom, 56)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looper")
                        .font(.title2.weight(.semibold))
                    Text(sidebarSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.send(.newPipelineButtonTapped)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .help(Text("sidebar.newPipeline", bundle: lang.bundle))
            }
            .padding(.top, 10)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .overlay(alignment: .bottomLeading) {
            Button {
                store.send(.openSettingsButtonTapped)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 32, height: 32)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
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
                    Label {
                        Text("sidebar.allPipelines", bundle: lang.bundle)
                            .font(.headline)
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                    Spacer()
                    if activeRunCount > 0 {
                        AppStatusBadge(title: "\(activeRunCount)", tint: .green)
                    }
                }

                Text(String(localized: "sidebar.linkedTasks \(store.tasks.count)", bundle: lang.bundle))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(sidebarSelectionBackground(isSelected: isSelected))
            .contentShape(.rect(cornerRadius: 14))
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
            .padding(.vertical, 8)
            .background(sidebarSelectionBackground(isSelected: isSelected))
            .contentShape(.rect(cornerRadius: 14))
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

    private func sidebarSelectionBackground(isSelected: Bool) -> some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.clear)
            }
        }
    }

    // MARK: - Workspace

    @ViewBuilder
    private var workspace: some View {
        if hasPipelines {
            HStack(alignment: .top, spacing: 24) {
                taskStreamPanel
                    .frame(
                        minWidth: 380,
                        idealWidth: detailTask == nil ? nil : 440,
                        maxWidth: detailTask == nil ? .infinity : 460
                    )

                if detailTask != nil {
                    taskDetailPanel
                        .frame(minWidth: 420, maxWidth: .infinity)
                }
            }
            .padding(workspaceInset)
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
        }
    }

    private var taskStreamPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(taskStreamTitle)
                    .font(.title3.weight(.semibold))

                Text(taskStreamSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            filterBar
            taskSearchField

            if visibleTaskSections.isEmpty {
                ContentUnavailableView(
                    String(localized: "workspace.emptyFiltered.title", bundle: lang.bundle),
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(emptyFilteredMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(visibleTaskSections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(section.title(bundle: lang.bundle))
                                        .font(.headline)
                                    Spacer()
                                    AppStatusBadge(
                                        title: "\(section.tasks.count)",
                                        tint: statusTintColor(section.status)
                                    )
                                }

                                VStack(spacing: 8) {
                                    ForEach(section.tasks) { task in
                                        taskRow(task)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskStreamFilter.allCases) { filter in
                    Button {
                        taskFilter = filter
                    } label: {
                        HStack(spacing: 8) {
                            Text(filter.title(bundle: lang.bundle))
                                .font(.subheadline.weight(.medium))
                            Text("\(taskCount(for: filter))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(taskFilter == filter ? .primary : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background(
                        Capsule()
                            .fill(taskFilter == filter ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                taskFilter == filter ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.06),
                                lineWidth: 1
                            )
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var taskSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(
                "",
                text: $taskSearchText,
                prompt: Text("workspace.searchTasks", bundle: lang.bundle)
            )
            .textFieldStyle(.plain)

            if !taskSearchText.isEmpty {
                Button {
                    taskSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func taskRow(_ task: LooperTask) -> some View {
        let run = activeRunForTask(task)
        let hasSession = terminalSession(for: task) != nil

        return TaskListRow(
            task: task,
            isSelected: task.id == detailTask?.id,
            isUpdating: store.updatingTaskIDs.contains(task.id),
            isActive: run?.isActive == true,
            hasTerminal: hasSession,
            activeRun: run,
            onSelect: {
                store.send(.selectTask(task.id))
            },
            onStart: task.status == .todo ? {
                send(.startSelectedTaskButtonTapped, selecting: task)
            } : nil,
            onMarkReview: task.status == .inProgress ? {
                send(.markSelectedTaskInReviewButtonTapped, selecting: task)
            } : nil,
            onMarkDone: task.status == .inReview ? {
                send(.markSelectedTaskDoneButtonTapped, selecting: task)
            } : nil,
            onReturnToTodo: task.status == .inReview ? {
                send(.returnSelectedTaskToTodoButtonTapped, selecting: task)
            } : nil,
            onAttach: hasSession ? {
                attach(to: task)
            } : nil,
            onCancelRun: run?.isActive == true ? {
                if let runID = run?.id {
                    store.send(.cancelRunButtonTapped(runID))
                }
            } : nil
        )
    }

    @ViewBuilder
    private var taskDetailPanel: some View {
        if let task = detailTask {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(for: task)
                detailTabs
                detailContent(for: task)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
        }
    }

    private func detailHeader(for task: LooperTask) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        AppStatusBadge(
                            title: task.status.localizedLabel(bundle: lang.bundle),
                            tint: statusTintColor(task.status)
                        )
                        AppStatusBadge(title: task.source, tint: .secondary)

                        if let pipeline = pipelineForTask(task) {
                            AppStatusBadge(title: pipeline.name, tint: .blue)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(detailActions(for: task), id: \.title) { action in
                        Button(action.title) {
                            action.handler()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(action.tint.opacity(0.12), in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(action.tint.opacity(0.18), lineWidth: 1)
                        }
                    }
                }
            }

            HStack(alignment: .center) {
                if let summary = trimmedSummary(for: task), !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(task.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var detailTabs: some View {
        HStack(spacing: 8) {
            ForEach(TaskDetailTab.allCases) { tab in
                Button {
                    selectedDetailTab = tab
                } label: {
                    Text(tab.title(bundle: lang.bundle))
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule()
                        .fill(selectedDetailTab == tab ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            selectedDetailTab == tab ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                            lineWidth: 1
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func detailContent(for task: LooperTask) -> some View {
        switch selectedDetailTab {
        case .console:
            consolePanel(for: task)
        case .details:
            detailsPanel(for: task)
        case .run:
            runPanel(for: task)
        }
    }

    @ViewBuilder
    private func consolePanel(for task: LooperTask) -> some View {
        if let session = terminalSession(for: task) {
            VStack(spacing: 12) {
                if let run = activeRunForTask(task) {
                    runSummaryBanner(run: run)
                }

                TerminalHostRepresentable(
                    registry: terminalRegistry,
                    activeSessionID: session.runID
                )
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("workspace.console.idleTitle", bundle: lang.bundle)
                    .font(.headline)

                Text(consoleIdleMessage(for: task))
                    .font(.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    if task.status == .todo {
                        Button(String(localized: "task.start", bundle: lang.bundle)) {
                            send(.startSelectedTaskButtonTapped, selecting: task)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }

                    if pipelineForTask(task) != nil {
                        Button(String(localized: "workspace.openPipeline", bundle: lang.bundle)) {
                            if let pipeline = pipelineForTask(task) {
                                store.send(.pipeline(.selectPipeline(pipeline.id)))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .background(Color.primary.opacity(0.03), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func detailsPanel(for task: LooperTask) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailSection(title: String(localized: "workspace.details.summary", bundle: lang.bundle)) {
                    Text(trimmedSummary(for: task) ?? String(localized: "workspace.details.noSummary", bundle: lang.bundle))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                detailSection(title: String(localized: "workspace.details.meta", bundle: lang.bundle)) {
                    VStack(spacing: 10) {
                        detailMetric(
                            title: String(localized: "workspace.meta.project", bundle: lang.bundle),
                            value: task.repoPath?.path(percentEncoded: false) ?? String(localized: "task.noProject", bundle: lang.bundle)
                        )
                        detailMetric(
                            title: String(localized: "workspace.meta.source", bundle: lang.bundle),
                            value: task.source
                        )
                        detailMetric(
                            title: String(localized: "workspace.meta.pipeline", bundle: lang.bundle),
                            value: pipelineForTask(task)?.name ?? String(localized: "sidebar.allPipelines", bundle: lang.bundle)
                        )
                        detailMetric(
                            title: String(localized: "workspace.meta.status", bundle: lang.bundle),
                            value: task.status.localizedLabel(bundle: lang.bundle)
                        )
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func runPanel(for task: LooperTask) -> some View {
        if let run = latestRun(for: task) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if run.isActive {
                        runSummaryBanner(run: run)
                    }

                    detailSection(title: String(localized: "workspace.run.overview", bundle: lang.bundle)) {
                        VStack(spacing: 10) {
                            detailMetric(
                                title: String(localized: "workspace.meta.runStatus", bundle: lang.bundle),
                                value: run.status.localizedLabel(bundle: lang.bundle)
                            )
                            detailMetric(
                                title: String(localized: "workspace.meta.started", bundle: lang.bundle),
                                value: run.startedAt.formatted(date: .abbreviated, time: .shortened)
                            )
                            if let finishedAt = run.finishedAt {
                                detailMetric(
                                    title: String(localized: "workspace.meta.finished", bundle: lang.bundle),
                                    value: finishedAt.formatted(date: .abbreviated, time: .shortened)
                                )
                            }
                            detailMetric(
                                title: String(localized: "workspace.meta.trigger", bundle: lang.bundle),
                                value: run.trigger.label
                            )
                            if let worktreePath = run.worktreePath {
                                detailMetric(
                                    title: String(localized: "workspace.meta.worktree", bundle: lang.bundle),
                                    value: worktreePath
                                )
                            }
                        }
                    }

                    detailSection(title: String(localized: "workspace.run.usage", bundle: lang.bundle)) {
                        VStack(spacing: 10) {
                            detailMetric(
                                title: String(localized: "workspace.meta.toolCalls", bundle: lang.bundle),
                                value: run.toolCallCount.map(String.init) ?? "0"
                            )
                            detailMetric(
                                title: String(localized: "workspace.meta.cost", bundle: lang.bundle),
                                value: run.costUSD.map { String(format: "$%.2f", $0) } ?? "$0.00"
                            )
                            detailMetric(
                                title: String(localized: "workspace.meta.activity", bundle: lang.bundle),
                                value: run.currentActivity ?? String(localized: "workspace.run.noActivity", bundle: lang.bundle)
                            )
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        } else {
            ContentUnavailableView(
                String(localized: "workspace.run.emptyTitle", bundle: lang.bundle),
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                description: Text(String(localized: "workspace.run.emptyMessage", bundle: lang.bundle))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func runSummaryBanner(run: Run) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let activity = run.currentActivity, !activity.isEmpty {
                Label(activity, systemImage: "sparkles")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                detailPill(
                    title: String(localized: "workspace.meta.runStatus", bundle: lang.bundle),
                    value: run.status.localizedLabel(bundle: lang.bundle)
                )

                if let count = run.toolCallCount, count > 0 {
                    detailPill(
                        title: String(localized: "workspace.meta.toolCalls", bundle: lang.bundle),
                        value: "\(count)"
                    )
                }

                if let cost = run.costUSD, cost > 0 {
                    detailPill(
                        title: String(localized: "workspace.meta.cost", bundle: lang.bundle),
                        value: String(format: "$%.2f", cost)
                    )
                }

                detailPill(
                    title: String(localized: "workspace.meta.elapsed", bundle: lang.bundle),
                    value: elapsedLabel(since: run.startedAt)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.03), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func detailMetric(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func panelBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .fill(tint)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
    }

    private var workspaceBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    .clear,
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color.orange.opacity(0.08),
                    .clear,
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 360
            )
        }
    }

    // MARK: - Computed Properties

    private var hasPipelines: Bool {
        !store.pipeline.pipelines.isEmpty
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

    private var sidebarSummary: String {
        String(localized: "workspace.sidebarSummary \(store.pipeline.pipelines.count) \(activeRunCount)", bundle: lang.bundle)
    }

    private var noPipelineSelectedMessage: String {
        if !store.pipeline.preferences.hasCompletedOnboarding {
            return String(localized: "workspace.noPipeline.onboarding", bundle: lang.bundle)
        }

        return String(localized: "workspace.noPipeline.default", bundle: lang.bundle)
    }

    private var taskStreamTitle: String {
        selectedPipeline?.name ?? String(localized: "workspace.tasks", bundle: lang.bundle)
    }

    private var taskStreamSubtitle: String {
        if let selectedPipeline {
            return selectedPipeline.executionDirectoryName
        }
        return String(localized: "workspace.taskStreamSubtitle", bundle: lang.bundle)
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

        guard let selectedPipeline else {
            return task
        }

        return pipelineMatchesTask(selectedPipeline, task: task) ? task : nil
    }

    private var searchScopedTasks: [LooperTask] {
        let tasks = scopedTasks
        let query = taskSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else { return tasks }

        return tasks.filter { task in
            let haystack = [
                task.title,
                task.summary,
                task.source,
                task.repoPath?.lastPathComponent ?? "",
            ]
            .joined(separator: " ")
            .localizedLowercase

            return haystack.contains(query.localizedLowercase)
        }
    }

    private var scopedTasks: [LooperTask] {
        if let selectedPipeline {
            return pipelineTasks(for: selectedPipeline)
        }
        return Array(store.tasks)
    }

    private var visibleTasks: [LooperTask] {
        taskFilter.apply(to: searchScopedTasks)
    }

    private var visibleTaskIDs: [LooperTask.ID] {
        visibleTasks.map(\.id)
    }

    private var visibleTaskSections: [TaskSection] {
        TaskSection.sections(from: visibleTasks)
    }

    private var detailTask: LooperTask? {
        guard let selectedTask = selectedPipelineTask,
              visibleTasks.contains(where: { $0.id == selectedTask.id })
        else {
            return nil
        }

        return selectedTask
    }

    private var canCreateLocalTask: Bool {
        store.pipeline.preferences.taskProviderConfiguration.kind == .local
            && selectedPipeline != nil
    }

    private var emptyFilteredMessage: String {
        if taskSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "workspace.emptyFiltered.noTasks", bundle: lang.bundle)
        }
        return String(localized: "workspace.emptyFiltered.noResults", bundle: lang.bundle)
    }

    private var activeRunCount: Int {
        store.runs.filter(\.isActive).count
    }

    private func terminalSession(for task: LooperTask) -> (session: PipelineTerminalSession, runID: UUID)? {
        guard task.status == .inProgress else { return nil }
        guard let run = store.runs.first(where: { $0.taskID == task.id && $0.isActive }) else { return nil }
        guard let session = terminalRegistry.runSession(id: run.id) else { return nil }
        return (session, run.id)
    }

    private func activeRunForTask(_ task: LooperTask) -> Run? {
        store.runs.first { $0.taskID == task.id && $0.isActive }
    }

    private func latestRun(for task: LooperTask) -> Run? {
        store.runs
            .filter { $0.taskID == task.id }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private func pipelineForTask(_ task: LooperTask) -> Pipeline? {
        store.pipeline.pipelines.first(where: { pipelineMatchesTask($0, task: task) })
    }

    private func pipelineTasks(for pipeline: Pipeline) -> [LooperTask] {
        store.tasks.filter { pipelineMatchesTask(pipeline, task: $0) }
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

    private func taskCount(for filter: TaskStreamFilter) -> Int {
        filter.apply(to: searchScopedTasks).count
    }

    private func activeRun(for pipeline: Pipeline) -> Run? {
        store.runs.first { $0.pipelineID == pipeline.id && $0.isActive }
    }

    private func syncVisibleTaskSelection() {
        guard let selectedTaskID = store.selectedTaskID else { return }
        guard !visibleTaskIDs.contains(selectedTaskID) else { return }
        store.send(.selectTask(nil))
    }

    private func send(_ action: AppFeature.Action, selecting task: LooperTask) {
        store.send(.selectTask(task.id))
        store.send(action)
    }

    private func attach(to task: LooperTask) {
        if let pipeline = pipelineForTask(task) {
            store.send(.pipeline(.selectPipeline(pipeline.id)))
            store.send(.pipeline(.attachSelectedPipelineButtonTapped))
        }
    }

    private func detailActions(for task: LooperTask) -> [DetailAction] {
        var actions: [DetailAction] = []

        if task.status == .todo {
            actions.append(
                .init(
                    title: String(localized: "task.start", bundle: lang.bundle),
                    tint: .accentColor,
                    handler: { send(.startSelectedTaskButtonTapped, selecting: task) }
                )
            )
        }

        if task.status == .inProgress {
            actions.append(
                .init(
                    title: String(localized: "task.markReview", bundle: lang.bundle),
                    tint: .orange,
                    handler: { send(.markSelectedTaskInReviewButtonTapped, selecting: task) }
                )
            )
            if let runID = activeRunForTask(task)?.id {
                actions.append(
                    .init(
                        title: String(localized: "task.stopRun", defaultValue: "Stop Run", bundle: lang.bundle),
                        tint: .red,
                        handler: { store.send(.cancelRunButtonTapped(runID)) }
                    )
                )
            }
        }

        if task.status == .inReview {
            actions.append(
                .init(
                    title: String(localized: "task.done", bundle: lang.bundle),
                    tint: .green,
                    handler: { send(.markSelectedTaskDoneButtonTapped, selecting: task) }
                )
            )
            actions.append(
                .init(
                    title: String(localized: "task.returnToTodo", bundle: lang.bundle),
                    tint: .secondary,
                    handler: { send(.returnSelectedTaskToTodoButtonTapped, selecting: task) }
                )
            )
        }

        if terminalSession(for: task) != nil {
            actions.append(
                .init(
                    title: String(localized: "workspace.attach", bundle: lang.bundle),
                    tint: .blue,
                    handler: { attach(to: task) }
                )
            )
        }

        return actions
    }

    private func consoleIdleMessage(for task: LooperTask) -> String {
        if task.status == .done {
            return String(localized: "workspace.console.idleDone", bundle: lang.bundle)
        }
        if task.status == .inReview {
            return String(localized: "workspace.console.idleReview", bundle: lang.bundle)
        }
        return String(localized: "workspace.console.idleDefault", bundle: lang.bundle)
    }

    private func trimmedSummary(for task: LooperTask) -> String? {
        let summary = task.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private func elapsedLabel(since startedAt: Date) -> String {
        let elapsed = Date.now.timeIntervalSince(startedAt)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    private func statusTintColor(_ status: LooperTask.Status) -> Color {
        switch status {
        case .todo:
            .secondary
        case .inProgress:
            .orange
        case .inReview:
            .blue
        case .done:
            .green
        }
    }
}

private enum TaskStreamFilter: CaseIterable, Identifiable {
    case all
    case todo
    case inProgress
    case inReview
    case done

    var id: Self { self }

    func title(bundle: Bundle) -> String {
        switch self {
        case .all:
            String(localized: "workspace.filter.all", bundle: bundle)
        case .todo:
            String(localized: "status.todo", bundle: bundle)
        case .inProgress:
            String(localized: "status.inProgress", bundle: bundle)
        case .inReview:
            String(localized: "status.inReview", bundle: bundle)
        case .done:
            String(localized: "status.done", bundle: bundle)
        }
    }

    func apply(to tasks: [LooperTask]) -> [LooperTask] {
        switch self {
        case .all:
            tasks
        case .todo:
            tasks.filter { $0.status == .todo }
        case .inProgress:
            tasks.filter { $0.status == .inProgress }
        case .inReview:
            tasks.filter { $0.status == .inReview }
        case .done:
            tasks.filter { $0.status == .done }
        }
    }
}

private enum TaskDetailTab: CaseIterable, Identifiable {
    case console
    case details
    case run

    var id: Self { self }

    func title(bundle: Bundle) -> String {
        switch self {
        case .console:
            String(localized: "workspace.detail.console", bundle: bundle)
        case .details:
            String(localized: "workspace.detail.details", bundle: bundle)
        case .run:
            String(localized: "workspace.detail.run", bundle: bundle)
        }
    }
}

private struct TaskSection: Identifiable {
    let status: LooperTask.Status
    let tasks: [LooperTask]

    var id: LooperTask.Status { status }

    func title(bundle: Bundle) -> String {
        status.localizedLabel(bundle: bundle)
    }

    static func sections(from tasks: [LooperTask]) -> [TaskSection] {
        let orderedStatuses: [LooperTask.Status] = [.inProgress, .inReview, .todo, .done]
        return orderedStatuses.compactMap { status in
            let grouped = tasks.filter { $0.status == status }
            guard !grouped.isEmpty else { return nil }
            return TaskSection(status: status, tasks: grouped)
        }
    }
}

private struct DetailAction {
    let title: String
    let tint: Color
    let handler: @MainActor () -> Void
}
