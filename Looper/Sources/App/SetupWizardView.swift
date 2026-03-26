import ComposableArchitecture
import SwiftUI

@MainActor
struct SetupWizardView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    progressStrip
                    stepBody
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
                Text(store.setupStep.title)
                    .font(.largeTitle.weight(.bold))
                Text(stepSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Close") {
                store.send(.dismissSetupWizardButtonTapped)
            }
            .buttonStyle(.bordered)
        }
    }

    private var progressStrip: some View {
        HStack(spacing: 10) {
            ForEach(AppFeature.SetupStep.allCases, id: \.rawValue) { step in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(step.title)
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        AppStatusBadge(title: stepBadgeTitle(step))
                    }

                    Capsule()
                        .fill(step.rawValue <= store.setupStep.rawValue ? Color.accentColor : Color.primary.opacity(0.08))
                        .frame(height: 6)
                }
            }
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch store.setupStep {
        case .welcome:
            welcomeStep
        case .taskSource:
            taskSourceStep
        case .environment:
            environmentStep
        case .finish:
            finishStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupCard {
                Text("Looper turns a task into a live local execution context.")
                    .font(.title3.weight(.semibold))

                Text("Pick a task source, verify that Claude can run locally, and come back to the inbox ready to start work.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    welcomeBullet(
                        title: "Choose a task provider",
                        detail: "Start with Local Tasks for an offline workflow, or connect one Feishu Bitable table."
                    )
                    welcomeBullet(
                        title: "Verify Git and Claude CLI",
                        detail: "Looper checks the local environment before it launches any task."
                    )
                    welcomeBullet(
                        title: "Run the first task end-to-end",
                        detail: "Once setup is complete, refresh the inbox and launch the first execution terminal."
                    )
                }
            }
        }
    }

    private var taskSourceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupCard {
                Text("Task Provider")
                    .font(.headline)

                Text("The rest of the app uses one unified task model. This choice only controls where tasks come from and where status writes back.")
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

            if selectedProviderKind == .feishu {
                feishuConfigurationStep
            } else {
                localProviderStep
            }

            if let inspection = store.taskProviderInspection {
                setupCard {
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
        }
    }

    private var feishuConfigurationStep: some View {
        Group {
            setupCard {
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
                        Label("Test Feishu Connection", systemImage: "bolt.horizontal.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isInspectingTaskProvider)
            }

            setupCard {
                Text("Field Mapping")
                    .font(.headline)

                Text("Field names must match the table exactly. Testing the connection will auto-suggest mappings when matching fields are found.")
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

            setupCard {
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

    private var localProviderStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupCard {
                Text("Local Tasks")
                    .font(.headline)

                Text("Local Tasks keeps the inbox inside Looper. Tasks are persisted on this Mac and status updates stay local.")
                    .foregroundStyle(.secondary)

                welcomeBullet(
                    title: "No external credentials",
                    detail: "You can finish setup without connecting any third-party system."
                )
                welcomeBullet(
                    title: "Best for solo workflows",
                    detail: "Use it when you want a private queue or need the app to work offline."
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
    }

    private var environmentStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupCard {
                Text("Local Defaults")
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

            setupCard {
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

                Text("Claude CLI and Git should be installed. tmux is optional but recommended for stable re-attach behavior.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let report = store.environmentReport {
                    toolStatusRow(report.git)
                    toolStatusRow(report.claude)
                    toolStatusRow(report.tmux)
                } else {
                    Text("Run the environment check to verify the machine before starting the first task.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupCard {
                Text("Ready To Start")
                    .font(.headline)

                welcomeBullet(
                    title: "\(selectedProviderKind.label) ready",
                    detail: providerReadyDetail
                )
                welcomeBullet(
                    title: "Local environment verified",
                    detail: store.environmentReport?.isReady == true
                        ? "Git and Claude CLI are ready on this machine."
                        : "Run the environment check if you want to verify this machine again."
                )
                welcomeBullet(
                    title: "After finishing",
                    detail: finishStepDetail
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            if store.setupStep != .welcome {
                Button("Back") {
                    store.send(.backSetupStepButtonTapped)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if store.setupStep == .finish {
                Button {
                    store.send(.finishSetupButtonTapped)
                } label: {
                    if store.isFinishingSetup || store.pipeline.isSavingPreferences {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Finish Setup")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canFinish)
            } else {
                Button("Continue") {
                    store.send(.advanceSetupStepButtonTapped)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
            }
        }
    }

    private var selectedProviderKind: TaskProviderKind {
        store.pipeline.preferences.taskProviderConfiguration.kind
    }

    private var stepSubtitle: String {
        switch store.setupStep {
        case .welcome:
            "A quick path from first launch to the first running task."
        case .taskSource:
            "Choose the task source you want Looper to orchestrate."
        case .environment:
            "Verify that the local machine can launch Claude and manage repositories."
        case .finish:
            "Persist the setup and return to the inbox ready to run work."
        }
    }

    private var canAdvance: Bool {
        switch store.setupStep {
        case .welcome:
            true
        case .taskSource:
            selectedProviderKind == .local || store.taskProviderInspection != nil
        case .environment:
            store.environmentReport?.isReady == true
        case .finish:
            false
        }
    }

    private var canFinish: Bool {
        store.pipeline.preferences.taskProviderConfiguration.canFetchTasks
            && store.environmentReport?.isReady == true
    }

    private var providerReadyDetail: String {
        switch selectedProviderKind {
        case .local:
            return store.taskProviderInspection == nil
                ? "Local Tasks is selected as the inbox source for this Mac."
                : "Looper found \(store.taskProviderInspection?.previewTaskCount ?? 0) local tasks on this Mac."
        case .feishu:
            return store.taskProviderInspection == nil
                ? "The current Feishu configuration is saved, even if it was not tested in this session."
                : "The selected Feishu table responded and field discovery completed."
        }
    }

    private var finishStepDetail: String {
        switch selectedProviderKind {
        case .local:
            "Looper will open the inbox ready for you to create and launch local tasks."
        case .feishu:
            "Looper will refresh the inbox and return you to the main window ready to launch the first synced task."
        }
    }

    private func stepBadgeTitle(_ step: AppFeature.SetupStep) -> String {
        if step.rawValue < store.setupStep.rawValue {
            return "Done"
        }
        if step == store.setupStep {
            return "Current"
        }
        return "Next"
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
    private func setupCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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

    private func welcomeBullet(title: String, detail: String) -> some View {
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
