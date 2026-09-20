import Foundation

/// Reads `~/.claude/sessions/<pid>.json`, the registry Claude Code keeps of running sessions.
public struct SessionRegistry: Sendable {
    public let directory: URL

    public init(claudeHome: URL = SessionRegistry.defaultClaudeHome) {
        directory = claudeHome.appendingPathComponent("sessions")
    }

    public static var defaultClaudeHome: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    /// Entries whose process is still alive, oldest first.
    public func liveEntries() -> [RegistryEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap(Self.parse)
            .filter { Self.isAlive(pid: $0.pid) }
            .sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    static func parse(_ data: Data) -> RegistryEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = object["pid"] as? Int,
              let sessionId = object["sessionId"] as? String
        else { return nil }
        let startedAt = (object["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return RegistryEntry(
            pid: Int32(pid),
            sessionId: sessionId,
            cwd: object["cwd"] as? String ?? "",
            name: object["name"] as? String,
            isBusy: object["status"] as? String == "busy",
            startedAt: startedAt,
            entrypoint: object["entrypoint"] as? String
        )
    }

    static func isAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
