import ComposableArchitecture
import SwiftUI

@MainActor
struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    let terminalRegistry: PipelineTerminalRegistry

    var body: some View {
        HSplitView {
            taskInbox
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

            executionStage
                .frame(minWidth: 640, idealWidth: 840)

            contextInspector
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .sheet(
            isPresented: Binding(
                get: { store.isSetupWizardPresented },
                set: { if !$0 { store.send(.dismissSetupWizardButtonTapped) } }
            )
        ) {
            SetupWizardView(store: store)
                .frame(width: 760, height: 760)
                .padding(28)
        }
        .sheet(
            isPresented: Binding(
                get: { store.isLocalTaskComposerPresented },
                set: { if !$0 { store.send(.dismissLocalTaskComposerButtonTapped) } }
            )
        ) {
            LocalTaskComposerView(
                defaultProjectPath: store.pipeline.preferences.defaultProjectPath,
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
            "Task Provider Error",
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

    private var taskInbox: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task Inbox")
                        .font(.title2.weight(.semibold))
                    Text("Tasks drive execution. Projects and terminals are attached runtime.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.send(.openSetupButtonTapped)
                } label: {
                    Label("Setup", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)

                if store.pipeline.preferences.taskProviderConfiguration.kind == .local {
                    Button {
                        store.send(.openLocalTaskComposerButtonTapped)
                    } label: {
                        Label("New Task", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.pipeline.preferences.hasCompletedOnboarding)
                }

                Button {
                    store.send(.refreshTasksButtonTapped)
                } label: {
                    if store.isLoadingTasks {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoadingTasks || !store.pipeline.preferences.hasCompletedOnboarding)
            }

            List(
                selection: Binding(
                    get: { store.selectedTaskID },
                    set: { store.send(.selectTask($0)) }
                )
            ) {
                ForEach(store.tasks) { task in
                    TaskListRow(task: task)
                        .tag(task.id)
                }
            }
            .listStyle(.sidebar)

            Text("\(store.tasks.count) tasks")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !store.pipeline.preferences.hasCompletedOnboarding {
                Text(setupIncompleteMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if store.tasks.isEmpty {
                Text(emptyInboxMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    private var executionStage: some View {
        Group {
            if let pipeline = selectedPipeline,
               let session = terminalRegistry.session(id: pipeline.id)
            {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedTask?.title ?? pipeline.name)
                                .font(.title3.weight(.semibold))
                            Text(pipeline.executionPath)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        AppStatusBadge(title: session.phase.label)

                        Button {
                            store.send(.pipeline(.attachSelectedPipelineButtonTapped))
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
                        .background(Color.black.opacity(0.92), in: .rect(cornerRadius: 22))
                }
                .padding(18)
                .background(.regularMaterial, in: .rect(cornerRadius: 28))
            } else {
                ContentUnavailableView {
                    Label("No Active Execution", systemImage: "terminal")
                } description: {
                    Text(executionEmptyStateMessage)
                } actions: {
                    if !store.pipeline.preferences.hasCompletedOnboarding {
                        Button("Open Setup") {
                            store.send(.openSetupButtonTapped)
                        }
                    } else if store.pipeline.preferences.taskProviderConfiguration.kind == .local && store.tasks.isEmpty {
                        Button("Create Local Task") {
                            store.send(.openLocalTaskComposerButtonTapped)
                        }
                    } else {
                        Button("Start Task") {
                            store.send(.startSelectedTaskButtonTapped)
                        }
                        .disabled(selectedTask?.repoPath == nil || isSelectedTaskUpdating)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial, in: .rect(cornerRadius: 28))
            }
        }
    }

    private var contextInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                taskCard
                executionCard
                controlsCard
                setupCard
            }
            .padding(18)
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task")
                .font(.headline)

            if let task = selectedTask {
                AppInspectorRow(label: "Title", value: task.title)
                AppInspectorRow(label: "Status", value: task.status.label)
                AppInspectorRow(label: "Source", value: task.source)
                AppInspectorRow(label: "Project", value: task.repoPath?.path(percentEncoded: false) ?? "Unassigned")

                Text(task.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a task to inspect its execution context.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }

    private var executionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Execution")
                .font(.headline)

            if let pipeline = selectedPipeline {
                AppInspectorRow(label: "Pipeline", value: pipeline.name)
                AppInspectorRow(label: "Directory", value: pipeline.executionPath)
                AppInspectorRow(label: "Command", value: pipeline.agentCommand.ifEmpty(fallback: "Shell only"))
                AppInspectorRow(label: "tmux", value: pipeline.tmuxSessionName)
                AppInspectorRow(label: "Terminal", value: selectedSession?.phase.label ?? "Not Ready")
            } else {
                Text("This task has no active execution pipeline yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls")
                .font(.headline)

            Button {
                store.send(.startSelectedTaskButtonTapped)
            } label: {
                Label(selectedPipeline == nil ? "Start Task" : "Resume Task", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                selectedTask?.repoPath == nil
                    || isSelectedTaskUpdating
                    || !store.pipeline.preferences.hasCompletedOnboarding
            )

            if let pipeline = selectedPipeline {
                Button {
                    store.send(.pipeline(.revealPipelineInFinderButtonTapped(pipeline.id)))
                } label: {
                    Label("Reveal Project", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    store.send(.pipeline(.rebuildPipelineButtonTapped(pipeline.id)))
                } label: {
                    Label("Restart Execution", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Button {
                store.send(.markSelectedTaskDoneButtonTapped)
            } label: {
                Label("Mark Done", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .disabled(selectedTask == nil || isSelectedTaskUpdating || !store.pipeline.preferences.hasCompletedOnboarding)

            Button {
                store.send(.markSelectedTaskFailedButtonTapped)
            } label: {
                Label("Mark Failed", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .disabled(selectedTask == nil || isSelectedTaskUpdating || !store.pipeline.preferences.hasCompletedOnboarding)

            if isSelectedTaskUpdating {
                ProgressView("Syncing task status…")
                    .controlSize(.small)
                    .font(.footnote)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Setup")
                    .font(.headline)
                Spacer()
                AppStatusBadge(title: store.pipeline.preferences.hasCompletedOnboarding ? "Ready" : "Required")
            }

            AppInspectorRow(
                label: "Task Source",
                value: taskProviderSummary
            )
            AppInspectorRow(
                label: "Default Agent",
                value: store.pipeline.preferences.defaultAgentCommand.ifEmpty(fallback: "claude")
            )
            AppInspectorRow(
                label: "Environment",
                value: environmentSummary
            )

            Text(setupHint)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(store.pipeline.preferences.hasCompletedOnboarding ? "Edit Setup" : "Continue Setup") {
                store.send(.openSetupButtonTapped)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }

    private var executionEmptyStateMessage: String {
        if !store.pipeline.preferences.hasCompletedOnboarding {
            "Finish setup first. Looper needs a task source and a local Claude environment before it can launch work."
        } else if store.pipeline.preferences.taskProviderConfiguration.kind == .local && store.tasks.isEmpty {
            "Create a local task first, then start it to attach a project-backed terminal."
        } else {
            "Select a task and start it to attach a project-backed terminal."
        }
    }

    private var setupHint: String {
        store.pipeline.preferences.hasCompletedOnboarding
            ? "Re-open setup any time to switch providers, test Feishu again, or verify your local tools."
            : "A first-run setup will choose a task source, verify Claude and Git, and bring you back ready to start the first task."
    }

    private var environmentSummary: String {
        guard let report = store.environmentReport else { return "Not checked yet" }
        return report.isReady ? "Git and Claude CLI ready" : "Environment needs attention"
    }

    private var selectedTask: LooperTask? {
        guard let selectedTaskID = store.selectedTaskID else { return nil }
        return store.tasks[id: selectedTaskID]
    }

    private var selectedPipeline: Pipeline? {
        guard let selectedPipelineID = store.pipeline.selectedPipelineID else { return nil }
        return store.pipeline.pipelines[id: selectedPipelineID]
    }

    private var selectedSession: PipelineTerminalSession? {
        guard let selectedPipeline else { return nil }
        return terminalRegistry.session(id: selectedPipeline.id)
    }

    private var isSelectedTaskUpdating: Bool {
        guard let selectedTask else { return false }
        return store.updatingTaskIDs.contains(selectedTask.id)
    }

    private var taskProviderSummary: String {
        switch store.pipeline.preferences.taskProviderConfiguration.kind {
        case .local:
            return "Local Tasks"
        case .feishu:
            return store.pipeline.preferences.feishuProviderConfiguration.isConfigured ? "Feishu connected" : "Feishu not configured"
        }
    }

    private var setupIncompleteMessage: String {
        switch store.pipeline.preferences.taskProviderConfiguration.kind {
        case .local:
            "Finish setup to enable Local Tasks, verify your environment, and create the first task."
        case .feishu:
            "Finish setup to connect Feishu, verify your environment, and start the first task."
        }
    }

    private var emptyInboxMessage: String {
        switch store.pipeline.preferences.taskProviderConfiguration.kind {
        case .local:
            "No local tasks yet. Create one to start the first execution."
        case .feishu:
            "No synced tasks yet. Refresh the inbox or check the current Feishu mapping."
        }
    }
}

@MainActor
private struct TaskListRow: View {
    let task: LooperTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.title)
                    .font(.headline)
                Spacer()
                AppStatusBadge(title: task.status.label)
            }

            Text(task.repoPath?.lastPathComponent ?? "No Project")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            Text(task.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private struct AppInspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
        }
    }
}

@MainActor
struct AppStatusBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

private extension String {
    func ifEmpty(fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
