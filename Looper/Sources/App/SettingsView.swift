import ComposableArchitecture
import Sparkle
import SwiftUI

@MainActor
struct SettingsView: View {
    private let settingsCornerRadius: CGFloat = 32

    @Bindable var store: StoreOf<AppFeature>
    @State private var selectedSection: SettingsSection? = .general
    @Namespace private var sidebarSelectionAnimation
    @Environment(\.updater) private var updater
    private let lang = AppLanguageManager.shared

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

                Text(section.titleKey, bundle: lang.bundle)
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
        Button {
            updater?.checkForUpdates()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 11, weight: .medium))

                Text("settings.checkForUpdates", bundle: lang.bundle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(updater?.canCheckForUpdates != true)
        .help(Text("settings.checkForUpdates", bundle: lang.bundle))
    }

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.titleKey, bundle: lang.bundle)
                        .font(.largeTitle.weight(.bold))
                    Text(section.subtitleKey, bundle: lang.bundle)
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
                .accessibilityLabel(Text("settings.closeSettings", bundle: lang.bundle))
                .glassEffect(.regular.interactive(), in: .circle)
            }

            switch section {
            case .general:
                generalSection
            case .taskProvider:
                taskProviderSection
            case .about:
                aboutSection
            }

            Spacer()
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            languagePicker

            Divider()

            LabeledContent {
                TextField(
                    "",
                    text: $store.pipeline.preferences.defaultAgentCommand,
                    prompt: Text(verbatim: "claude")
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.general.agentCommand", bundle: lang.bundle)
                    Text("settings.general.agentCommandDetail", bundle: lang.bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            LabeledContent {
                Picker(
                    selection: $store.pipeline.preferences.postRunGitAction
                ) {
                    ForEach(PostRunGitAction.allCases) { action in
                        Text(action.localizedLabel(bundle: lang.bundle)).tag(action)
                    }
                } label: {
                    EmptyView()
                }
                .frame(width: 280)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.general.postRunGitAction", bundle: lang.bundle)
                    Text("settings.general.postRunGitActionDetail", bundle: lang.bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Task Provider

    private var taskProviderSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            providerPicker

            Divider()

            switch store.pipeline.preferences.taskProviderConfiguration.kind {
            case .local:
                localProviderInfo
            case .feishu:
                feishuConfigForm
            }
        }
    }

    private var providerPicker: some View {
        LabeledContent {
            Picker(
                selection: Binding(
                    get: { store.pipeline.preferences.taskProviderConfiguration.kind },
                    set: { store.send(.selectTaskProvider($0)) }
                )
            ) {
                ForEach(TaskProviderKind.allCases, id: \.self) { kind in
                    Text(kind.localizedLabel(bundle: lang.bundle)).tag(kind)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        } label: {
            Text("settings.taskProvider.source", bundle: lang.bundle)
        }
    }

    private var localProviderInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("settings.taskProvider.local.description", bundle: lang.bundle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Feishu Config

    private var feishuConfigForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            feishuConnectionFields
            Divider()
            feishuFieldMappingSection
            Divider()
            feishuStatusMappingSection
            Divider()
            feishuActions
        }
    }

    private var feishuConnectionFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.feishu.connection", bundle: lang.bundle)
                .font(.headline)

            settingsTextField(
                label: "settings.feishu.appID",
                text: $store.pipeline.preferences.feishuProviderConfiguration.appID,
                placeholder: "cli_xxxx"
            )
            settingsSecureField(
                label: "settings.feishu.appSecret",
                text: $store.pipeline.preferences.feishuProviderConfiguration.appSecret,
                placeholder: "••••••••"
            )
            settingsTextField(
                label: "settings.feishu.appToken",
                text: $store.pipeline.preferences.feishuProviderConfiguration.appToken,
                placeholder: "appXXXX"
            )
            settingsTextField(
                label: "settings.feishu.tableID",
                text: $store.pipeline.preferences.feishuProviderConfiguration.tableID,
                placeholder: "tblXXXX"
            )
        }
    }

    private var feishuFieldMappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.feishu.fieldMapping", bundle: lang.bundle)
                .font(.headline)

            Text("settings.feishu.fieldMapping.detail", bundle: lang.bundle)
                .font(.caption)
                .foregroundStyle(.secondary)

            settingsTextField(
                label: "settings.feishu.field.title",
                text: $store.pipeline.preferences.feishuProviderConfiguration.titleFieldName,
                placeholder: "Title"
            )
            settingsTextField(
                label: "settings.feishu.field.summary",
                text: $store.pipeline.preferences.feishuProviderConfiguration.summaryFieldName,
                placeholder: "Summary"
            )
            settingsTextField(
                label: "settings.feishu.field.status",
                text: $store.pipeline.preferences.feishuProviderConfiguration.statusFieldName,
                placeholder: "Status"
            )
            settingsTextField(
                label: "settings.feishu.field.repoPath",
                text: $store.pipeline.preferences.feishuProviderConfiguration.repoPathFieldName,
                placeholder: "Repository"
            )
        }
    }

    private var feishuStatusMappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.feishu.statusMapping", bundle: lang.bundle)
                .font(.headline)

            Text("settings.feishu.statusMapping.detail", bundle: lang.bundle)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsTextField(
                        label: "status.todo",
                        text: $store.pipeline.preferences.feishuProviderConfiguration.todoStatusValue,
                        placeholder: "todo"
                    )
                    settingsTextField(
                        label: "status.inProgress",
                        text: $store.pipeline.preferences.feishuProviderConfiguration.inProgressStatusValue,
                        placeholder: "in_progress"
                    )
                }
                VStack(alignment: .leading, spacing: 8) {
                    settingsTextField(
                        label: "status.inReview",
                        text: $store.pipeline.preferences.feishuProviderConfiguration.inReviewStatusValue,
                        placeholder: "in_review"
                    )
                    settingsTextField(
                        label: "status.done",
                        text: $store.pipeline.preferences.feishuProviderConfiguration.doneStatusValue,
                        placeholder: "done"
                    )
                }
            }
        }
    }

    private var feishuActions: some View {
        HStack(spacing: 12) {
            Button {
                store.send(.inspectTaskProviderButtonTapped)
            } label: {
                if store.isInspectingTaskProvider {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("settings.feishu.inspect", systemImage: "magnifyingglass")
                }
            }
            .disabled(store.isInspectingTaskProvider)

            Button {
                store.send(.saveSettingsButtonTapped)
            } label: {
                if store.isSavingSettings {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("settings.feishu.save", systemImage: "checkmark.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isSavingSettings)

            Spacer()

            if let inspection = store.taskProviderInspection {
                inspectionBadge(inspection)
            }
        }
    }

    @ViewBuilder
    private func inspectionBadge(_ inspection: TaskProviderInspection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("settings.feishu.inspectResult \(inspection.previewTaskCount) \(inspection.discoveredFieldNames.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Field Helpers

    private func settingsTextField(
        label: LocalizedStringKey,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        LabeledContent {
            TextField("", text: text, prompt: Text(verbatim: placeholder))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        } label: {
            Text(label, bundle: lang.bundle)
                .frame(width: 100, alignment: .trailing)
        }
    }

    private func settingsSecureField(
        label: LocalizedStringKey,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        LabeledContent {
            SecureField("", text: text, prompt: Text(verbatim: placeholder))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        } label: {
            Text(label, bundle: lang.bundle)
                .frame(width: 100, alignment: .trailing)
        }
    }

    private var languagePicker: some View {
        LabeledContent {
            Picker(selection: Binding(
                get: { lang.selected },
                set: { lang.selected = $0 }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName(bundle: lang.bundle)).tag(language)
                }
            } label: {
                EmptyView()
            }
            .frame(width: 200)
        } label: {
            Text("settings.language", bundle: lang.bundle)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Looper")
                .font(.title2.weight(.semibold))

            LabeledContent {
                Text(appVersion)
            } label: {
                Text("settings.version", bundle: lang.bundle)
            }
            LabeledContent {
                Text(appBuild)
            } label: {
                Text("settings.build", bundle: lang.bundle)
            }
            LabeledContent(
                String(localized: "settings.bundleID", bundle: lang.bundle),
                value: Bundle.main.bundleIdentifier ?? "com.jarvis.looper"
            )
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
    case taskProvider
    case about

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .general: "settings.general"
        case .taskProvider: "settings.taskProvider"
        case .about: "settings.about"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .general: "settings.general.subtitle"
        case .taskProvider: "settings.taskProvider.subtitle"
        case .about: "settings.about.subtitle"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .taskProvider: "tray.and.arrow.down"
        case .about: "info.circle"
        }
    }
}
