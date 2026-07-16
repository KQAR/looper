import SwiftUI

/// Renders a unified diff patch with conventional +/− line coloring.
/// Part of the review card's evidence (INTERACTION.md: the diff renders
/// inline — no detour through external tools just to decide).
@MainActor
struct DiffView: View {
    var diff: PresentedDiff
    var onDismiss: () -> Void

    private let lang = AppLanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(diff.taskTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Text("diff.close", bundle: lang.bundle)
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diff.patch.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        diffLine(String(line))
                    }
                }
                .padding(16)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 420, idealHeight: 560)
    }

    @ViewBuilder
    private func diffLine(_ line: String) -> some View {
        Text(line.isEmpty ? " " : line)
            .font(.body.monospaced())
            .foregroundStyle(lineColor(line))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lineBackground(line))
            .textSelection(.enabled)
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
            return .secondary
        }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        if line.hasPrefix("@@") { return .secondary }
        return .primary
    }

    private func lineBackground(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .clear }
        if line.hasPrefix("+") { return .green.opacity(0.08) }
        if line.hasPrefix("-") { return .red.opacity(0.08) }
        return .clear
    }
}
