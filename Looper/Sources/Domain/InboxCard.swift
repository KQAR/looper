import Foundation

/// A machine-generated decision request surfaced to the owner.
/// Pending cards form the Inbox; resolution happens on the card itself.
/// See INTERACTION.md — cards are a "reverse issue system": typed, short-lived,
/// self-healing (a card disappears when its situation resolves itself).
struct InboxCard: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Environment fault not tied to any Run (missing CLI, broken PATH).
        case system(toolName: String, command: String)
        /// A task finished its run and awaits human review.
        case reviewRequest(taskID: LooperTask.ID)
        /// A task's latest run failed and no retry is active; worktree preserved.
        case failureEscalation(taskID: LooperTask.ID, runID: UUID, worktreePath: String?)
        /// Aggregated leftovers: preserved worktrees whose task is done or
        /// gone, and run records whose pipeline no longer exists.
        case maintenance(staleWorktreeRunIDs: [UUID], orphanedRunIDs: [UUID])
    }

    var id: String
    var kind: Kind
    var title: String
    var detail: String
    var pipelineName: String?
    var occurredAt: Date?

    /// System cards float above all Run cards; failures above reviews;
    /// maintenance sinks to the bottom (low urgency).
    var sortRank: Int {
        switch kind {
        case .system: 0
        case .failureEscalation: 1
        case .reviewRequest: 2
        case .maintenance: 3
        }
    }

    var taskID: LooperTask.ID? {
        switch kind {
        case .system, .maintenance: nil
        case let .reviewRequest(taskID): taskID
        case let .failureEscalation(taskID, _, _): taskID
        }
    }
}

/// A short instruction from the owner to a task's next run — the level-1
/// intervention in INTERACTION.md. Queued notes are consumed (delivered)
/// when the task's next run launches.
struct SteeringNote: Equatable, Identifiable, Sendable {
    enum Origin: Equatable, Sendable {
        /// Typed by the owner on a card or task.
        case user
        /// Auto-queued from a mandatory send-back reason.
        case sendBackReason
    }

    var id: UUID
    var taskID: LooperTask.ID
    var text: String
    var origin: Origin
    var createdAt: Date
}
