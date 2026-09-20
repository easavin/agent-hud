import Foundation

/// Finds files under a session's working directory that changed since the session started.
/// This is what catches work done through the shell (heredocs, sed, generators, formatters),
/// which never shows up as an Edit or Write call in the transcript.
public enum DirectoryScanner {
    public struct Hit: Sendable, Equatable {
        public var modified: Date
        public var created: Bool
    }

    /// Build output, dependencies and caches: huge, noisy, and never what the agent "worked on".
    static let skippedDirectories: Set<String> = [
        "node_modules", "build", "dist", "DerivedData", "Pods", "target", "venv", "__pycache__", "vendor", "out", "coverage",
    ]

    public static func changedFiles(in root: String, since: Date, until: Date = .distantFuture, entryLimit: Int = 30_000, hitLimit: Int = 400) -> [String: Hit] {
        // Never crawl a home directory or a volume root.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard root != home, root.split(separator: "/").count >= 3 else { return [:] }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .creationDateKey]
        guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [:] }

        var hits: [String: Hit] = [:]
        var seen = 0
        for case let url as URL in walker {
            seen += 1
            if seen > entryLimit || hits.count >= hitLimit { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if skippedDirectories.contains(url.lastPathComponent) || url.pathExtension == "xcodeproj" { walker.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, let modified = values.contentModificationDate, modified >= since, modified <= until else { continue }
            hits[url.path] = Hit(modified: modified, created: (values.creationDate ?? .distantPast) >= since)
        }
        return hits
    }
}
