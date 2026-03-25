import ComposableArchitecture
import Foundation

struct WorkspaceFailure: LocalizedError, Equatable, Sendable {
    let description: String

    var errorDescription: String? {
        description
    }
}

@Reducer
struct WorkspaceFeature {
    struct BootstrapPayload: Equatable, Sendable {
        var workspaces: [CodingWorkspace]
        var preferences: WorkspacePreferences
    }

    @ObservableState
    struct State: Equatable {
        var workspaces: IdentifiedArrayOf<CodingWorkspace> = []
        var selectedWorkspaceID: CodingWorkspace.ID?
        var preferences: WorkspacePreferences = .init()
        var composer: WorkspaceDraft = .init()
        var isComposerPresented = false
        var isCreatingWorkspace = false
        var removingWorkspaceIDs: Set<CodingWorkspace.ID> = []
        var errorMessage: String?
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case addWorkspaceButtonTapped
        case attachSelectedWorkspaceButtonTapped
        case bootstrapResponse(Result<BootstrapPayload, WorkspaceFailure>)
        case createWorkspaceButtonTapped
        case createWorkspaceResponse(Result<CodingWorkspace, WorkspaceFailure>)
        case dismissError
        case onAppear
        case openInFinderButtonTapped(CodingWorkspace.ID)
        case rebuildWorkspaceButtonTapped(CodingWorkspace.ID)
        case removeWorkspaceButtonTapped(CodingWorkspace.ID)
        case removeWorkspaceResponse(CodingWorkspace.ID, Result<Void, WorkspaceFailure>)
        case selectWorkspace(CodingWorkspace.ID?)
        case workspacePersistenceFailed(WorkspaceFailure)
    }

    @Dependency(\.repoManagerClient) var repoManagerClient
    @Dependency(\.workspacePreferencesClient) var workspacePreferencesClient
    @Dependency(\.terminalWorkspaceClient) var terminalWorkspaceClient
    @Dependency(\.workspaceStoreClient) var workspaceStoreClient

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                return .run { send in
                    do {
                        async let workspaces = workspaceStoreClient.fetchWorkspaces()
                        async let preferences = workspacePreferencesClient.fetchPreferences()
                        await send(
                            .bootstrapResponse(
                                .success(
                                    BootstrapPayload(
                                        workspaces: try await workspaces,
                                        preferences: await preferences
                                    )
                                )
                            )
                        )
                    } catch {
                        await send(
                            .bootstrapResponse(
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case .addWorkspaceButtonTapped:
                state.composer = state.preferences.draft
                state.isComposerPresented = true
                return .none

            case .createWorkspaceButtonTapped:
                guard state.composer.canCreate, !state.isCreatingWorkspace else {
                    return .none
                }

                let request = CreateWorkspaceRequest(draft: state.composer)
                state.isCreatingWorkspace = true

                return .run { send in
                    do {
                        let workspace = try await repoManagerClient.createWorkspace(request)
                        await send(.createWorkspaceResponse(.success(workspace)))
                    } catch {
                        await send(
                            .createWorkspaceResponse(
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case let .createWorkspaceResponse(.success(workspace)):
                state.isCreatingWorkspace = false
                state.isComposerPresented = false
                state.workspaces.append(workspace)
                state.selectedWorkspaceID = workspace.id
                state.preferences = .from(
                    workspace: workspace,
                    selectedWorkspaceID: workspace.id
                )

                return .run { send in
                    do {
                        try await workspaceStoreClient.saveWorkspace(workspace)
                        await workspacePreferencesClient.savePreferences(
                            .from(workspace: workspace, selectedWorkspaceID: workspace.id)
                        )
                        await terminalWorkspaceClient.upsertSession(workspace)
                        await terminalWorkspaceClient.focusSession(workspace.id)
                        await terminalWorkspaceClient.bootstrapSession(workspace.id)
                    } catch {
                        await send(
                            .workspacePersistenceFailed(
                                .init(description: error.localizedDescription)
                            )
                        )
                    }
                }

            case let .createWorkspaceResponse(.failure(message)):
                state.isCreatingWorkspace = false
                state.errorMessage = message.description
                return .none

            case .dismissError:
                state.errorMessage = nil
                return .none

            case let .bootstrapResponse(.success(payload)):
                state.workspaces = IdentifiedArray(uniqueElements: payload.workspaces)
                state.preferences = payload.preferences
                state.composer = payload.preferences.draft
                state.selectedWorkspaceID = selectedWorkspaceID(
                    preferredID: payload.preferences.lastSelectedWorkspaceID,
                    availableIDs: Array(state.workspaces.ids)
                )

                return .run { _ in
                    for workspace in payload.workspaces {
                        await terminalWorkspaceClient.upsertSession(workspace)
                    }
                }

            case let .bootstrapResponse(.failure(message)):
                state.errorMessage = message.description
                return .none

            case let .selectWorkspace(id):
                state.selectedWorkspaceID = id
                state.preferences.lastSelectedWorkspaceID = id
                let preferences = state.preferences

                return .run { _ in
                    await workspacePreferencesClient.savePreferences(preferences)

                    guard let id else { return }
                    await terminalWorkspaceClient.focusSession(id)
                }

            case .attachSelectedWorkspaceButtonTapped:
                guard let id = state.selectedWorkspaceID else { return .none }
                return .run { _ in
                    await terminalWorkspaceClient.focusSession(id)
                    await terminalWorkspaceClient.bootstrapSession(id)
                }

            case let .openInFinderButtonTapped(id):
                guard let workspace = state.workspaces[id: id] else { return .none }
                return .run { _ in
                    await repoManagerClient.revealInFinder(workspace.worktreePath)
                }

            case let .rebuildWorkspaceButtonTapped(id):
                guard let workspace = state.workspaces[id: id] else { return .none }
                return .run { _ in
                    await terminalWorkspaceClient.rebuildSession(workspace)
                    await terminalWorkspaceClient.focusSession(id)
                    await terminalWorkspaceClient.bootstrapSession(id)
                }

            case let .removeWorkspaceButtonTapped(id):
                guard let workspace = state.workspaces[id: id] else { return .none }
                guard !state.removingWorkspaceIDs.contains(id) else { return .none }
                state.removingWorkspaceIDs.insert(id)

                return .run { send in
                    await terminalWorkspaceClient.removeSession(id)

                    do {
                        try await repoManagerClient.removeWorkspace(workspace)
                        try await workspaceStoreClient.deleteWorkspace(id)
                        await send(.removeWorkspaceResponse(id, .success(())))
                    } catch {
                        await send(
                            .removeWorkspaceResponse(
                                id,
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case let .removeWorkspaceResponse(id, .success):
                state.removingWorkspaceIDs.remove(id)
                state.workspaces.remove(id: id)

                if state.selectedWorkspaceID == id {
                    state.selectedWorkspaceID = state.workspaces.ids.first
                }
                state.preferences.lastSelectedWorkspaceID = state.selectedWorkspaceID

                return .run { [preferences = state.preferences] _ in
                    await workspacePreferencesClient.savePreferences(preferences)
                }

            case let .removeWorkspaceResponse(id, .failure(message)):
                state.removingWorkspaceIDs.remove(id)
                state.errorMessage = message.description
                return .none

            case let .workspacePersistenceFailed(message):
                state.errorMessage = message.description
                return .none
            }
        }
    }
}

private func selectedWorkspaceID(
    preferredID: UUID?,
    availableIDs: [UUID]
) -> UUID? {
    if let preferredID, availableIDs.contains(preferredID) {
        return preferredID
    }

    return availableIDs.first
}
