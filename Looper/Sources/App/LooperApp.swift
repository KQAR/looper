import ComposableArchitecture
import Sparkle
import SwiftUI

@MainActor
@main
struct LooperApp: App {
    @State private var store: StoreOf<AppFeature>
    @State private var terminalRegistry = PipelineTerminalRegistry.shared
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        let database = AppDatabase.makeLive()
        _store = State(
            initialValue: Store(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.pipelineStoreClient = .live(database: database)
                $0.runStoreClient = .live(database: database)
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            AppView(
                store: store,
                terminalRegistry: terminalRegistry
            )
            .frame(minWidth: 1240, minHeight: 760)
            .environment(\.updater, updaterController.updater)
        }
        .defaultSize(width: 1480, height: 920)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowStyle(.hiddenTitleBar)
    }
}
