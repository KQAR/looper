import Foundation

/// Structured events from a Claude Code agent process running in
/// `--print --output-format stream-json --verbose` mode.
enum AgentEvent: Sendable, Equatable {
    case initialized(sessionID: String, model: String)
    case toolUse(name: String, inputSummary: String)
    case toolResult(isError: Bool)
    case text(String)
    case result(AgentResult)
}

struct AgentResult: Sendable, Equatable {
    var sessionID: String
    var isError: Bool
    var durationMs: Int
    var costUSD: Double
    var numTurns: Int
    var resultText: String
}
