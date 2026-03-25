import ComposableArchitecture

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var workspace = WorkspaceFeature.State()
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.workspace, action: \.workspace) {
            WorkspaceFeature()
        }
    }

    enum Action {
        case workspace(WorkspaceFeature.Action)
    }
}
