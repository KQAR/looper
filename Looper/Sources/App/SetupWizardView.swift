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
        case .taskBoard:
            taskBoardStep
        case .environment:
            environmentStep
        case .finish:
            finishStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupCard {
                Text("Looper turns a Feishu task into a live local execution context.")
                    .font(.title3.weight(.semibold))

                Text("The first-run flow connects your task board, verifies that Claude can run locally, and then drops you back into the inbox ready to start the first task.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    welcomeBullet(
                        title: "Connect one Feishu Bitable table",
                        detail: "Looper fetches tasks and writes `developing`, `done`, and `failed` back to the same table."
                    )
                    welcomeBullet(
                        title: "Verify Git and Claude CLI",
                        detail: "The app checks the local environment before you start any task."
                    )
                    welcomeBullet(
                        title: "Run the first task end-to-end",
                        detail: "Once setup is complete, refresh the inbox and launch the first execution terminal."
                    )
                }
            }
        }
    }

    private var taskBoardStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupCard {
                Text("Connection")
                    .font(.headline)

                labeledField("App ID") {
                    TextField("cli_xxx", text: taskBoardAppIDBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("App Secret") {
                    SecureField("xxx", text: taskBoardAppSecretBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Bitable App Token") {
                    TextField("bascn_xxx", text: taskBoardAppTokenBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Table ID") {
                    TextField("tblxxx", text: taskBoardTableIDBinding)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    store.send(.testTaskBoardConnectionButtonTapped)
                } label: {
                    if store.isInspectingTaskBoard {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Test Connection", systemImage: "bolt.horizontal.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isInspectingTaskBoard)
            }

            setupCard {
                Text("Field Mapping")
                    .font(.headline)

                Text("Field names must match the table exactly. Testing the connection will auto-suggest mappings when matching fields are found.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                labeledField("Title Field") {
                    TextField("Title", text: taskBoardTitleFieldBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Summary Field") {
                    TextField("Summary", text: taskBoardSummaryFieldBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Status Field") {
                    TextField("Status", text: taskBoardStatusFieldBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Repository Field") {
                    TextField("Repository", text: taskBoardRepositoryFieldBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            setupCard {
                Text("Status Mapping")
                    .font(.headline)

                labeledField("Pending Value") {
                    TextField("pending", text: taskBoardPendingValueBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Running Value") {
                    TextField("developing", text: taskBoardDevelopingValueBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Done Value") {
                    TextField("done", text: taskBoardDoneValueBinding)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Failed Value") {
                    TextField("failed", text: taskBoardFailedValueBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let inspection = store.taskBoardInspection {
                setupCard {
                    Text("Connection Result")
                        .font(.headline)

                    Text("Previewed \(inspection.previewTaskCount) records from the selected table.")
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

    private var environmentStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupCard {
                Text("Local Defaults")
                    .font(.headline)

                labeledField("Default Project Path") {
                    TextField("/Users/you/project", text: defaultRepositoryPathBinding)
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
                    title: "Feishu task board connected",
                    detail: store.taskBoardInspection == nil
                        ? "Connection has not been tested in this session, but the current configuration is saved."
                        : "The selected table responded and field discovery completed."
                )
                welcomeBullet(
                    title: "Local environment verified",
                    detail: store.environmentReport?.isReady == true
                        ? "Git and Claude CLI are ready on this machine."
                        : "Run the environment check if you want to verify this machine again."
                )
                welcomeBullet(
                    title: "After finishing",
                    detail: "Looper will refresh the inbox and return you to the main window ready to launch the first task."
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
                    if store.isFinishingSetup || store.workspace.isSavingPreferences {
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

    private var stepSubtitle: String {
        switch store.setupStep {
        case .welcome:
            "A quick path from first launch to the first running task."
        case .taskBoard:
            "Connect one Feishu Bitable table and confirm the field mapping."
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
        case .taskBoard:
            store.taskBoardInspection != nil
        case .environment:
            store.environmentReport?.isReady == true
        case .finish:
            false
        }
    }

    private var canFinish: Bool {
        store.workspace.preferences.taskBoardConfiguration.isConfigured
            && store.environmentReport?.isReady == true
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

    private var defaultRepositoryPathBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.defaultRepositoryPath },
            set: { store.send(.workspace(.binding(.set(\.preferences.defaultRepositoryPath, $0)))) }
        )
    }

    private var defaultAgentCommandBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.defaultAgentCommand },
            set: { store.send(.workspace(.binding(.set(\.preferences.defaultAgentCommand, $0)))) }
        )
    }

    private var taskBoardAppIDBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.appID },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.appID, $0)))) }
        )
    }

    private var taskBoardAppSecretBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.appSecret },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.appSecret, $0)))) }
        )
    }

    private var taskBoardAppTokenBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.appToken },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.appToken, $0)))) }
        )
    }

    private var taskBoardTableIDBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.tableID },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.tableID, $0)))) }
        )
    }

    private var taskBoardTitleFieldBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.titleFieldName },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.titleFieldName, $0)))) }
        )
    }

    private var taskBoardSummaryFieldBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.summaryFieldName },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.summaryFieldName, $0)))) }
        )
    }

    private var taskBoardStatusFieldBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.statusFieldName },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.statusFieldName, $0)))) }
        )
    }

    private var taskBoardRepositoryFieldBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.repoPathFieldName },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.repoPathFieldName, $0)))) }
        )
    }

    private var taskBoardPendingValueBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.pendingStatusValue },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.pendingStatusValue, $0)))) }
        )
    }

    private var taskBoardDevelopingValueBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.developingStatusValue },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.developingStatusValue, $0)))) }
        )
    }

    private var taskBoardDoneValueBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.doneStatusValue },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.doneStatusValue, $0)))) }
        )
    }

    private var taskBoardFailedValueBinding: Binding<String> {
        Binding(
            get: { store.workspace.preferences.taskBoardConfiguration.failedStatusValue },
            set: { store.send(.workspace(.binding(.set(\.preferences.taskBoardConfiguration.failedStatusValue, $0)))) }
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
