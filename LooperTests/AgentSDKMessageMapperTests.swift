import XCTest

@testable import Looper

final class AgentSDKMessageMapperTests: XCTestCase {
    func testMapsSystemInit() throws {
        let message = try decodeMessage(
            #"{"type":"system","subtype":"init","agents":[],"api_key_source":"oauth","betas":[],"claude_code_version":"2.1.81","cwd":"/tmp/demo","tools":["Bash","Read"],"mcp_servers":[],"model":"claude-sonnet-4-6","permission_mode":"default","slash_commands":[],"output_style":"normal","skills":[],"plugins":[],"fast_mode_state":"off","uuid":"11111111-1111-1111-1111-111111111111","session_id":"session-123"}"#
        )

        XCTAssertEqual(
            AgentSDKMessageMapper.events(from: message),
            [.initialized(sessionID: "session-123", model: "claude-sonnet-4-6")]
        )
    }

    func testMapsAssistantToolUseAndTextBlocks() throws {
        let message = try decodeMessage(
            #"{"type":"assistant","message":{"id":"msg-1","type":"message","role":"assistant","content":[{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"/tmp/main.swift"}},{"type":"text","text":"Working on it"}],"model":"claude-sonnet-4-6","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":12}},"parent_tool_use_id":null,"uuid":"22222222-2222-2222-2222-222222222222","session_id":"session-123"}"#
        )

        XCTAssertEqual(
            AgentSDKMessageMapper.events(from: message),
            [
                .toolUse(name: "Read", inputSummary: "/tmp/main.swift"),
                .text("Working on it"),
            ]
        )
    }

    func testMapsToolResultMessage() throws {
        let message = try decodeMessage(
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool-1","content":"ok","is_error":true}]},"parent_tool_use_id":"tool-1","is_synthetic":true,"tool_use_result":{"type":"tool_result","tool_use_id":"tool-1","content":"ok","is_error":true},"priority":"now","timestamp":"2026-04-15T00:00:00Z","uuid":"33333333-3333-3333-3333-333333333333","session_id":"session-123"}"#
        )

        XCTAssertEqual(
            AgentSDKMessageMapper.events(from: message),
            [.toolResult(isError: true)]
        )
    }

    func testMapsErrorResult() throws {
        let message = try decodeMessage(
            #"{"type":"result","subtype":"error_during_execution","duration_ms":500,"duration_api_ms":400,"is_error":true,"num_turns":1,"stop_reason":null,"session_id":"session-123","total_cost_usd":0.01,"usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}},"model_usage":{},"permission_denials":[],"errors":["first","second"],"fast_mode_state":"off","uuid":"44444444-4444-4444-4444-444444444444"}"#
        )

        XCTAssertEqual(
            AgentSDKMessageMapper.events(from: message),
            [
                .result(
                    AgentResult(
                        sessionID: "session-123",
                        isError: true,
                        durationMs: 500,
                        costUSD: 0.01,
                        numTurns: 1,
                        resultText: "first\nsecond"
                    )
                ),
            ]
        )
    }

    private func decodeMessage(_ json: String) throws -> SDKMessage {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SDKMessage.self, from: Data(json.utf8))
    }
}
