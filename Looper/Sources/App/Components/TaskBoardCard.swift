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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                AppStatusBadge(title: task.status.label)
            }

            Text(task.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Text(task.repoPath?.lastPathComponent ?? "No Project")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(task.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(isSelected ? "Selected" : "Inspect") {
                    onSelect()
                }
                .buttonStyle(.bordered)

                if let onStart {
                    Button("Start") {
                        onStart()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let onMarkDone {
                    Button("Done") {
                        onMarkDone()
                    }
                    .buttonStyle(.bordered)
                }

                if let onMarkFailed {
                    Button("Fail") {
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
