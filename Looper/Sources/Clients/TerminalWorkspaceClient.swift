import ComposableArchitecture
import Foundation

@DependencyClient
struct TerminalWorkspaceClient {
    var upsertSession: @Sendable (CodingWorkspace) async -> Void
    var removeSession: @Sendable (UUID) async -> Void
    var focusSession: @Sendable (UUID) async -> Void
    var bootstrapSession: @Sendable (UUID) async -> Void
    var rebuildSession: @Sendable (CodingWorkspace) async -> Void
    var events: @Sendable () async -> AsyncStream<WorkspaceTerminalEvent> = {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

extension DependencyValues {
    var terminalWorkspaceClient: TerminalWorkspaceClient {
        get { self[TerminalWorkspaceClient.self] }
        set { self[TerminalWorkspaceClient.self] = newValue }
    }
}

extension TerminalWorkspaceClient: DependencyKey {
    static let liveValue = TerminalWorkspaceClient(
        upsertSession: { workspace in
            await MainActor.run {
                WorkspaceTerminalRegistry.shared.upsertSession(for: workspace)
            }
        },
        removeSession: { id in
            await MainActor.run {
                WorkspaceTerminalRegistry.shared.removeSession(id: id)
            }
        },
        focusSession: { id in
            await MainActor.run {
                WorkspaceTerminalRegistry.shared.session(id: id)?.focus()
            }
        },
        bootstrapSession: { id in
            await MainActor.run {
                WorkspaceTerminalRegistry.shared.session(id: id)?.scheduleAttach()
            }
        },
        rebuildSession: { workspace in
            await MainActor.run {
                WorkspaceTerminalRegistry.shared.rebuildSession(for: workspace)
            }
        },
        events: {
            await MainActor.run {
                WorkspaceTerminalRegistry.shared.events()
            }
        }
    )
}
