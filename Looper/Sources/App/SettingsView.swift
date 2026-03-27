import ComposableArchitecture
import SwiftUI

@MainActor
struct SettingsView: View {
    private let settingsCornerRadius: CGFloat = 32

    @Bindable var store: StoreOf<AppFeature>
    @State private var selectedSection: SettingsSection? = .general
    @Namespace private var sidebarSelectionAnimation

    var body: some View {
        NavigationSplitView {
            settingsSidebar
                .navigationSplitViewColumnWidth(min: 156, ideal: 168, max: 180)
        } detail: {
            detailView(for: selectedSection ?? .general)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
        }
        .background(settingsBackground)
        .clipShape(.rect(cornerRadius: settingsCornerRadius))
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SettingsSection.allCases) { section in
                sidebarButton(for: section)
            }

            Spacer(minLength: 0)

            checkForUpdatesButton
        }
        .padding(.top, settingsCornerRadius)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.04))
    }

    private func sidebarButton(for section: SettingsSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 22)

                Text(section.title)
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background {
                if isSelected {
                    Rectangle()
                        .fill(Color.gray.opacity(0.24))
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.55))
                                .frame(width: 2)
                        }
                        .matchedGeometryEffect(
                            id: "settings-sidebar-selection",
                            in: sidebarSelectionAnimation
                        )
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var checkForUpdatesButton: some View {
        Button {} label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)

                Text("Check for Updates")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Check for Updates")
    }

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.largeTitle.weight(.bold))
                    Text(section.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

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

            switch section {
            case .general:
                generalSection
            case .about:
                aboutSection
            }

            Spacer()
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("General settings will be redesigned here.")
                .font(.body.weight(.medium))

            Text("This section is reserved for future app-level preferences and behavior controls.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Looper")
                .font(.title2.weight(.semibold))

            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
            LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "com.jarvis.looper")
        }
        .foregroundStyle(.primary)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.1"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "1"
    }

    private var settingsBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .about:
            return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Application behavior and defaults."
        case .about:
            return "Version information and app metadata."
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .about:
            return "info.circle"
        }
    }
}
