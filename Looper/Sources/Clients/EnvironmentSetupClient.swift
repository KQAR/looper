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
            await withTaskGroup(of: EnvironmentToolStatus.self) { group in
                group.addTask { inspectTool(name: "Git", command: "git") }
                group.addTask { inspectTool(name: "Claude CLI", command: "claude") }
                group.addTask { inspectTool(name: "tmux", command: "tmux") }

                var statuses: [String: EnvironmentToolStatus] = [:]
                for await status in group {
                    statuses[status.command] = status
                }

                return EnvironmentSetupReport(
                    git: statuses["git"] ?? .init(name: "Git", command: "git", isInstalled: false),
                    claude: statuses["claude"] ?? .init(name: "Claude CLI", command: "claude", isInstalled: false),
                    tmux: statuses["tmux"] ?? .init(name: "tmux", command: "tmux", isInstalled: false)
                )
            }
        }
    )
}

private func inspectTool(name: String, command: String) -> EnvironmentToolStatus {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", "command -v \(command)"]

    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return EnvironmentToolStatus(
            name: name,
            command: command,
            isInstalled: false,
            resolvedPath: nil
        )
    }

    let path = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return EnvironmentToolStatus(
        name: name,
        command: command,
        isInstalled: process.terminationStatus == 0 && !path.isEmpty,
        resolvedPath: path.isEmpty ? nil : path
    )
}
