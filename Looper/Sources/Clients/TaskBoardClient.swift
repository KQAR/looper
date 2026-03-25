import ComposableArchitecture
import Foundation

@DependencyClient
struct TaskBoardClient {
    var fetchTasks: @Sendable () async -> [LooperTask] = { [] }
}

extension DependencyValues {
    var taskBoardClient: TaskBoardClient {
        get { self[TaskBoardClient.self] }
        set { self[TaskBoardClient.self] = newValue }
    }
}

extension TaskBoardClient: DependencyKey {
    static let liveValue = Self(
        fetchTasks: {
            [
                LooperTask(
                    id: "task-101",
                    title: "Stabilize workspace restore flow",
                    summary: "Make sidebar projects and last selection survive relaunch.",
                    status: .developing,
                    source: "Mock Feishu",
                    repoPath: URL(filePath: "/tmp/looper")
                ),
                LooperTask(
                    id: "task-102",
                    title: "Add project picker for local repos",
                    summary: "Let users add a local project without typing the path manually.",
                    status: .pending,
                    source: "Mock Feishu",
                    repoPath: URL(filePath: "/tmp/demo-app")
                ),
                LooperTask(
                    id: "task-103",
                    title: "Investigate failed sync writeback",
                    summary: "Inspect why remote status writeback sometimes stalls after agent exit.",
                    status: .failed,
                    source: "Mock Feishu",
                    repoPath: URL(filePath: "/tmp/api-service")
                ),
            ]
        }
    )
}
