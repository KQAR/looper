import ComposableArchitecture
import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("Settings")
                    .font(.largeTitle.weight(.bold))

                Spacer()

                Button {
                    store.send(.dismissSettingsButtonTapped)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Settings")
                .glassEffect(.regular.interactive(), in: .circle)
            }

            Text("Cleared for redesign.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    }
}
