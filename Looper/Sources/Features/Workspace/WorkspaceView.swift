import ComposableArchitecture
import SwiftUI

@MainActor
struct WorkspaceView: View {
    @Bindable var store: StoreOf<WorkspaceFeature>
    let terminalRegistry: WorkspaceTerminalRegistry

    var body: some View {
        HSplitView {
            workspaceSidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

            terminalStage
                .frame(minWidth: 640, idealWidth: 820)

            workspaceInspector
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
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
        .sheet(isPresented: $store.isComposerPresented) {
            WorkspaceComposerSheet(store: store)
                .frame(width: 540)
                .padding(24)
        }
        .alert(
            "Workspace Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.send(.dismissError) } }
            )
        ) {
            Button("OK", role: .cancel) {
                store.send(.dismissError)
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    private var workspaceSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspaces")
                        .font(.title2.weight(.semibold))
                    Text("Each workspace maps one project directory to one live terminal context.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.send(.selectPreviousWorkspace)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered)
                .disabled(store.workspaces.isEmpty)
                .keyboardShortcut(.upArrow, modifiers: [.command])

                Button {
                    store.send(.selectNextWorkspace)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.bordered)
                .disabled(store.workspaces.isEmpty)
                .keyboardShortcut(.downArrow, modifiers: [.command])

                Button {
                    store.send(.openProjectButtonTapped)
                } label: {
                    Label("Open", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(store.isCreatingWorkspace)

                Button {
                    store.send(.addWorkspaceButtonTapped)
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            List(
                selection: Binding(
                    get: { store.selectedWorkspaceID },
                    set: { store.send(.selectWorkspace($0)) }
                )
            ) {
                ForEach(store.workspaces) { workspace in
                    WorkspaceListRow(
                        workspace: workspace,
                        session: terminalRegistry.session(id: workspace.id)
                    )
                    .tag(workspace.id)
                }
            }
            .listStyle(.sidebar)

            Text("\(store.workspaces.count) active workspace\(store.workspaces.count == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(.secondary)

            defaultsCard
        }
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    private var terminalStage: some View {
        Group {
            if let workspace = selectedWorkspace,
               let session = terminalRegistry.session(id: workspace.id)
            {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.displayTitle)
                                .font(.title3.weight(.semibold))
                            Text(workspace.worktreePath)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        StatusBadge(title: session.phase.label)

                        Button {
                            store.send(.attachSelectedWorkspaceButtonTapped)
                        } label: {
                            Label("Attach", systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                    }

                    ZStack {
                        ForEach(store.workspaces) { workspace in
                            if let workspaceSession = terminalRegistry.session(id: workspace.id) {
                                WorkspaceTerminalRepresentable(session: workspaceSession)
                                    .opacity(
                                        workspace.id == store.selectedWorkspaceID ? 1 : 0.001
                                    )
                                    .allowsHitTesting(
                                        workspace.id == store.selectedWorkspaceID
                                    )
                                    .zIndex(
                                        workspace.id == store.selectedWorkspaceID ? 1 : 0
                                    )
                            }
                        }
                    }
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
                ContentUnavailableView(
                    "No Workspace Selected",
                    systemImage: "rectangle.split.3x1",
                    description: Text("Open a project directory to start an attached terminal.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial, in: .rect(cornerRadius: 28))
            }
        }
    }

    private var workspaceInspector: some View {
        Group {
            if let workspace = selectedWorkspace {
                WorkspaceInspectorPanel(
                    workspace: workspace,
                    session: terminalRegistry.session(id: workspace.id),
                    isRemoving: store.removingWorkspaceIDs.contains(workspace.id),
                    onReveal: { store.send(.openInFinderButtonTapped(workspace.id)) },
                    onRestart: { store.send(.rebuildWorkspaceButtonTapped(workspace.id)) },
                    onRemove: { store.send(.removeWorkspaceButtonTapped(workspace.id)) }
                )
            } else {
                ContentUnavailableView(
                    "No Context",
                    systemImage: "sidebar.right",
                    description: Text("Select a workspace to inspect its project directory and terminal status.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial, in: .rect(cornerRadius: 24))
            }
        }
    }

    private var selectedWorkspace: CodingWorkspace? {
        guard let id = store.selectedWorkspaceID else { return nil }
        return store.workspaces[id: id]
    }

    private var defaultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Defaults")
                    .font(.headline)
                Spacer()
                Button {
                    store.send(.savePreferencesButtonTapped)
                } label: {
                    if store.isSavingPreferences {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(store.isSavingPreferences)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Project")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("/Users/you/project", text: $store.preferences.defaultRepositoryPath)
                    .textFieldStyle(.roundedBorder)

                Text("Agent")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("claude", text: $store.preferences.defaultAgentCommand)
                    .textFieldStyle(.roundedBorder)
            }

            Text("New workspaces start from these values.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }
}

@MainActor
private struct WorkspaceListRow: View {
    let workspace: CodingWorkspace
    let session: WorkspaceTerminalSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(workspace.name)
                    .font(.headline)
                Spacer()
                if let session {
                    StatusBadge(title: session.phase.label)
                }
            }

            Text(workspace.worktreePath)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(workspace.repositoryRootURL.lastPathComponent)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private struct WorkspaceInspectorPanel: View {
    let workspace: CodingWorkspace
    let session: WorkspaceTerminalSession?
    let isRemoving: Bool
    let onReveal: () -> Void
    let onRestart: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(workspace.name)
                        .font(.title3.weight(.semibold))
                    Text("This terminal stays anchored to the selected project directory.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                metadataCard
                terminalCard

                HStack(spacing: 10) {
                    Button(action: onReveal) {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button(action: onRestart) {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive, action: onRemove) {
                        Label(isRemoving ? "Removing" : "Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRemoving)
                }
            }
            .padding(18)
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repository")
                .font(.headline)

            InspectorValueRow(label: "Project", value: workspace.worktreePath)
            InspectorValueRow(label: "tmux", value: workspace.tmuxSessionName)
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }

    private var terminalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Terminal")
                .font(.headline)

            InspectorValueRow(label: "Status", value: session?.phase.label ?? "Not Ready")
            InspectorValueRow(label: "Title", value: session?.displayTitle ?? workspace.name)
            InspectorValueRow(label: "Command", value: workspace.agentCommand.ifEmpty(fallback: "Shell only"))
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }
}

@MainActor
private struct WorkspaceComposerSheet: View {
    @Bindable var store: StoreOf<WorkspaceFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New Workspace")
                    .font(.title2.weight(.semibold))
                Text("Open a project directory and keep its terminal agent attached.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Name")
                        .foregroundStyle(.secondary)
                    TextField("Optional display name", text: $store.composer.name)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Project")
                        .foregroundStyle(.secondary)
                    TextField("/Users/you/project", text: $store.composer.repositoryPath)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Agent")
                        .foregroundStyle(.secondary)
                    TextField("claude", text: $store.composer.agentCommand)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("Workspace name: \(store.composer.inferredName)")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    store.send(.createWorkspaceButtonTapped)
                } label: {
                    if store.isCreatingWorkspace {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Open Workspace")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!store.composer.canCreate || store.isCreatingWorkspace)
            }
        }
    }
}

@MainActor
private struct InspectorValueRow: View {
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
private struct StatusBadge: View {
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
