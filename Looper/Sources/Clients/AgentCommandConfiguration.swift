import Foundation

struct AgentCommandConfiguration: Sendable {
    var options: Options
    var executableDescription: String
    var ignoredArguments: [String]

    init(
        request: AgentProcessRequest,
        environment: [String: String] = AgentCommandConfiguration.defaultEnvironment()
    ) {
        let tokens = ShellWords.split(request.agentCommand)
        let executableToken = tokens.first
        let executablePath = Self.resolveExecutablePath(from: executableToken, environment: environment)
        let parsed = ParsedArguments(
            tokens: Array(tokens.dropFirst()),
            resumeSessionID: request.resumeSessionID
        )

        self.options = parsed.options(
            cwd: request.workingDirectory,
            environment: environment,
            executablePath: executablePath
        )
        self.executableDescription = executableToken ?? "claude"
        self.ignoredArguments = parsed.ignoredArguments
    }

    private static func resolveExecutablePath(
        from executableToken: String?,
        environment: [String: String]
    ) -> String? {
        guard let executableToken,
              !executableToken.isEmpty,
              executableToken != "claude"
        else {
            return nil
        }

        if executableToken.contains("/") {
            return executableToken
        }

        let searchPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path, isDirectory: true)
                .appendingPathComponent(executableToken, isDirectory: false)
                .path(percentEncoded: false)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return executableToken
    }

    static func defaultEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin", "\(NSHomeDirectory())/.local/bin"]
        let currentPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let missingPaths = extraPaths.filter { !currentPath.contains($0) }
        if !missingPaths.isEmpty {
            environment["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
        }
        return environment
    }
}

private struct ParsedArguments: Sendable {
    var model: String?
    var systemPrompt: SystemPrompt?
    var permissionMode: PermissionMode?
    var allowDangerouslySkipPermissions = true
    var tools: ToolsConfig?
    var allowedTools: [String]?
    var disallowedTools: [String]?
    var additionalDirectories: [String]?
    var maxTurns: Int?
    var maxBudgetUsd: Double?
    var effort: Effort?
    var includePartialMessages: Bool?
    var resume: String?
    var continueSession: Bool?
    var forkSession: Bool?
    var agent: String?
    var debug: Bool?
    var debugFile: String?
    var fallbackModel: String?
    var extraArgs: [String: String?] = [:]
    var persistSession: Bool?
    var betas: [String]?
    var ignoredArguments: [String] = []

    init(tokens: [String], resumeSessionID: String?) {
        resume = resumeSessionID

        var index = 0
        while index < tokens.count {
            let token = tokens[index]

            switch token {
            case "-p", "--print", "--verbose":
                break

            case "--dangerously-skip-permissions":
                allowDangerouslySkipPermissions = true
                permissionMode = .bypassPermissions

            case "--continue":
                continueSession = true

            case "--fork-session":
                forkSession = true

            case "--debug":
                debug = true

            case "--include-partial-messages":
                includePartialMessages = true

            case "--no-session-persistence":
                persistSession = false

            case "--model":
                model = consumeValue(tokens, &index)

            case "--permission-mode":
                if let rawValue = consumeValue(tokens, &index),
                   let parsedMode = PermissionMode(rawValue: rawValue)
                {
                    permissionMode = parsedMode
                    allowDangerouslySkipPermissions = parsedMode == .bypassPermissions
                }

            case "--allowed-tools":
                allowedTools = consumeValues(tokens, &index)

            case "--disallowed-tools":
                disallowedTools = consumeValues(tokens, &index)

            case "--tools":
                let values = consumeValues(tokens, &index)
                if !values.isEmpty {
                    tools = .specific(values)
                }

            case "--add-dir":
                additionalDirectories = consumeValues(tokens, &index)

            case "--max-turns":
                if let rawValue = consumeValue(tokens, &index),
                   let parsedValue = Int(rawValue)
                {
                    maxTurns = parsedValue
                }

            case "--max-budget-usd":
                if let rawValue = consumeValue(tokens, &index),
                   let parsedValue = Double(rawValue)
                {
                    maxBudgetUsd = parsedValue
                }

            case "--effort":
                if let rawValue = consumeValue(tokens, &index),
                   let parsedValue = Effort(rawValue: rawValue)
                {
                    effort = parsedValue
                }

            case "--resume":
                if resume == nil {
                    resume = consumeValue(tokens, &index)
                } else {
                    _ = consumeValue(tokens, &index)
                }

            case "--system-prompt":
                if let prompt = consumeValue(tokens, &index) {
                    systemPrompt = .custom(prompt)
                }

            case "--append-system-prompt":
                if let prompt = consumeValue(tokens, &index) {
                    systemPrompt = .presetWithAppend(prompt)
                }

            case "--debug-file":
                debugFile = consumeValue(tokens, &index)

            case "--fallback-model":
                fallbackModel = consumeValue(tokens, &index)

            case "--agent":
                agent = consumeValue(tokens, &index)

            case "--betas":
                betas = consumeValues(tokens, &index)

            case "--output-format", "--input-format":
                _ = consumeValue(tokens, &index)

            case "--":
                let remainingIndex = tokens.index(after: index)
                if remainingIndex < tokens.endIndex {
                    ignoredArguments.append(contentsOf: tokens[remainingIndex...])
                }
                index = tokens.count
                continue

            default:
                parseUnknown(token: token, tokens: tokens, index: &index)
            }

            index += 1
        }

        if permissionMode == nil {
            permissionMode = .bypassPermissions
        }
    }

