import Foundation

struct LooperTask: Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var summary: String
    var status: Status
    var source: String
    var repoPath: URL?

    enum Status: String, Equatable, Sendable {
        case pending
        case developing
        case done
        case failed

        var label: String {
            switch self {
            case .pending:
                "Pending"
            case .developing:
                "Running"
            case .done:
                "Done"
            case .failed:
                "Failed"
            }
        }
    }
}
