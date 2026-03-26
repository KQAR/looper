import Foundation

struct LocalTaskDraft: Equatable, Sendable {
    var title: String = ""
    var summary: String = ""
    var projectPath: String = ""

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedProjectPath: String {
        projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCreate: Bool {
        !trimmedTitle.isEmpty && !trimmedProjectPath.isEmpty
    }

    func makeTask() -> LooperTask {
        LooperTask(
            id: UUID().uuidString,
            title: trimmedTitle,
            summary: trimmedSummary,
            status: .pending,
            source: "Local",
            repoPath: URL(fileURLWithPath: NSString(string: trimmedProjectPath).expandingTildeInPath)
                .standardizedFileURL
        )
    }
}
