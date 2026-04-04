import SwiftUI

@MainActor
struct TaskBoardCard: View {
    let task: LooperTask
    let isSelected: Bool
    let isUpdating: Bool
    var hasTerminal: Bool = false
    var isTerminalExpanded: Bool = false
    var activeRun: Run? = nil
    let onSelect: () -> Void
    let onStart: (() -> Void)?
    let onMarkReview: (() -> Void)?
    let onMarkDone: (() -> Void)?
    let onReturnToTodo: (() -> Void)?
    var onAttach: (() -> Void)? = nil
    var onExpandTerminal: (() -> Void)? = nil
    var onCancelRun: (() -> Void)? = nil

    @State private var isActionMenuPresented = false
    private let lang = AppLanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if let run = activeRun, run.isActive {
                agentProgressView(run: run)
            }

            HStack(spacing: 8) {
                Text(task.repoPath?.lastPathComponent ?? String(localized: "task.noProject", bundle: lang.bundle))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(task.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if hasTerminal {
                    Button {
                        onExpandTerminal?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isTerminalExpanded ? "rectangle.inset.filled" : "terminal")
                                .font(.system(size: 11))
                            Text(isTerminalExpanded
                                ? String(localized: "task.terminalActive", bundle: lang.bundle)
                                : String(localized: "task.terminalShow", bundle: lang.bundle))
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(isTerminalExpanded ? .accentColor : nil)
                }
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
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture(count: 2) {
            isActionMenuPresented = true
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .contextMenu { actionMenuContent }
        .popover(isPresented: $isActionMenuPresented) {
            actionMenuContent
                .padding(4)
        }
    }

    @ViewBuilder
    private func agentProgressView(run: Run) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let activity = run.currentActivity {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(activity)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 12) {
                if let count = run.toolCallCount, count > 0 {
                    Label("\(count)", systemImage: "wrench.and.screwdriver")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let cost = run.costUSD, cost > 0 {
                    Label(String(format: "$%.2f", cost), systemImage: "dollarsign.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                let elapsed = Date.now.timeIntervalSince(run.startedAt)
                if elapsed > 0 {
                    Label(formatElapsed(elapsed), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let onCancelRun {
                    Button {
                        onCancelRun()
                    } label: {
                        Image(systemName: "stop.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.red)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    @ViewBuilder
    private var actionMenuContent: some View {
        if let onStart {
            Button {
                onStart()
                isActionMenuPresented = false
            } label: {
                Label(String(localized: "task.start", bundle: lang.bundle), systemImage: "play.fill")
            }
        }

        if let onMarkReview {
            Button {
                onMarkReview()
                isActionMenuPresented = false
            } label: {
                Label(String(localized: "task.markReview", bundle: lang.bundle), systemImage: "eye")
            }
        }

        if let onMarkDone {
            Button {
                onMarkDone()
                isActionMenuPresented = false
            } label: {
                Label(String(localized: "task.done", bundle: lang.bundle), systemImage: "checkmark.circle")
            }
        }

        if let onReturnToTodo {
            Button {
                onReturnToTodo()
                isActionMenuPresented = false
            } label: {
                Label(String(localized: "task.returnToTodo", bundle: lang.bundle), systemImage: "arrow.uturn.backward")
            }
        }

        if let onAttach {
            Divider()
            Button {
                onAttach()
                isActionMenuPresented = false
            } label: {
                Label(String(localized: "workspace.attach", bundle: lang.bundle), systemImage: "terminal")
            }
        }
    }
}
