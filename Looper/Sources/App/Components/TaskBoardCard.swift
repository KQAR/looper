import SwiftUI

@MainActor
struct TaskBoardCard: View {
    let task: LooperTask
    let isSelected: Bool
    let isUpdating: Bool
    let onSelect: () -> Void
    let onStart: (() -> Void)?
    let onMarkDone: (() -> Void)?
    let onMarkFailed: (() -> Void)?

    private let lang = AppLanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                AppStatusBadge(title: task.status.localizedLabel(bundle: lang.bundle))
            }

            Text(task.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Text(task.repoPath?.lastPathComponent ?? String(localized: "task.noProject", bundle: lang.bundle))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(task.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(isSelected
                    ? String(localized: "task.selected", bundle: lang.bundle)
                    : String(localized: "task.inspect", bundle: lang.bundle)
                ) {
                    onSelect()
                }
                .buttonStyle(.bordered)

                if let onStart {
                    Button(String(localized: "task.start", bundle: lang.bundle)) {
                        onStart()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let onMarkDone {
                    Button(String(localized: "task.done", bundle: lang.bundle)) {
                        onMarkDone()
                    }
                    .buttonStyle(.bordered)
                }

                if let onMarkFailed {
                    Button(String(localized: "task.fail", bundle: lang.bundle)) {
                        onMarkFailed()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }

            if isUpdating {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04),
            in: .rect(cornerRadius: 16)
        )
    }
}
