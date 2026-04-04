import Foundation

/// Parses Claude Code `--output-format stream-json` JSONL lines into `AgentEvent`s.
enum AgentStreamParser {
    static func parse(_ line: String) -> AgentEvent? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return nil }

        switch type {
        case "system":
            return parseSystem(json)
        case "assistant":
            return parseAssistant(json)
        case "user":
            return parseUser(json)
        case "result":
            return parseResult(json)
        default:
            return nil
        }
    }

    // MARK: - System

    private static func parseSystem(_ json: [String: Any]) -> AgentEvent? {
        guard let subtype = json["subtype"] as? String, subtype == "init" else { return nil }
        let sessionID = json["session_id"] as? String ?? ""
        let model = json["model"] as? String ?? ""
        return .initialized(sessionID: sessionID, model: model)
    }

    // MARK: - Assistant

    private static func parseAssistant(_ json: [String: Any]) -> AgentEvent? {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]],
              let first = content.first,
              let contentType = first["type"] as? String
        else { return nil }

        switch contentType {
        case "tool_use":
            let name = first["name"] as? String ?? "unknown"
            let input = first["input"] as? [String: Any] ?? [:]
            return .toolUse(name: name, inputSummary: summarizeToolInput(name: name, input: input))
        case "text":
            let text = first["text"] as? String ?? ""
            return text.isEmpty ? nil : .text(text)
        default:
            return nil
        }
    }

    // MARK: - User (tool results)

    private static func parseUser(_ json: [String: Any]) -> AgentEvent? {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]],
              let first = content.first,
              first["type"] as? String == "tool_result"
        else { return nil }

        let isError = first["is_error"] as? Bool ?? false
        return .toolResult(isError: isError)
    }

    // MARK: - Result

    private static func parseResult(_ json: [String: Any]) -> AgentEvent? {
        .result(AgentResult(
            sessionID: json["session_id"] as? String ?? "",
            isError: json["is_error"] as? Bool ?? false,
            durationMs: json["duration_ms"] as? Int ?? 0,
            costUSD: json["total_cost_usd"] as? Double ?? 0,
            numTurns: json["num_turns"] as? Int ?? 0,
            resultText: json["result"] as? String ?? ""
        ))
    }

    // MARK: - Tool input summarization

    private static func summarizeToolInput(name: String, input: [String: Any]) -> String {
        switch name {
        case "Read", "Edit", "Write":
            return input["file_path"] as? String ?? ""
        case "Bash":
            return input["description"] as? String
                ?? (input["command"] as? String).map { String($0.prefix(80)) }
                ?? ""
        case "Grep":
            return input["pattern"] as? String ?? ""
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "WebFetch":
            return input["url"] as? String ?? ""
        case "Agent":
            return input["description"] as? String ?? ""
        default:
            return ""
        }
    }
}
