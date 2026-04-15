import Foundation

enum AgentSDKMessageMapper {
    static func events(from message: SDKMessage) -> [AgentEvent] {
        switch message {
        case let .system(.initialize(event)):
            return [.initialized(sessionID: event.sessionId, model: event.model)]

        case let .assistant(message):
            return assistantEvents(from: message)

        case let .user(message):
            return userEvents(from: message)

        case let .result(result):
            return [.result(agentResult(from: result))]

        default:
            return []
        }
    }

    private static func assistantEvents(from message: SDKAssistantMessage) -> [AgentEvent] {
        guard let content = message.message["content"]?.arrayValue else { return [] }

        return content.compactMap { block in
            switch block["type"]?.stringValue {
            case "tool_use":
                let name = block["name"]?.stringValue ?? "unknown"
                let input = block["input"]?.objectValue ?? [:]
                return .toolUse(name: name, inputSummary: summarizeToolInput(name: name, input: input))

            case "text":
                guard let text = block["text"]?.stringValue,
                      !text.isEmpty
                else {
                    return nil
                }
                return .text(text)

            default:
                return nil
            }
        }
    }

    private static func userEvents(from message: SDKUserMessage) -> [AgentEvent] {
        if let toolUseResult = message.toolUseResult {
            return [.toolResult(isError: toolUseResult["is_error"]?.boolValue ?? false)]
        }

        guard let content = message.message["content"]?.arrayValue else { return [] }
        return content.compactMap { block in
            guard block["type"]?.stringValue == "tool_result" else { return nil }
            return .toolResult(isError: block["is_error"]?.boolValue ?? false)
        }
    }

    private static func agentResult(from result: SDKResultMessage) -> AgentResult {
        switch result {
        case let .success(success):
            return AgentResult(
                sessionID: success.sessionId,
                isError: success.isError,
                durationMs: success.durationMs,
                costUSD: success.totalCostUsd,
                numTurns: success.numTurns,
                resultText: success.result
            )

        case let .error(error):
            return AgentResult(
                sessionID: error.sessionId,
                isError: error.isError,
                durationMs: error.durationMs,
                costUSD: error.totalCostUsd,
                numTurns: error.numTurns,
                resultText: error.errors.joined(separator: "\n")
            )
        }
    }

    private static func summarizeToolInput(
        name: String,
        input: [String: AnyCodable]
    ) -> String {
        switch name {
        case "Read", "Edit", "Write":
            return input["file_path"]?.stringValue ?? ""

        case "Bash":
            return input["description"]?.stringValue
                ?? input["command"]?.stringValue.map { String($0.prefix(80)) }
                ?? ""

        case "Grep", "Glob":
            return input["pattern"]?.stringValue ?? ""

        case "WebFetch":
            return input["url"]?.stringValue ?? ""

        case "Agent":
            return input["description"]?.stringValue ?? ""

        default:
            return ""
        }
    }
}
