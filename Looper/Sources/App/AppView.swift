import ComposableArchitecture
import SwiftUI

@MainActor
struct AppView: View {
    let store: StoreOf<AppFeature>
    let terminalRegistry: WorkspaceTerminalRegistry

    var body: some View {
        WorkspaceView(
            store: store.scope(state: \.workspace, action: \.workspace),
            terminalRegistry: terminalRegistry
        )
    }
}
