import ComposableArchitecture
import Foundation

@DependencyClient
struct PipelineTerminalClient {
    var upsertSession: @Sendable (Pipeline) async -> Void
    var removeSession: @Sendable (UUID) async -> Void
    var focusSession: @Sendable (UUID) async -> Void
    var bootstrapSession: @Sendable (UUID) async -> Void
    var rebuildSession: @Sendable (Pipeline) async -> Void
    var events: @Sendable () async -> AsyncStream<PipelineTerminalEvent> = {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

extension DependencyValues {
    var pipelineTerminalClient: PipelineTerminalClient {
        get { self[PipelineTerminalClient.self] }
        set { self[PipelineTerminalClient.self] = newValue }
    }
}

extension PipelineTerminalClient: DependencyKey {
    static let liveValue = PipelineTerminalClient(
        upsertSession: { pipeline in
            await MainActor.run {
                PipelineTerminalRegistry.shared.upsertSession(for: pipeline)
            }
        },
        removeSession: { id in
            await MainActor.run {
                PipelineTerminalRegistry.shared.removeSession(id: id)
            }
        },
        focusSession: { id in
            await MainActor.run {
                PipelineTerminalRegistry.shared.session(id: id)?.focus()
            }
        },
        bootstrapSession: { id in
            await MainActor.run {
                PipelineTerminalRegistry.shared.session(id: id)?.scheduleAttach()
            }
        },
        rebuildSession: { pipeline in
            await MainActor.run {
                PipelineTerminalRegistry.shared.rebuildSession(for: pipeline)
            }
        },
        events: {
            await MainActor.run {
                PipelineTerminalRegistry.shared.events()
            }
        }
    )
}
