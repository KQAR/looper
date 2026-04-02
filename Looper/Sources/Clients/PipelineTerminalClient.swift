import ComposableArchitecture
import Foundation

@DependencyClient
struct PipelineTerminalClient {
    var upsertSession: @Sendable (Pipeline) async -> Void
    var removeSession: @Sendable (UUID) async -> Void
    var focusSession: @Sendable (UUID) async -> Void
    var bootstrapSession: @Sendable (UUID) async -> Void
    var attachSessionIfNeeded: @Sendable (UUID) async -> Void
    var rebuildSession: @Sendable (Pipeline) async -> Void
    // Run-level terminal sessions
    var upsertRunSession: @Sendable (_ runID: UUID, _ pipeline: Pipeline, _ executionPath: String) async -> Void
    var focusRunSession: @Sendable (_ runID: UUID) async -> Void
    var bootstrapRunSession: @Sendable (_ runID: UUID) async -> Void
    var removeRunSession: @Sendable (_ runID: UUID) async -> Void
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
        attachSessionIfNeeded: { id in
            await MainActor.run {
                PipelineTerminalRegistry.shared.session(id: id)?.markShouldAttach()
            }
        },
        rebuildSession: { pipeline in
            await MainActor.run {
                PipelineTerminalRegistry.shared.rebuildSession(for: pipeline)
            }
        },
        upsertRunSession: { runID, pipeline, executionPath in
            await MainActor.run {
                PipelineTerminalRegistry.shared.upsertRunSession(
                    runID: runID,
                    pipeline: pipeline,
                    executionPath: executionPath
                )
            }
        },
        focusRunSession: { runID in
            await MainActor.run {
                PipelineTerminalRegistry.shared.runSession(id: runID)?.focus()
            }
        },
        bootstrapRunSession: { runID in
            await MainActor.run {
                PipelineTerminalRegistry.shared.runSession(id: runID)?.scheduleAttach()
            }
        },
        removeRunSession: { runID in
            await MainActor.run {
                PipelineTerminalRegistry.shared.removeRunSession(id: runID)
            }
        },
        events: {
            await MainActor.run {
                PipelineTerminalRegistry.shared.events()
            }
        }
    )

    static let testValue = PipelineTerminalClient(
        upsertSession: { _ in },
        removeSession: { _ in },
        focusSession: { _ in },
        bootstrapSession: { _ in },
        attachSessionIfNeeded: { _ in },
        rebuildSession: { _ in },
        upsertRunSession: { _, _, _ in },
        focusRunSession: { _ in },
        bootstrapRunSession: { _ in },
        removeRunSession: { _ in },
        events: {
            AsyncStream { continuation in
                continuation.finish()
            }
        }
    )
}
