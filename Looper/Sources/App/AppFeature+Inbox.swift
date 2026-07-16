import ComposableArchitecture
import Foundation

/// The three meanings of an empty Inbox — they must never look the same
/// (INTERACTION.md, Empty & Degraded States).
enum InboxEmptyContext: Equatable, Sendable {
    /// No pipelines exist; show day-0 guidance.
    case unconfigured
    /// Pipelines exist, nothing running, backlog empty.
    case idle
    /// Runs active, no pending decisions — the earned inbox zero.
    case healthy
}

/// Inbox state is *derived*, never stored: pending cards and history are the
/// same data in two tenses (INTERACTION.md). Deriving guarantees cards
/// self-heal the moment their situation resolves (card rule 2).
extension AppFeature.State {
    var inboxCards: IdentifiedArrayOf<InboxCard> {
        var cards: [InboxCard] = []

        if let report = environmentReport {
            for tool in [report.git, report.claude] where !tool.isInstalled {
                cards.append(
                    InboxCard(
                        id: "system-\(tool.command)",
                        kind: .system(toolName: tool.name, command: tool.command),
                        title: String(
                            format: String(localized: "inbox.card.system.title", bundle: .localized),
                            tool.name
                        ),
                        detail: String(
                            format: String(localized: "inbox.card.system.detail", bundle: .localized),
                            tool.command
                        )
                    )
                )
            }
        }

        for task in tasks {
            switch task.status {
            case .inReview:
                cards.append(
                    InboxCard(
                        id: "review-\(task.id)",
                        kind: .reviewRequest(taskID: task.id),
                        title: task.title,
                        detail: String(localized: "inbox.card.review.detail", bundle: .localized),
                        pipelineName: pipelineName(for: task, in: pipeline.pipelines)
                    )
                )

            case .todo, .inProgress:
                let taskRuns = runs.filter { $0.taskID == task.id }
                guard !taskRuns.contains(where: \.isActive),
                      let latestRun = taskRuns.max(by: { $0.startedAt < $1.startedAt }),
                      latestRun.status == .failed
                else { break }
                cards.append(
                    InboxCard(
                        id: "failure-\(task.id)",
                        kind: .failureEscalation(
                            taskID: task.id,
                            runID: latestRun.id,
                            worktreePath: latestRun.worktreePath
                        ),
                        title: task.title,
                        detail: String(localized: "inbox.card.failure.detail", bundle: .localized),
                        pipelineName: pipelineName(for: task, in: pipeline.pipelines),
                        occurredAt: latestRun.finishedAt
                    )
                )

            case .done:
                break
            }
        }

        cards.sort { lhs, rhs in
            if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
            return (lhs.occurredAt ?? .distantPast) > (rhs.occurredAt ?? .distantPast)
        }

        return IdentifiedArray(uniqueElements: cards)
    }

    var inboxQuietRunCount: Int {
        runs.count(where: \.isActive)
    }

    var inboxBacklogCount: Int {
        let failureTaskIDs = Set(inboxCards.compactMap { card -> LooperTask.ID? in
            guard case .failureEscalation = card.kind else { return nil }
            return card.taskID
        })
        return tasks.count { $0.status == .todo && !failureTaskIDs.contains($0.id) }
    }

    var inboxEmptyContext: InboxEmptyContext {
        if pipeline.pipelines.isEmpty {
            .unconfigured
        } else if inboxQuietRunCount > 0 {
            .healthy
        } else {
            .idle
        }
    }
}

private func pipelineName(
    for task: LooperTask,
    in pipelines: IdentifiedArrayOf<Pipeline>
) -> String? {
    guard let taskPath = task.repoPath?.standardizedFileURL.path(percentEncoded: false) else {
        return nil
    }
    return pipelines.first {
        $0.executionURL.standardizedFileURL.path(percentEncoded: false) == taskPath
    }?.name
}
