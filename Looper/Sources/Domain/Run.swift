import Foundation

struct Run: Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Equatable, Sendable {
        case running
        case succeeded
        case failed

        var label: String {
            switch self {
            case .running:
                "Running"
            case .succeeded:
                "Succeeded"
            case .failed:
                "Failed"
            }
        }
    }

    enum Trigger: String, Codable, Equatable, Sendable {
        case startTask
        case resumeTask

        var label: String {
            switch self {
            case .startTask:
                "Start Task"
            case .resumeTask:
                "Resume Task"
            }
        }
    }

    var id: UUID
    var pipelineID: UUID
    var taskID: LooperTask.ID
    var status: Status
    var trigger: Trigger
    var startedAt: Date
    var finishedAt: Date?
    var exitCode: Int32?
    var logPath: String

    var isActive: Bool {
        status == .running
    }
}

extension Run {
    func finished(
        status: Status,
        exitCode: Int32?,
        finishedAt: Date
    ) -> Self {
        var copy = self
        copy.status = status
        copy.exitCode = exitCode
        copy.finishedAt = finishedAt
        return copy
    }
}
