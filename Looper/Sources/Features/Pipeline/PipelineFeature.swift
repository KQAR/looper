import ComposableArchitecture
import Foundation

struct PipelineFailure: LocalizedError, Equatable, Sendable {
    let description: String

    var errorDescription: String? {
        description
    }
}

@Reducer
struct PipelineFeature {
    struct BootstrapPayload: Equatable, Sendable {
        var pipelines: [Pipeline]
        var preferences: AppPreferences
    }

    @ObservableState
    struct State: Equatable {
        var pipelines: IdentifiedArrayOf<Pipeline> = []
        var selectedPipelineID: Pipeline.ID?
        var preferences: AppPreferences = .init()
        var composer: PipelineDraft = .init()
        var isComposerPresented = false
        var isCreatingPipeline = false
        var isSavingPreferences = false
        var removingPipelineIDs: Set<Pipeline.ID> = []
        var errorMessage: String?
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case addPipelineButtonTapped
        case attachSelectedPipelineButtonTapped
        case bootstrapResponse(Result<BootstrapPayload, PipelineFailure>)
        case createPipelineFromDefaults(String)
        case createPipelineButtonTapped
        case createPipelineResponse(Result<Pipeline, PipelineFailure>)
        case dismissError
        case onAppear
        case openProjectButtonTapped
        case openProjectResponse(String?)
        case revealPipelineInFinderButtonTapped(Pipeline.ID)
        case selectNextPipeline
        case selectPreviousPipeline
        case rebuildPipelineButtonTapped(Pipeline.ID)
        case removePipelineButtonTapped(Pipeline.ID)
        case removePipelineResponse(Pipeline.ID, Result<Void, PipelineFailure>)
        case savePreferencesButtonTapped
        case savePreferencesFinished
        case selectPipeline(Pipeline.ID?)
        case pipelinePersistenceFailed(PipelineFailure)
    }

