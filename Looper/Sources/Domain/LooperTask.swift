import Foundation

struct LooperTask: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var summary: String
    var status: Status
    var source: String
    var repoPath: URL?

    enum Status: String, Codable, Equatable, Sendable {
        case todo
        case inProgress = "in_progress"
        case inReview = "in_review"
        case done

        var label: String {
            switch self {
            case .todo: "Todo"
            case .inProgress: "In Progress"
            case .inReview: "In Review"
            case .done: "Done"
            }
        }

        func localizedLabel(bundle: Bundle) -> String {
            switch self {
            case .todo: String(localized: "status.todo", bundle: bundle)
            case .inProgress: String(localized: "status.inProgress", bundle: bundle)
            case .inReview: String(localized: "status.inReview", bundle: bundle)
            case .done: String(localized: "status.done", bundle: bundle)
            }
        }
    }
}
