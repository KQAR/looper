import SwiftUI

@MainActor
struct PipelineSidebarRow: View {
    let pipeline: Pipeline
    let taskCount: Int
    let activeRunTitle: String?

    private let lang = AppLanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pipeline.name)
                    .font(.headline)
                Spacer()
                if let activeRunTitle {
                    AppStatusBadge(title: activeRunTitle)
                }
            }

            Text(pipeline.executionDirectoryName)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            Text(String(localized: "sidebar.linkedTasks \(taskCount)", bundle: lang.bundle))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