    @Dependency(\.projectDirectoryPickerClient) var projectDirectoryPickerClient
    @Dependency(\.pipelineManagerClient) var pipelineManagerClient
    @Dependency(\.appPreferencesClient) var appPreferencesClient
    @Dependency(\.pipelineTerminalClient) var pipelineTerminalClient
    @Dependency(\.pipelineStoreClient) var pipelineStoreClient

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                return .run { send in
                    do {
                        async let pipelines = pipelineStoreClient.fetchPipelines()
                        async let preferences = appPreferencesClient.fetchPreferences()
                        await send(
                            .bootstrapResponse(
                                .success(
                                    BootstrapPayload(
                                        pipelines: try await pipelines,
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

            case .addPipelineButtonTapped:
                state.composer = state.preferences.draft
                state.isComposerPresented = true
                return .none

            case .openProjectButtonTapped:
                guard !state.isCreatingPipeline else { return .none }
                return .run { send in
                    await send(.openProjectResponse(await projectDirectoryPickerClient.pickDirectory()))
                }

            case let .openProjectResponse(path):
                guard let path else { return .none }
                return .send(.createPipelineFromDefaults(path))

            case let .createPipelineFromDefaults(path):
                guard !state.isCreatingPipeline else { return .none }
                state.composer = PipelineDraft(
                    name: "",
                    projectPath: path,
                    agentCommand: state.preferences.defaultAgentCommand
                )

                let request = CreatePipelineRequest(draft: state.composer)
                state.isCreatingPipeline = true

                return .run { send in
                    do {
                        let pipeline = try await pipelineManagerClient.createPipeline(request)
                        await send(.createPipelineResponse(.success(pipeline)))
                    } catch {
                        await send(
                            .createPipelineResponse(
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case .createPipelineButtonTapped:
                guard state.composer.canCreate, !state.isCreatingPipeline else {
                    return .none
                }

                let request = CreatePipelineRequest(draft: state.composer)
                state.isCreatingPipeline = true

                return .run { send in
                    do {
                        let pipeline = try await pipelineManagerClient.createPipeline(request)
                        await send(.createPipelineResponse(.success(pipeline)))
                    } catch {
                        await send(
                            .createPipelineResponse(
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case let .createPipelineResponse(.success(pipeline)):
                state.isCreatingPipeline = false
                state.isComposerPresented = false
                state.pipelines.append(pipeline)
                state.selectedPipelineID = pipeline.id
                state.preferences = .from(
                    pipeline: pipeline,
                    selectedPipelineID: pipeline.id,
                    base: state.preferences
                )
                let preferences = state.preferences

                return .run { send in
                    do {
                        try await pipelineStoreClient.savePipeline(pipeline)
                        await appPreferencesClient.savePreferences(
                            preferences
                        )
                        await pipelineTerminalClient.upsertSession(pipeline)
                        await pipelineTerminalClient.focusSession(pipeline.id)
                        await pipelineTerminalClient.bootstrapSession(pipeline.id)
                    } catch {
                        await send(
                            .pipelinePersistenceFailed(
                                .init(description: error.localizedDescription)
                            )
                        )
                    }
                }

            case let .createPipelineResponse(.failure(message)):
                state.isCreatingPipeline = false
                state.errorMessage = message.description
                return .none

            case .dismissError:
                state.errorMessage = nil
                return .none

            case let .bootstrapResponse(.success(payload)):
                state.pipelines = IdentifiedArray(uniqueElements: payload.pipelines)
                state.preferences = payload.preferences
                state.composer = payload.preferences.draft
                state.selectedPipelineID = selectedPipelineID(
                    preferredID: payload.preferences.lastSelectedPipelineID,
                    availableIDs: Array(state.pipelines.ids)
                )

                return .run { _ in
                    for pipeline in payload.pipelines {
                        await pipelineTerminalClient.upsertSession(pipeline)
                    }
                }

            case let .bootstrapResponse(.failure(message)):
                state.errorMessage = message.description
                return .none

            case let .selectPipeline(id):
                state.selectedPipelineID = id
                state.preferences.lastSelectedPipelineID = id
                let preferences = state.preferences

                return .run { _ in
                    await appPreferencesClient.savePreferences(preferences)

                    guard let id else { return }
                    await pipelineTerminalClient.focusSession(id)
                }

            case .selectPreviousPipeline:
                guard let previousID = adjacentPipelineID(
                    from: state.selectedPipelineID,
                    within: Array(state.pipelines.ids),
                    direction: -1
                ) else { return .none }
                return .send(.selectPipeline(previousID))

            case .selectNextPipeline:
                guard let nextID = adjacentPipelineID(
                    from: state.selectedPipelineID,
                    within: Array(state.pipelines.ids),
                    direction: 1
                ) else { return .none }
                return .send(.selectPipeline(nextID))

            case .savePreferencesButtonTapped:
                guard !state.isSavingPreferences else { return .none }
                state.isSavingPreferences = true
                let preferences = state.preferences

                return .run { send in
                    await appPreferencesClient.savePreferences(preferences)
                    await send(.savePreferencesFinished)
                }

            case .savePreferencesFinished:
                state.isSavingPreferences = false
                return .none

            case .attachSelectedPipelineButtonTapped:
                guard let id = state.selectedPipelineID else { return .none }
                return .run { _ in
                    await pipelineTerminalClient.focusSession(id)
                    await pipelineTerminalClient.bootstrapSession(id)
                }

            case let .revealPipelineInFinderButtonTapped(id):
                guard let pipeline = state.pipelines[id: id] else { return .none }
                return .run { _ in
                    await pipelineManagerClient.revealInFinder(pipeline.executionPath)
                }

            case let .rebuildPipelineButtonTapped(id):
                guard let pipeline = state.pipelines[id: id] else { return .none }
                return .run { _ in
                    await pipelineTerminalClient.rebuildSession(pipeline)
                    await pipelineTerminalClient.focusSession(id)
                    await pipelineTerminalClient.bootstrapSession(id)
                }

            case let .removePipelineButtonTapped(id):
                guard let pipeline = state.pipelines[id: id] else { return .none }
                guard !state.removingPipelineIDs.contains(id) else { return .none }
                state.removingPipelineIDs.insert(id)

                return .run { send in
                    await pipelineTerminalClient.removeSession(id)

                    do {
                        try await pipelineManagerClient.removePipeline(pipeline)
                        try await pipelineStoreClient.deletePipeline(id)
                        await send(.removePipelineResponse(id, .success(())))
                    } catch {
                        await send(
                            .removePipelineResponse(
                                id,
                                .failure(.init(description: error.localizedDescription))
                            )
                        )
                    }
                }

            case let .removePipelineResponse(id, .success):
                state.removingPipelineIDs.remove(id)
                state.pipelines.remove(id: id)

                if state.selectedPipelineID == id {
                    state.selectedPipelineID = state.pipelines.ids.first
                }
                state.preferences.lastSelectedPipelineID = state.selectedPipelineID

                return .run { [preferences = state.preferences] _ in
                    await appPreferencesClient.savePreferences(preferences)
                }

            case let .removePipelineResponse(id, .failure(message)):
                state.removingPipelineIDs.remove(id)
                state.errorMessage = message.description
                return .none

            case let .pipelinePersistenceFailed(message):
                state.errorMessage = message.description
                return .none
            }
        }
    }
}

private func selectedPipelineID(
    preferredID: UUID?,
    availableIDs: [UUID]
) -> UUID? {
    if let preferredID, availableIDs.contains(preferredID) {
        return preferredID
    }

    return availableIDs.first
}

private func adjacentPipelineID(
    from currentID: UUID?,
    within ids: [UUID],
    direction: Int
) -> UUID? {
    guard !ids.isEmpty else { return nil }

    guard let currentID, let currentIndex = ids.firstIndex(of: currentID) else {
        return ids.first
    }

    let nextIndex = (currentIndex + direction + ids.count) % ids.count
    return ids[nextIndex]
}
