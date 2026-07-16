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
            // Cards exist only for tasks routed to an existing pipeline.
            // A task whose pipeline was deleted is stranded: it must not
            // offer loop decisions (retry would silently resurrect the
            // pipeline). Stranded tasks stay reachable on the Manage surface.
            guard let pipelineName = pipelineName(for: task, in: pipeline.pipelines) else {
                continue
            }

            let latestRun = runs
                .filter { $0.taskID == task.id }
                .max(by: { $0.startedAt < $1.startedAt })

            switch task.status {
            case .inReview:
                cards.append(
                    InboxCard(
                        id: "review-\(task.id)",
                        kind: .reviewRequest(taskID: task.id),
                        title: task.title,
                        detail: String(localized: "inbox.card.review.detail", bundle: .localized),
                        pipelineName: pipelineName,
                        diffPath: latestRun?.diffPath
                    )
                )

            case .todo, .inProgress:
                guard let latestRun,
                      !latestRun.isActive,
                      !runs.contains(where: { $0.taskID == task.id && $0.isActive }),
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
                        pipelineName: pipelineName,
                        occurredAt: latestRun.finishedAt,
                        diffPath: latestRun.diffPath
                    )
                )

            case .done:
                break
            }
        }

        if let maintenance = maintenanceCard {
            cards.append(maintenance)
        }

        cards.sort { lhs, rhs in
            if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
            return (lhs.occurredAt ?? .distantPast) > (rhs.occurredAt ?? .distantPast)
        }

        return IdentifiedArray(uniqueElements: cards)
    }

    /// Leftovers that structured cleanup missed (crashes, legacy data):
    /// preserved worktrees whose task is done or vanished, and run records
    /// whose pipeline was deleted. Silent until both sources have loaded.
    private var maintenanceCard: InboxCard? {
        guard hasLoadedPipelines, hasLoadedTasks else { return nil }

        var staleWorktreeRunIDs: [UUID] = []
        var orphanedRunIDs: [UUID] = []

        for run in runs where !run.isActive {
            if pipeline.pipelines[id: run.pipelineID] == nil {
                orphanedRunIDs.append(run.id)
            } else if run.worktreePath != nil {
                let task = tasks[id: run.taskID]
                if task == nil || task?.status == .done {
                    staleWorktreeRunIDs.append(run.id)
                }
            }
        }

        guard !staleWorktreeRunIDs.isEmpty || !orphanedRunIDs.isEmpty else { return nil }

        return InboxCard(
            id: "maintenance",
            kind: .maintenance(
                staleWorktreeRunIDs: staleWorktreeRunIDs,
                orphanedRunIDs: orphanedRunIDs
            ),
            title: String(localized: "inbox.card.maintenance.title", bundle: .localized),
            detail: String(
                format: String(localized: "inbox.card.maintenance.detail", bundle: .localized),
                staleWorktreeRunIDs.count,
                orphanedRunIDs.count
            )
        )
    }

    var inboxQuietRunCount: Int {
        runs.count(where: \.isActive)
    }

    var inboxBacklogCount: Int {
        let failureTaskIDs = Set(inboxCards.compactMap { card -> LooperTask.ID? in
            guard case .failureEscalation = card.kind else { return nil }
            return card.taskID
        })
        // Stranded tasks (no matching pipeline) cannot start, so they are
        // not "queued" — counting them would promise runs that never come.
        return tasks.count {
            $0.status == .todo
                && !failureTaskIDs.contains($0.id)
                && pipelineName(for: $0, in: pipeline.pipelines) != nil
        }
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
