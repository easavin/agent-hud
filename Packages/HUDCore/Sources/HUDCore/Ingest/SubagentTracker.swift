import Foundation

/// Follows the transcripts under `<project>/<sessionId>/subagents/`.
struct SubagentTracker: Sendable {
    private struct Entry: Sendable {
        var info: SubagentInfo
        var tailer: TranscriptTailer
        var lastMessageId: String?
        var lastUsage = TokenUsage()
    }

    let directory: URL
    private var entries: [String: Entry] = [:]

    init(sessionTranscript: URL) {
        directory = sessionTranscript.deletingPathExtension().appendingPathComponent("subagents")
    }

    mutating func poll() -> [SubagentInfo] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "jsonl" {
            let id = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "agent-", with: "")
            if entries[id] == nil {
                let meta = Self.meta(url.deletingPathExtension().appendingPathExtension("meta.json"))
                entries[id] = Entry(info: SubagentInfo(id: id, toolUseId: meta["toolUseId"] ?? "", agentType: meta["agentType"] ?? "agent",
                                                       description: meta["description"] ?? ""),
                                    tailer: TranscriptTailer(url: url))
            }
            guard var entry = entries[id] else { continue }
            for event in entry.tailer.poll() { Self.apply(event, to: &entry) }
            entries[id] = entry
        }
        return entries.values.map(\.info).sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    private static func apply(_ event: TranscriptEvent, to entry: inout Entry) {
        if let date = event.timestamp {
            if entry.info.startedAt == nil { entry.info.startedAt = date }
            entry.info.lastEventAt = date
        }
        guard event.role == .assistant else { return }
        if let model = event.model, model != "<synthetic>" { entry.info.model = model }
        for case .toolUse in event.blocks { entry.info.toolCalls += 1 }
        if let turn = event.usage {
            let continuation = event.messageId != nil && event.messageId == entry.lastMessageId
            entry.info.usage = entry.info.usage + (turn - (continuation ? entry.lastUsage : TokenUsage()))
            entry.lastMessageId = event.messageId
            entry.lastUsage = turn
        }
        entry.info.finished = event.stopReason == "end_turn"
    }

    private static func meta(_ url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.compactMapValues { $0 as? String }
    }
}
