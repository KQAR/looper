import ComposableArchitecture
import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    taskProviderSection

                    if selectedProviderKind == .feishu {
                        feishuConfigurationSection
                    } else {
                        localProviderSection
                    }

                    if let inspection = store.taskProviderInspection {
                        inspectionSection(inspection)
                    }

                    defaultsSection
                    environmentSection
                }
                .padding(.vertical, 4)
            }

            footer
        }
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.largeTitle.weight(.bold))
                Text("Configure task source, local defaults, and environment checks.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Close") {
                store.send(.dismissSettingsButtonTapped)
            }
            .buttonStyle(.bordered)
        }
    }

    private var taskProviderSection: some View {
        settingsCard {
            Text("Task Provider")
                .font(.headline)

            Text("Looper uses one task model. Settings here only decide where tasks come from and where status updates are written back.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Task Provider", selection: taskProviderKindBinding) {
                ForEach(TaskProviderKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(TaskProviderKind.allCases, id: \.self) { kind in
                    providerOptionCard(kind)
                }
            }
        }
    }

    private var feishuConfigurationSection: some View {
        Group {
            settingsCard {
                Text("Feishu Connection")
                    .font(.headline)

                labeledField("App ID") {
                    TextField("cli_xxx", text: feishuAppIDBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("App Secret") {
                    SecureField("xxx", text: feishuAppSecretBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Bitable App Token") {
                    TextField("bascn_xxx", text: feishuAppTokenBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Table ID") {
                    TextField("tblxxx", text: feishuTableIDBinding)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    store.send(.inspectTaskProviderButtonTapped)
                } label: {
                    if store.isInspectingTaskProvider {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Test Connection", systemImage: "bolt.horizontal.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isInspectingTaskProvider)
            }

            settingsCard {
                Text("Field Mapping")
                    .font(.headline)

                Text("Field names must match the table exactly. A successful connection test can auto-fill matching fields.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                labeledField("Title Field") {
                    TextField("Title", text: feishuTitleFieldBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Summary Field") {
                    TextField("Summary", text: feishuSummaryFieldBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Status Field") {
                    TextField("Status", text: feishuStatusFieldBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Repository Field") {
                    TextField("Repository", text: feishuProjectFieldBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            settingsCard {
                Text("Status Mapping")
                    .font(.headline)

                labeledField("Pending Value") {
                    TextField("pending", text: feishuPendingValueBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Running Value") {
                    TextField("developing", text: feishuDevelopingValueBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Done Value") {
                    TextField("done", text: feishuDoneValueBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Failed Value") {
                    TextField("failed", text: feishuFailedValueBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var localProviderSection: some View {
        settingsCard {
            Text("Local Tasks")
                .font(.headline)

            Text("Local Tasks keeps the inbox entirely on this Mac. Tasks persist locally and status updates never leave the machine.")
                .foregroundStyle(.secondary)

            settingsBullet(
                title: "No external credentials",
                detail: "Useful for private queues, offline work, and single-machine flows."
            )
            settingsBullet(
                title: "Fastest path to usage",
                detail: "Create a pipeline, add a local task, and launch work without any third-party service."
            )

            Button {
                store.send(.inspectTaskProviderButtonTapped)
            } label: {
                if store.isInspectingTaskProvider {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Inspect Local Tasks", systemImage: "tray.full")
                }
            }
            .buttonStyle(.bordered)
            .disabled(store.isInspectingTaskProvider)
        }
    }

    private func inspectionSection(_ inspection: TaskProviderInspection) -> some View {
        settingsCard {
            Text(selectedProviderKind == .feishu ? "Connection Result" : "Local Provider Snapshot")
                .font(.headline)

            Text(providerInspectionSummary(inspection))
                .foregroundStyle(.secondary)

            if !inspection.discoveredFieldNames.isEmpty {
                chipGroup(title: "Detected Fields", values: inspection.discoveredFieldNames)
            }

            if !inspection.detectedStatusValues.isEmpty {
                chipGroup(title: "Observed Status Values", values: inspection.detectedStatusValues)
            }

            if !inspection.sampleTaskTitles.isEmpty {
                chipGroup(title: "Sample Tasks", values: inspection.sampleTaskTitles)
            }
        }
    }

    private var defaultsSection: some View {
        settingsCard {
            Text("Execution Defaults")
                .font(.headline)

            labeledField("Default Project Path") {
                TextField("/Users/you/project", text: defaultProjectPathBinding)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField("Default Agent Command") {
                TextField("claude", text: defaultAgentCommandBinding)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var environmentSection: some View {
        settingsCard {
            HStack {
                Text("Environment Check")
                    .font(.headline)
                Spacer()
                Button {
                    store.send(.runEnvironmentCheckButtonTapped)
                } label: {
                    if store.isCheckingEnvironment {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Check Environment", systemImage: "checklist")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isCheckingEnvironment)
            }

            Text("Git and Claude CLI should be installed. tmux is optional, but recommended for stable terminal re-attach behavior.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let report = store.environmentReport {
                toolStatusRow(report.git)
                toolStatusRow(report.claude)
                toolStatusRow(report.tmux)
            } else {
                Text("Run the environment check to verify the machine before starting work.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Close") {
                store.send(.dismissSettingsButtonTapped)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                store.send(.saveSettingsButtonTapped)
            } label: {
                if store.isSavingSettings || store.pipeline.isSavingPreferences {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Save Settings")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isSavingSettings || store.pipeline.isSavingPreferences)
        }
    }

    private var selectedProviderKind: TaskProviderKind {
        store.pipeline.preferences.taskProviderConfiguration.kind
    }

    private func providerInspectionSummary(_ inspection: TaskProviderInspection) -> String {
        switch selectedProviderKind {
        case .local:
            return "Previewed \(inspection.previewTaskCount) locally persisted tasks."
        case .feishu:
            return "Previewed \(inspection.previewTaskCount) records from the selected Feishu table."
        }
    }

    @ViewBuilder
    private func providerOptionCard(_ kind: TaskProviderKind) -> some View {
        let isSelected = selectedProviderKind == kind

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kind.label)
                    .font(.body.weight(.semibold))
                Spacer()
                AppStatusBadge(title: isSelected ? "Selected" : "Available")
            }

            Text(kind.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(18)
            .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func settingsBullet(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chipGroup(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            FlowLayout(values: values)
        }
    }

    private func toolStatusRow(_ tool: EnvironmentToolStatus) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name)
                    .font(.body.weight(.semibold))
                Text(tool.detail)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            AppStatusBadge(title: tool.label)
        }
        .padding(.vertical, 2)
    }

    private var taskProviderKindBinding: Binding<TaskProviderKind> {
        Binding(
            get: { store.pipeline.preferences.taskProviderConfiguration.kind },
            set: { store.send(.selectTaskProvider($0)) }
        )
    }

    private var defaultProjectPathBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.defaultProjectPath },
            set: { store.send(.pipeline(.binding(.set(\.preferences.defaultProjectPath, $0)))) }
        )
    }

    private var defaultAgentCommandBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.defaultAgentCommand },
            set: { store.send(.pipeline(.binding(.set(\.preferences.defaultAgentCommand, $0)))) }
        )
    }

    private var feishuAppIDBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.appID },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.appID, $0)))) }
        )
    }

    private var feishuAppSecretBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.appSecret },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.appSecret, $0)))) }
        )
    }

    private var feishuAppTokenBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.appToken },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.appToken, $0)))) }
        )
    }

    private var feishuTableIDBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.tableID },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.tableID, $0)))) }
        )
    }

    private var feishuTitleFieldBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.titleFieldName },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.titleFieldName, $0)))) }
        )
    }

    private var feishuSummaryFieldBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.summaryFieldName },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.summaryFieldName, $0)))) }
        )
    }

    private var feishuStatusFieldBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.statusFieldName },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.statusFieldName, $0)))) }
        )
    }

    private var feishuProjectFieldBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.repoPathFieldName },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.repoPathFieldName, $0)))) }
        )
    }

    private var feishuPendingValueBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.pendingStatusValue },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.pendingStatusValue, $0)))) }
        )
    }

    private var feishuDevelopingValueBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.developingStatusValue },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.developingStatusValue, $0)))) }
        )
    }

    private var feishuDoneValueBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.doneStatusValue },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.doneStatusValue, $0)))) }
        )
    }

    private var feishuFailedValueBinding: Binding<String> {
        Binding(
            get: { store.pipeline.preferences.feishuProviderConfiguration.failedStatusValue },
            set: { store.send(.pipeline(.binding(.set(\.preferences.feishuProviderConfiguration.failedStatusValue, $0)))) }
        )
    }
}

@MainActor
private struct FlowLayout: View {
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunk(values, size: 3), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { value in
                        Text(value)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunk(_ values: [String], size: Int) -> [[String]] {
        stride(from: 0, to: values.count, by: size).map {
            Array(values[$0 ..< Swift.min($0 + size, values.count)])
        }
    }
}
