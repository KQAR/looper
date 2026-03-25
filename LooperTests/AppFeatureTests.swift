import ComposableArchitecture
import Testing

@testable import Looper

@MainActor
@Suite
struct AppFeatureTests {
    @Test
    func onAppear() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.onAppear)
    }
}
