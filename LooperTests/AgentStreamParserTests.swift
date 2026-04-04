import XCTest

@testable import Looper

final class AgentStreamParserTests: XCTestCase {
    func testParseSystemInit() {
        let line = """
        {"type":"system","subtype":"init","session_id":"abc-123","model":"claude-opus-4-6","tools":["Bash","Read"]}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .initialized(sessionID: "abc-123", model: "claude-opus-4-6"))
    }

    func testParseSystemNonInitIsIgnored() {
        let line = """
        {"type":"system","subtype":"hook_started","hook_id":"xyz"}
        """
        XCTAssertNil(AgentStreamParser.parse(line))
    }

    func testParseToolUse() {
        let line = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"/src/main.swift"}}]}}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .toolUse(name: "Read", inputSummary: "/src/main.swift"))
    }

    func testParseToolUseBashWithDescription() {
        let line = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-2","name":"Bash","input":{"command":"ls -la","description":"List files"}}]}}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .toolUse(name: "Bash", inputSummary: "List files"))
    }

    func testParseToolUseBashFallsBackToCommand() {
        let line = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-3","name":"Bash","input":{"command":"git status"}}]}}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .toolUse(name: "Bash", inputSummary: "git status"))
    }

    func testParseToolUseUnknownToolHasEmptySummary() {
        let line = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-4","name":"CustomMCP","input":{"key":"value"}}]}}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .toolUse(name: "CustomMCP", inputSummary: ""))
    }

    func testParseText() {
        let line = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"I'll fix the bug now."}]}}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .text("I'll fix the bug now."))
    }

    func testParseEmptyTextIsIgnored() {
        let line = """
        {"type":"assistant","message":{"content":[{"type":"text","text":""}]}}
        """
        XCTAssertNil(AgentStreamParser.parse(line))
    }

    func testParseToolResult() {
        let line = """
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"tool-1","type":"tool_result","content":"file contents","is_error":false}]}}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .toolResult(isError: false))
    }

    func testParseToolResultWithError() {
        let line = """
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"tool-1","type":"tool_result","content":"not found","is_error":true}]}}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .toolResult(isError: true))
    }

    func testParseResultSuccess() {
        let line = """
        {"type":"result","subtype":"success","is_error":false,"duration_ms":12345,"total_cost_usd":0.05,"num_turns":3,"result":"Done!","session_id":"sess-456"}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .result(AgentResult(
            sessionID: "sess-456",
            isError: false,
            durationMs: 12345,
            costUSD: 0.05,
            numTurns: 3,
            resultText: "Done!"
        )))
    }

    func testParseResultFailure() {
        let line = """
        {"type":"result","subtype":"error","is_error":true,"duration_ms":500,"total_cost_usd":0.01,"num_turns":1,"result":"Out of tokens","session_id":"sess-789"}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .result(AgentResult(
            sessionID: "sess-789",
            isError: true,
            durationMs: 500,
            costUSD: 0.01,
            numTurns: 1,
            resultText: "Out of tokens"
        )))
    }

    func testParseInvalidJSONReturnsNil() {
        XCTAssertNil(AgentStreamParser.parse("not json"))
        XCTAssertNil(AgentStreamParser.parse(""))
        XCTAssertNil(AgentStreamParser.parse("{invalid"))
    }

    func testParseUnknownTypeReturnsNil() {
        let line = """
        {"type":"unknown","data":"something"}
        """
        XCTAssertNil(AgentStreamParser.parse(line))
    }

    func testParseGrepToolUse() {
        let line = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-5","name":"Grep","input":{"pattern":"TODO","path":"/src"}}]}}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .toolUse(name: "Grep", inputSummary: "TODO"))
    }

    func testParseAgentToolUse() {
        let line = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-6","name":"Agent","input":{"description":"Search for tests","prompt":"Find all test files"}}]}}
        """
        let event = AgentStreamParser.parse(line)
        XCTAssertEqual(event, .toolUse(name: "Agent", inputSummary: "Search for tests"))
    }
}
