import ComposableArchitecture
import Foundation

@DependencyClient
struct EnvironmentSetupClient {
    var inspect: @Sendable () async -> EnvironmentSetupReport = {
        EnvironmentSetupReport(
            git: .init(name: "Git", command: "git", isInstalled: false),
            claude: .init(name: "Claude CLI", command: "claude", isInstalled: false),
            tmux: .init(name: "tmux", command: "tmux", isInstalled: false)
        )
    }
}

extension DependencyValues {
    var environmentSetupClient: EnvironmentSetupClient {
        get { self[EnvironmentSetupClient.self] }
        set { self[EnvironmentSetupClient.self] = newValue }
    }
}

extension EnvironmentSetupClient: DependencyKey {
    static let liveValue = Self(
        inspect: {
            // Static resolution first (process PATH + well-known install
            // dirs — no shell). Only names that miss trigger one batched
            // interactive-login-shell lookup, which sees the PATH the
            // user's terminal sees (see ExecutableResolver).
            let tools = [
                (name: "Git", command: "git"),
                (name: "Claude CLI", command: "claude"),
                (name: "tmux", command: "tmux"),
            ]

            var resolved: [String: String] = [:]
            for tool in tools {
                if let path = ExecutableResolver.resolveStatically(tool.command) {
                    resolved[tool.command] = path
                }
            }

            let missing = tools.map(\.command).filter { resolved[$0] == nil }
            if !missing.isEmpty {
                let shellResolved = await ExecutableResolver.resolveViaLoginShell(names: missing)
                resolved.merge(shellResolved) { current, _ in current }
            }

            func status(_ name: String, _ command: String) -> EnvironmentToolStatus {
                EnvironmentToolStatus(
                    name: name,
                    command: command,
                    isInstalled: resolved[command] != nil,
                    resolvedPath: resolved[command]
                )
            }

            return EnvironmentSetupReport(
                git: status("Git", "git"),
                claude: status("Claude CLI", "claude"),
                tmux: status("tmux", "tmux")
            )
        }
    )
}
