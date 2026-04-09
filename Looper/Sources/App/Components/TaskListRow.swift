import SwiftUI

@MainActor
struct TaskListRow: View {
    let task: LooperTask
    let isSelected: Bool
    let isUpdating: Bool
    var isActive: Bool = false
    var hasTerminal: Bool = false
    var activeRun: Run? = nil
    let onSelect: () -> Void
    let onStart: (() -> Void)?
    let onMarkReview: (() -> Void)?
    let onMarkDone: (() -> Void)?
    let onReturnToTodo: (() -> Void)?
    var onAttach: (() -> Void)? = nil
    var onCancelRun: (() -> Void)? = nil

    private let lang = AppLanguageManager.shared

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(isSelected ? task.status.tintColor : task.status.tintColor.opacity(0.18))
                    .overlay {
                        Circle()
                            .strokeBorder(task.status.tintColor, lineWidth: 1.5)
                    }
                    .frame(width: 12, height: 12)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(task.title)
                            .font(.headline.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if hasTerminal {
                            Image(systemName: "terminal")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        if isUpdating {
                            ProgressView()
                                .controlSize(.mini)
                        }

                        if isActive, let onCancelRun {
                            Button(role: .destructive, action: onCancelRun) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help(Text("task.stopRun", bundle: lang.bundle))
                        }
                    }

                    if let secondaryLine {
                        Text(secondaryLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        AppStatusBadge(
                            title: task.status.localizedLabel(bundle: lang.bundle),
                            tint: task.status.tintColor
                        )

                        Text(task.source)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05), in: Capsule())

                        Text(task.repoPath?.lastPathComponent ?? String(localized: "task.noProject", bundle: lang.bundle))
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if let runMeta {
                            Text(runMeta)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .contextMenu { actionMenuContent }
    }

    private var secondaryLine: String? {
        if let activity = activeRun?.currentActivity, !activity.isEmpty {
            return activity
        }

        let summary = task.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private var runMeta: String? {
        guard isActive, let activeRun else { return nil }
        let elapsed = Date.now.timeIntervalSince(activeRun.startedAt)
        guard elapsed > 0 else { return nil }

        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    @ViewBuilder
    private var actionMenuContent: some View {
        if let onStart {
            Button(action: onStart) {
                Label(String(localized: "task.start", bundle: lang.bundle), systemImage: "play.fill")
            }
        }

        if let onMarkReview {
            Button(action: onMarkReview) {
                Label(String(localized: "task.markReview", bundle: lang.bundle), systemImage: "eye")
            }
        }

        if let onMarkDone {
            Button(action: onMarkDone) {
                Label(String(localized: "task.done", bundle: lang.bundle), systemImage: "checkmark.circle")
            }
        }

        if let onReturnToTodo {
            Button(action: onReturnToTodo) {
                Label(String(localized: "task.returnToTodo", bundle: lang.bundle), systemImage: "arrow.uturn.backward")
            }
        }

        if let onAttach {
            Divider()
            Button(action: onAttach) {
                Label(String(localized: "workspace.attach", bundle: lang.bundle), systemImage: "terminal")
            }
        }

        if let onCancelRun {
            Divider()
            Button(role: .destructive, action: onCancelRun) {
                Label(String(localized: "task.stopRun", defaultValue: "Stop Run", bundle: lang.bundle), systemImage: "stop.circle")
            }
        }
    }
}

private extension LooperTask.Status {
    var tintColor: Color {
        switch self {
        case .todo:
            .secondary
        case .inProgress:
            .orange
        case .inReview:
            .blue
        case .done:
            .green
        }
    }
}
