import Foundation

struct EnvironmentToolStatus: Equatable, Sendable {
    var name: String
    var command: String
    var isInstalled: Bool
    var resolvedPath: String?

    var label: String {
        isInstalled ? "Ready" : "Missing"
    }

    var detail: String {
        resolvedPath ?? "Not found"
    }
}

struct EnvironmentSetupReport: Equatable, Sendable {
    var git: EnvironmentToolStatus
    var claude: EnvironmentToolStatus
    var tmux: EnvironmentToolStatus

    var isReady: Bool {
        git.isInstalled && claude.isInstalled
    }
}
