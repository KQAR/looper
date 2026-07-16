import Foundation

/// Resolves third-party CLI names ("claude", "git", "tmux") to absolute
/// executable paths. GUI-launched apps do not inherit the user's interactive
/// shell PATH — nvm/fnm/mise multishells, the Anthropic native installer
/// prefix, and per-user npm prefixes all live in directories that only get
/// added to PATH by ~/.zshrc — so bare-name lookup in the process
/// environment misses tools that work fine in the user's terminal.
///
/// Resolution strategy (after multica's daemon probe):
/// 1. A command containing "/" is a user-pinned path: verify it directly and
///    hard-miss otherwise — never silently substitute a different binary.
/// 2. Scan the process PATH plus well-known install directories with cheap
///    stat calls (the happy path; no shell is spawned).
/// 3. Lazily, only for names that missed, ask the user's *interactive login*
///    shell (`$SHELL -ilc`) to resolve all of them in one batch: strip
///    aliases and shell functions so `command -v` reaches the real binary,
///    require absolute results, and canonicalise the directory so symlinked
///    prefixes (fnm/nvm/volta) collapse to stable paths.
enum ExecutableResolver {
    /// Directories worth probing even when they are missing from the
    /// process PATH.
    static func wellKnownDirectories(home: String = NSHomeDirectory()) -> [String] {
        [
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/share/mise/shims",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
    }

    /// The process PATH augmented with the well-known directories — used
    /// both for static resolution and as the PATH handed to agent child
    /// processes, so a resolved binary can also spawn its own siblings.
    static func augmentedPATH(
        base: String? = ProcessInfo.processInfo.environment["PATH"],
        home: String = NSHomeDirectory()
    ) -> String {
        let baseEntries = (base ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        var entries: [String] = []
        for entry in baseEntries + wellKnownDirectories(home: home) where !entry.isEmpty {
            if seen.insert(entry).inserted {
                entries.append(entry)
            }
        }
        return entries.joined(separator: ":")
    }

    /// Static resolution: pinned paths verify directly; bare names scan the
    /// augmented PATH. Returns an absolute path, or nil on miss.
    static func resolveStatically(
        _ command: String,
        path: String = augmentedPATH(),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        guard !command.isEmpty else { return nil }

        if command.contains("/") {
            let expanded = (command as NSString).expandingTildeInPath
            return isExecutable(expanded) ? expanded : nil
        }

        for directory in path.split(separator: ":").map(String.init) where !directory.isEmpty {
            let candidate = (directory as NSString).appendingPathComponent(command)
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Shells whose alias/function stripping syntax matches the script
    /// below. Anything else falls back to /bin/zsh (always present on macOS).
    private static let supportedLoginShells: Set<String> = ["zsh", "bash"]

    static func loginShell(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let shell = environment["SHELL"] ?? ""
        if supportedLoginShells.contains((shell as NSString).lastPathComponent) {
            return shell
        }
        return "/bin/zsh"
    }

    /// Bare command names only — anything shell-metacharacter-ish is
    /// excluded before interpolation into the resolve script.
    static func isSafeCommandName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    /// The script run inside `$SHELL -ilc`: per name, strip alias and shell
    /// function, resolve with POSIX `command -v`, keep only absolute paths,
    /// canonicalise the directory (`cd … && pwd -P`), and emit
    /// `<name>\t<canonical_path>` per line.
    static func loginShellResolveScript(names: [String]) -> String {
        names
            .filter(isSafeCommandName)
            .map { name in
                """
                unalias \(name) 2>/dev/null; unset -f \(name) 2>/dev/null; \
                p=$(command -v \(name) 2>/dev/null); case "$p" in /*) \
                d=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) && \
                printf '%s\\t%s/%s\\n' '\(name)' "$d" "$(basename "$p")";; esac
                """
            }
            .joined(separator: "\n")
    }

    static func parseLoginShellResolveOutput(
        _ output: String,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> [String: String] {
        var resolved: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = String(parts[0])
            let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
            // Reality check: the shell's answer must still be executable
            // from this process — a per-session multishell dir can vanish
            // between detection and execution.
            guard path.hasPrefix("/"), isExecutable(path) else { continue }
            resolved[name] = path
        }
        return resolved
    }

    /// Batch-resolves bare names via the user's interactive login shell.
    /// Spawning the login shell touches the user's rc files, so callers
    /// should invoke this once per batch and only after static misses.
    static func resolveViaLoginShell(
        names: [String],
        timeout: Duration = .seconds(8)
    ) async -> [String: String] {
        let safeNames = names.filter(isSafeCommandName)
        guard !safeNames.isEmpty else { return [:] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: loginShell())
        process.arguments = ["-ilc", loginShellResolveScript(names: safeNames)]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return [:]
        }

        let watchdog = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning {
                process.terminate()
            }
        }
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return [:] }
        let output = String(
            decoding: stdout.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        return parseLoginShellResolveOutput(output)
    }
}