    func options(
        cwd: String,
        environment: [String: String],
        executablePath: String?
    ) -> Options {
        Options(
            model: model,
            cwd: cwd,
            systemPrompt: systemPrompt,
            permissionMode: permissionMode,
            allowDangerouslySkipPermissions: allowDangerouslySkipPermissions,
            tools: tools,
            allowedTools: allowedTools,
            disallowedTools: disallowedTools,
            additionalDirectories: additionalDirectories,
            maxTurns: maxTurns,
            maxBudgetUsd: maxBudgetUsd,
            effort: effort,
            includePartialMessages: includePartialMessages,
            resume: resume,
            continueSession: continueSession,
            forkSession: forkSession,
            agent: agent,
            env: environment,
            debug: debug,
            debugFile: debugFile,
            pathToClaudeCodeExecutable: executablePath,
            fallbackModel: fallbackModel,
            extraArgs: extraArgs.isEmpty ? nil : extraArgs,
            persistSession: persistSession,
            betas: betas
        )
    }

    private mutating func parseUnknown(
        token: String,
        tokens: [String],
        index: inout Int
    ) {
        if let separator = token.firstIndex(of: "="),
           token.starts(with: "--")
        {
            let key = String(token[token.index(after: token.startIndex)..<separator])
            let value = String(token[token.index(after: separator)...])
            extraArgs[key] = value
            return
        }

        guard token.starts(with: "--") else {
            ignoredArguments.append(token)
            return
        }

        let key = String(token.dropFirst(2))
        let nextIndex = index + 1
        if nextIndex < tokens.count,
           !tokens[nextIndex].starts(with: "-")
        {
            extraArgs[key] = tokens[nextIndex]
            index = nextIndex
        } else {
            extraArgs[key] = nil
        }
    }

    private func consumeValue(_ tokens: [String], _ index: inout Int) -> String? {
        let nextIndex = index + 1
        guard nextIndex < tokens.count else { return nil }
        index = nextIndex
        return tokens[nextIndex]
    }

    private func consumeValues(_ tokens: [String], _ index: inout Int) -> [String] {
        var values: [String] = []
        var nextIndex = index + 1

        while nextIndex < tokens.count, !tokens[nextIndex].starts(with: "-") {
            values.append(tokens[nextIndex])
            nextIndex += 1
        }

        if !values.isEmpty {
            index = nextIndex - 1
        }

        return values
    }
}

private enum ShellWords {
    static func split(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for character in command {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\", quote != "'" {
                isEscaping = true
                continue
            }

            if let activeQuote = quote, character == activeQuote {
                quote = nil
                continue
            }

            if quote == nil, character == "\"" || character == "'" {
                quote = character
                continue
            }

            if quote == nil, character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        if isEscaping {
            current.append("\\")
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
