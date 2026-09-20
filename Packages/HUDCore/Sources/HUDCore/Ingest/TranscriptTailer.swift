import Foundation

/// Reads a growing JSONL file incrementally: each `poll()` returns only the events
/// appended since the previous call.
public struct TranscriptTailer: Sendable {
    public let url: URL
    public private(set) var offset: UInt64 = 0
    /// Bytes of a trailing line that had not been terminated yet.
    private var partial = Data()

    public init(url: URL) { self.url = url }

    public mutating func poll() -> [TranscriptEvent] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            // Truncated or replaced: start over.
            offset = 0
            partial.removeAll()
        }
        guard size > offset, (try? handle.seek(toOffset: offset)) != nil,
              let chunk = try? handle.readToEnd(), !chunk.isEmpty
        else { return [] }
        offset += UInt64(chunk.count)

        var buffer = partial + chunk
        var events: [TranscriptEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            if let event = TranscriptParser.parse(line: buffer[buffer.startIndex..<newline]) { events.append(event) }
            buffer = buffer[buffer.index(after: newline)...]
        }
        partial = Data(buffer)
        return events
    }
}
