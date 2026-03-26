import ComposableArchitecture
import SwiftUI

@MainActor
struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    let terminalRegistry: WorkspaceTerminalRegistry

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
        .alert(
            "Task Board Error",
            isPresented: Binding(
                get: { store.taskBoardErrorMessage != nil },
                set: { if !$0 { store.send(.dismissTaskBoardError) } }
            )
        ) {
            Button("OK", role: .cancel) {
                store.send(.dismissTaskBoardError)
            }
        } message: {
            Text(store.taskBoardErrorMessage ?? "")
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
                .disabled(store.isLoadingTasks || !store.workspace.preferences.hasCompletedOnboarding)
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

            if !store.workspace.preferences.hasCompletedOnboarding {
                Text("Finish setup to connect Feishu, verify your environment, and start the first task.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    private var executionStage: some View {
        Group {
            if let workspace = selectedWorkspace,
               let session = terminalRegistry.session(id: workspace.id)
            {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedTask?.title ?? workspace.name)
                                .font(.title3.weight(.semibold))
                            Text(workspace.worktreePath)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        AppStatusBadge(title: session.phase.label)

                        Button {
                            store.send(.workspace(.attachSelectedWorkspaceButtonTapped))
                        } label: {
                            Label("Attach", systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                    }

                    WorkspaceTerminalRepresentable(session: session)
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
                    if !store.workspace.preferences.hasCompletedOnboarding {
                        Button("Open Setup") {
                            store.send(.openSetupButtonTapped)
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

            if let workspace = selectedWorkspace {
                AppInspectorRow(label: "Workspace", value: workspace.name)
                AppInspectorRow(label: "Directory", value: workspace.worktreePath)
                AppInspectorRow(label: "Command", value: workspace.agentCommand.ifEmpty(fallback: "Shell only"))
                AppInspectorRow(label: "tmux", value: workspace.tmuxSessionName)
                AppInspectorRow(label: "Terminal", value: selectedSession?.phase.label ?? "Not Ready")
            } else {
                Text("This task has no active execution workspace yet.")
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
                Label(selectedWorkspace == nil ? "Start Task" : "Resume Task", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                selectedTask?.repoPath == nil
                    || isSelectedTaskUpdating
                    || !store.workspace.preferences.hasCompletedOnboarding
            )

            if let workspace = selectedWorkspace {
                Button {
                    store.send(.workspace(.openInFinderButtonTapped(workspace.id)))
                } label: {
                    Label("Reveal Project", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    store.send(.workspace(.rebuildWorkspaceButtonTapped(workspace.id)))
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
            .disabled(selectedTask == nil || isSelectedTaskUpdating || !store.workspace.preferences.hasCompletedOnboarding)

            Button {
                store.send(.markSelectedTaskFailedButtonTapped)
            } label: {
                Label("Mark Failed", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .disabled(selectedTask == nil || isSelectedTaskUpdating || !store.workspace.preferences.hasCompletedOnboarding)

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
                AppStatusBadge(title: store.workspace.preferences.hasCompletedOnboarding ? "Ready" : "Required")
            }

            AppInspectorRow(
                label: "Task Board",
                value: store.workspace.preferences.taskBoardConfiguration.isConfigured ? "Feishu connected" : "Not configured"
            )
            AppInspectorRow(
                label: "Default Agent",
                value: store.workspace.preferences.defaultAgentCommand.ifEmpty(fallback: "claude")
            )
            AppInspectorRow(
                label: "Environment",
                value: environmentSummary
            )

            Text(setupHint)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(store.workspace.preferences.hasCompletedOnboarding ? "Edit Setup" : "Continue Setup") {
                store.send(.openSetupButtonTapped)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }

    private var executionEmptyStateMessage: String {
        if !store.workspace.preferences.hasCompletedOnboarding {
            "Finish setup first. Looper needs a Feishu task board and a local Claude environment before it can launch work."
        } else {
            "Select a task and start it to attach a project-backed terminal."
        }
    }

    private var setupHint: String {
        store.workspace.preferences.hasCompletedOnboarding
            ? "Re-open setup any time to test Feishu again, update mappings, or verify your local tools."
            : "A first-run setup will connect Feishu, verify Claude and Git, and bring you back ready to start the first task."
    }

    private var environmentSummary: String {
        guard let report = store.environmentReport else { return "Not checked yet" }
        return report.isReady ? "Git and Claude CLI ready" : "Environment needs attention"
    }

    private var selectedTask: LooperTask? {
        guard let selectedTaskID = store.selectedTaskID else { return nil }
        return store.tasks[id: selectedTaskID]
    }

    private var selectedWorkspace: CodingWorkspace? {
        guard let selectedWorkspaceID = store.workspace.selectedWorkspaceID else { return nil }
        return store.workspace.workspaces[id: selectedWorkspaceID]
    }

    private var selectedSession: WorkspaceTerminalSession? {
        guard let selectedWorkspace else { return nil }
        return terminalRegistry.session(id: selectedWorkspace.id)
    }

    private var isSelectedTaskUpdating: Bool {
        guard let selectedTask else { return false }
        return store.updatingTaskIDs.contains(selectedTask.id)
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
