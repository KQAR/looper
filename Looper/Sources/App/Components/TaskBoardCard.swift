import SwiftUI

@MainActor
struct TaskBoardCard: View {
    let task: LooperTask
    let isSelected: Bool
    let isUpdating: Bool
    var hasTerminal: Bool = false
    var isTerminalExpanded: Bool = false
    let onSelect: () -> Void
    let onStart: (() -> Void)?
    let onMarkDone: (() -> Void)?
    let onMarkFailed: (() -> Void)?
    var onAttach: (() -> Void)? = nil
    var onExpandTerminal: (() -> Void)? = nil

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
    private var actionMenuContent: some View {
        if let onStart {
            Button {
                onStart()
                isActionMenuPresented = false
            } label: {
                Label(String(localized: "task.start", bundle: lang.bundle), systemImage: "play.fill")
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

        if let onMarkFailed {
            Button {
                onMarkFailed()
                isActionMenuPresented = false
            } label: {
                Label(String(localized: "task.fail", bundle: lang.bundle), systemImage: "xmark.circle")
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
