import SwiftUI

@MainActor
struct LocalTaskComposerView: View {
    @State private var draft: LocalTaskDraft

    let isCreating: Bool
    let onCancel: () -> Void
    let onCreate: (LocalTaskDraft) -> Void

    init(
        defaultProjectPath: String,
        isCreating: Bool,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (LocalTaskDraft) -> Void
    ) {
        _draft = State(
            initialValue: LocalTaskDraft(projectPath: defaultProjectPath)
        )
        self.isCreating = isCreating
        self.onCancel = onCancel
        self.onCreate = onCreate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New Local Task")
                    .font(.title2.weight(.semibold))
                Text("Create a task inside Looper without relying on any external board.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                labeledField("Title") {
                    TextField("Refactor task provider abstraction", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Summary") {
                    TextEditor(text: $draft.summary)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        .frame(minHeight: 120)
                }

                labeledField("Project Path") {
                    TextField("/Users/you/project", text: $draft.projectPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    onCreate(draft)
                } label: {
                    if isCreating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create Task")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canCreate || isCreating)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 28)
        )
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
}
