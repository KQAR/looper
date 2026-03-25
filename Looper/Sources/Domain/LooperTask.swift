import Foundation

struct LooperTask: Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var status: Status
    var repoPath: URL?

    enum Status: String, Equatable, Sendable {
        case pending
        case developing
        case done
        case failed
    }
}
