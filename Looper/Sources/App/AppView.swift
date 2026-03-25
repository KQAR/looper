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
                    store.send(.refreshTasksButtonTapped)
                } label: {
                    if store.isLoadingTasks {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(store.isLoadingTasks)
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

            if !taskBoardConfiguration.isConfigured {
                Text("Configure Feishu below, then refresh to load tasks.")
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
                    Text("Select a task and start it to attach a project-backed terminal.")
                } actions: {
                    Button("Start Task") {
                        store.send(.startSelectedTaskButtonTapped)
                    }
                    .disabled(selectedTask?.repoPath == nil || isSelectedTaskUpdating)
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
                workspaceDefaultsCard
                taskBoardCard
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
            .disabled(selectedTask?.repoPath == nil || isSelectedTaskUpdating)

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
            .disabled(selectedTask == nil || isSelectedTaskUpdating)

            Button {
                store.send(.markSelectedTaskFailedButtonTapped)
            } label: {
                Label("Mark Failed", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .disabled(selectedTask == nil || isSelectedTaskUpdating)

            if isSelectedTaskUpdating {
                ProgressView("Syncing task status…")
                    .controlSize(.small)
                    .font(.footnote)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }

    private var workspaceDefaultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Execution Defaults")
                    .font(.headline)
                Spacer()
                Button("Save") {
                    store.send(.workspace(.savePreferencesButtonTapped))
                }
                .buttonStyle(.bordered)
                .disabled(store.workspace.isSavingPreferences)
            }

            Text("These values are used when a task starts a new local execution workspace.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Project")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "/Users/you/project",
                text: defaultRepositoryPathBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Agent")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "claude",
                text: defaultAgentCommandBinding
            )
            .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }

    private var taskBoardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Task Board")
                    .font(.headline)
                Spacer()
                AppStatusBadge(title: taskBoardConfiguration.isConfigured ? "Configured" : "Needs Setup")
            }

            Text("MVP uses a Feishu Bitable table. Title, summary, repository, and status field names must match your table exactly.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("App ID")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "cli_xxx",
                text: taskBoardAppIDBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("App Secret")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            SecureField(
                "xxx",
                text: taskBoardAppSecretBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Bitable App Token")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "bascn_xxx",
                text: taskBoardAppTokenBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Table ID")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "tblxxx",
                text: taskBoardTableIDBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Title Field")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "Title",
                text: taskBoardTitleFieldBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Summary Field")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "Summary",
                text: taskBoardSummaryFieldBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Status Field")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "Status",
                text: taskBoardStatusFieldBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Repository Field")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "Repository",
                text: taskBoardRepositoryFieldBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Pending Value")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "pending",
                text: taskBoardPendingValueBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Running Value")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "developing",
                text: taskBoardDevelopingValueBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Done Value")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "done",
                text: taskBoardDoneValueBinding
            )
            .textFieldStyle(.roundedBorder)

            Text("Failed Value")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "failed",
                text: taskBoardFailedValueBinding
            )
            .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
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

    private var taskBoardConfiguration: TaskBoardConfiguration {
        store.workspace.preferences.taskBoardConfiguration
    }

    private var isSelectedTaskUpdating: Bool {
        guard let selectedTask else { return false }
        return store.updatingTaskIDs.contains(selectedTask.id)
    }

    private var defaultRepositoryPathBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.defaultRepositoryPath },
            set: { store.send(.workspace(.binding(.set(\.preferences.defaultRepositoryPath, $0)))) }
        )
    }

    private var defaultAgentCommandBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.defaultAgentCommand },
            set: { store.send(.workspace(.binding(.set(\.preferences.defaultAgentCommand, $0)))) }
        )
    }

    private var taskBoardAppIDBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.appID },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.appID, $0)))) }
        )
    }

    private var taskBoardAppSecretBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.appSecret },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.appSecret, $0)))) }
        )
    }

    private var taskBoardAppTokenBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.appToken },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.appToken, $0)))) }
        )
    }

    private var taskBoardTableIDBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.tableID },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.tableID, $0)))) }
        )
    }

    private var taskBoardTitleFieldBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.titleFieldName },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.titleFieldName, $0)))) }
        )
    }

    private var taskBoardSummaryFieldBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.summaryFieldName },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.summaryFieldName, $0)))) }
        )
    }

    private var taskBoardStatusFieldBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.statusFieldName },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.statusFieldName, $0)))) }
        )
    }

    private var taskBoardRepositoryFieldBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.repoPathFieldName },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.repoPathFieldName, $0)))) }
        )
    }

    private var taskBoardPendingValueBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.pendingStatusValue },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.pendingStatusValue, $0)))) }
        )
    }

    private var taskBoardDevelopingValueBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.developingStatusValue },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.developingStatusValue, $0)))) }
        )
    }

    private var taskBoardDoneValueBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.doneStatusValue },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.doneStatusValue, $0)))) }
        )
    }

    private var taskBoardFailedValueBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.failedStatusValue },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.failedStatusValue, $0)))) }
        )
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
private struct AppStatusBadge: View {
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
