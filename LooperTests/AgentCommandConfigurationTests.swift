import XCTest

@testable import Looper

final class AgentCommandConfigurationTests: XCTestCase {
    func testDefaultCommandUsesBypassPermissions() {
        let request = AgentProcessRequest(
            runID: UUID(),
            workingDirectory: "/tmp/demo",
            taskDescription: "Fix the bug",
            agentCommand: "claude",
            resumeSessionID: nil
        )

        let configuration = AgentCommandConfiguration(
            request: request,
            environment: ["PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(configuration.executableDescription, "claude")
        XCTAssertEqual(configuration.options.cwd, "/tmp/demo")
        XCTAssertEqual(configuration.options.permissionMode, .bypassPermissions)
        XCTAssertEqual(configuration.options.allowDangerouslySkipPermissions, true)
        XCTAssertNil(configuration.options.pathToClaudeCodeExecutable)
        XCTAssertTrue(configuration.ignoredArguments.isEmpty)
    }

    func testParsesCommonFlagsAndPreservesUnknownLongFlags() {
        let request = AgentProcessRequest(
            runID: UUID(),
            workingDirectory: "/tmp/demo",
            taskDescription: "Fix the bug",
            agentCommand: #"claude --model claude-opus-4-1 --max-turns 7 --append-system-prompt "Be terse" --allowed-tools Read Grep --resume stale-session --debug --custom-flag custom-value -- ignored prompt"#,
            resumeSessionID: "fresh-session"
        )

        let configuration = AgentCommandConfiguration(
            request: request,
            environment: ["PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(configuration.options.model, "claude-opus-4-1")
        XCTAssertEqual(configuration.options.maxTurns, 7)
        XCTAssertEqual(configuration.options.allowedTools, ["Read", "Grep"])
        XCTAssertEqual(configuration.options.resume, "fresh-session")
        XCTAssertEqual(configuration.options.debug, true)
        XCTAssertEqual(configuration.options.extraArgs?["custom-flag"] ?? nil, "custom-value")

        if case let .presetWithAppend(prompt)? = configuration.options.systemPrompt {
            XCTAssertEqual(prompt, "Be terse")
        } else {
            XCTFail("Expected appended system prompt")
        }

        XCTAssertEqual(configuration.ignoredArguments, ["ignored", "prompt"])
    }

    func testResolvesExplicitExecutablePath() {
        let request = AgentProcessRequest(
            runID: UUID(),
            workingDirectory: "/tmp/demo",
            taskDescription: "Fix the bug",
            agentCommand: #""/Applications/Claude Code.app/Contents/MacOS/claude" --model claude-sonnet-4-6"#,
            resumeSessionID: nil
        )

        let configuration = AgentCommandConfiguration(
            request: request,
            environment: ["PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(configuration.executableDescription, "/Applications/Claude Code.app/Contents/MacOS/claude")
        XCTAssertEqual(
            configuration.options.pathToClaudeCodeExecutable,
            "/Applications/Claude Code.app/Contents/MacOS/claude"
        )
        XCTAssertEqual(configuration.options.model, "claude-sonnet-4-6")
    }
}
