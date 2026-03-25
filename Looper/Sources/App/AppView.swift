import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationSplitView {
            List {
                Text("Tasks")
            }
            .navigationTitle("Looper")
        } detail: {
            Text("Select a task")
                .foregroundStyle(.secondary)
        }
        .onAppear {
            store.send(.onAppear)
        }
    }
}
