import Foundation

/// A single line of a Claude Code transcript (`~/.claude/projects/<slug>/<session>.jsonl`),
/// reduced to the fields the HUD cares about. Parsing is deliberately lenient: the
/// format is undocumented and gains fields between CLI versions.
public struct TranscriptEvent: Sendable, Equatable {
    public enum Role: Sendable, Equatable { case assistant, user, title, other }

    public enum Block: Sendable, Equatable {
        case thinking(String)
        case text(String)
        case toolUse(ToolCall)
        case toolResult(toolUseId: String, isError: Bool, chars: Int, errorText: String?)
    }

    /// Change to the agent's task list carried by a TaskCreate / TaskUpdate / TodoWrite call.
    public enum PlanOp: Sendable, Equatable {
        case create(subject: String)
        case update(taskId: String, status: String)
        case replace([PlanStep])
    }

    public struct ToolCall: Sendable, Equatable {
        public var id: String
        public var name: String
        /// Human-readable one-liner (the tool's description if it has one).
        public var summary: String
        /// What the call acts on: the command, file path, pattern or URL.
        public var target: String
        public var inputChars = 0
        public var linesAdded = 0
        public var linesRemoved = 0
        public var planOp: PlanOp?
    }

    public var role: Role
    public var uuid: String?
    public var timestamp: Date?
    public var isSidechain = false
    public var gitBranch: String?
    public var cwd: String?
    public var title: String?
    public var messageId: String?
    public var model: String?
    public var usage: TokenUsage?
    public var stopReason: String?
    public var blocks: [Block] = []

    /// True for a user line typed by a human (not a tool result being fed back).
    public var isUserPrompt: Bool {
        guard role == .user else { return false }
        return !blocks.contains { if case .toolResult = $0 { true } else { false } }
    }
}

public enum TranscriptParser {
    public static func parse(line: Data) -> TranscriptEvent? {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }

        var event = TranscriptEvent(role: .other)
        event.uuid = object["uuid"] as? String
        event.isSidechain = object["isSidechain"] as? Bool ?? false
        event.gitBranch = object["gitBranch"] as? String
        event.cwd = object["cwd"] as? String
        if let stamp = object["timestamp"] as? String { event.timestamp = parseDate(stamp) }

        switch type {
        case "assistant": event.role = .assistant
        case "user": event.role = .user
        case "custom-title":
            event.role = .title
            event.title = object["customTitle"] as? String
            return event
        default:
            return event
        }

        guard let message = object["message"] as? [String: Any] else { return event }
        event.messageId = message["id"] as? String
        event.model = message["model"] as? String
        event.stopReason = message["stop_reason"] as? String
        if let usage = message["usage"] as? [String: Any] { event.usage = parseUsage(usage) }

        if let text = message["content"] as? String {
            event.blocks = [.text(text)]
        } else if let content = message["content"] as? [[String: Any]] {
            event.blocks = content.compactMap(parseBlock)
        }
        return event
    }

    static func parseUsage(_ usage: [String: Any]) -> TokenUsage {
        let details = usage["output_tokens_details"] as? [String: Any]
        let creation = usage["cache_creation"] as? [String: Any]
        return TokenUsage(
            input: usage["input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0,
            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
            cacheCreation: usage["cache_creation_input_tokens"] as? Int ?? 0,
            thinking: details?["thinking_tokens"] as? Int ?? 0,
            cacheCreation1h: creation?["ephemeral_1h_input_tokens"] as? Int ?? 0
        )
    }

    static func parseBlock(_ block: [String: Any]) -> TranscriptEvent.Block? {
        switch block["type"] as? String {
        case "thinking":
            return .thinking(block["thinking"] as? String ?? "")
        case "text":
            return .text(block["text"] as? String ?? "")
        case "tool_use":
            return .toolUse(parseToolCall(block))
        case "tool_result":
            let isError = block["is_error"] as? Bool ?? false
            let text = resultText(block["content"])
            return .toolResult(toolUseId: block["tool_use_id"] as? String ?? "", isError: isError,
                               chars: text.count, errorText: isError ? snippet(text, limit: 200) : nil)
        default:
            return nil
        }
    }

    static func parseToolCall(_ block: [String: Any]) -> TranscriptEvent.ToolCall {
        let name = block["name"] as? String ?? "?"
        let input = block["input"] as? [String: Any] ?? [:]
        var call = TranscriptEvent.ToolCall(id: block["id"] as? String ?? "", name: name,
                                            summary: summarize(tool: name, input: input), target: target(input: input))
        call.inputChars = input.values.reduce(0) { $0 + (($1 as? String)?.count ?? 8) }
        let old = lineCount(input["old_string"]), new = lineCount(input["new_string"]) + lineCount(input["content"])
        if name == "Edit" || name == "Write" || name == "MultiEdit" || name == "NotebookEdit" {
            call.linesAdded = new
            call.linesRemoved = old
        }
        switch name {
        case "TaskCreate":
            call.planOp = .create(subject: input["subject"] as? String ?? "task")
        case "TaskUpdate":
            if let id = input["taskId"] as? String, let status = input["status"] as? String {
                call.planOp = .update(taskId: id, status: status)
            }
        case "TodoWrite":
            let todos = input["todos"] as? [[String: Any]] ?? []
            call.planOp = .replace(todos.map {
                PlanStep(title: $0["content"] as? String ?? "", status: PlanStep.Status(raw: $0["status"] as? String))
            })
        default: break
        }
        return call
    }

    static func lineCount(_ value: Any?) -> Int {
        guard let text = value as? String, !text.isEmpty else { return 0 }
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    static func resultText(_ content: Any?) -> String {
        if let text = content as? String { return text }
        let parts = content as? [[String: Any]] ?? []
        return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    static func target(input: [String: Any]) -> String {
        let keys = ["command", "file_path", "notebook_path", "pattern", "query", "url", "description", "prompt"]
        guard let key = keys.first(where: { input[$0] is String }), let value = input[key] as? String else { return "" }
        return snippet(value, limit: 200)
    }

    /// A short human-readable description of what a tool call is touching.
    static func summarize(tool: String, input: [String: Any]) -> String {
        let keys = ["description", "command", "file_path", "notebook_path", "pattern", "query", "url", "prompt", "skill"]
        guard let key = keys.first(where: { input[$0] is String }), var value = input[key] as? String else { return "" }
        if key == "file_path" || key == "notebook_path" { value = (value as NSString).lastPathComponent }
        return snippet(value, limit: 120)
    }

    public static func snippet(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count <= limit ? flat : String(flat.prefix(limit - 1)) + "…"
    }

    static func parseDate(_ string: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string))
            ?? (try? Date.ISO8601FormatStyle().parse(string))
    }
}
