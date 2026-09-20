import Foundation

public struct BurnPoint: Sendable, Equatable {
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var thinking = 0
}

public enum BurnRange: String, Sendable, CaseIterable {
    case hour = "1h", day = "24h", week = "7d"

    /// (number of points, seconds per point)
    var shape: (points: Int, step: Int) {
        switch self {
        case .hour: (30, 120)
        case .day: (24, 3600)
        case .week: (28, 6 * 3600)
        }
    }
}

/// Aggregates over every transcript on disk, ready for the stats rail.
public struct StatsSnapshot: Sendable, Equatable {
    public var burn: [BurnRange: [BurnPoint]] = [:]
    public var modelMix: [(model: String, share: Double)] = []
    public var cacheRead = 0
    public var cacheDenominator = 0
    public var costToday = 0.0
    public var costLastHour = 0.0
    public var tokensToday = 0
    public var errorsToday = 0
    public var tools: [(name: String, count: Int)] = []
    public var repos: [(name: String, tokens: Int, model: String)] = []
    /// 12 weeks × 7 days, oldest week first, Monday first; 0…1, nil for days in the future.
    public var heatmap: [[Double?]] = []
    public var isBackfilling = true

    public var cacheHitRate: Double { cacheDenominator == 0 ? 0 : Double(cacheRead) / Double(cacheDenominator) }

    public init() {}

    public static func == (a: StatsSnapshot, b: StatsSnapshot) -> Bool {
        a.tokensToday == b.tokensToday && a.errorsToday == b.errorsToday && a.isBackfilling == b.isBackfilling
            && a.burn == b.burn && a.costToday == b.costToday
    }
}

/// Incrementally indexes `~/.claude/projects/**/*.jsonl` into small time buckets.
/// Each pass only reads bytes appended since the last one; cursors and buckets persist between launches.
public actor HistoryIndex {
    static let slotSeconds = 120
    static let slotRetention = 8 * 86_400
    static let dayRetention = 100

    struct Cursor: Codable {
        var offset: UInt64 = 0
        var lastMessageId: String?
        var lastUsage = TokenUsage()
        /// Where the session started; later `cd`s must not split one repo into several.
        var repo: String?
    }

    struct Day: Codable {
        var models: [String: TokenUsage] = [:]
        var tools: [String: Int] = [:]
        var repos: [String: Int] = [:]
        var repoModels: [String: String] = [:]
        var errors = 0
    }

    struct Store: Codable {
        var version = 2
        var cursors: [String: Cursor] = [:]
        /// 2-minute slots keyed by `epoch / slotSeconds`, with the cost accrued in each.
        var slots: [Int: TokenUsage] = [:]
        var slotCost: [Int: Double] = [:]
        var days: [Int: Day] = [:]
    }

    private let projectsDirectory: URL
    private let storeURL: URL
    private var store = Store()
    private var loaded = false
    private var backfilled = false
    private let zoneOffset = TimeInterval(TimeZone.current.secondsFromGMT())

    public init(claudeHome: URL = SessionRegistry.defaultClaudeHome, storeURL: URL? = nil) {
        projectsDirectory = claudeHome.appendingPathComponent("projects")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.storeURL = storeURL ?? support.appendingPathComponent("AgentHUD/index.json")
    }

    /// Reads whatever is new on disk. The first call walks the whole history and can take a few seconds.
    public func refresh(now: Date = Date()) -> StatsSnapshot {
        load()
        var changed = false
        for url in transcriptFiles() where ingest(url) { changed = true }
        if changed || !backfilled {
            prune(now: now)
            save()
        }
        backfilled = true
        return snapshot(now: now)
    }

    // MARK: Ingest

    private func transcriptFiles() -> [URL] {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: projectsDirectory, includingPropertiesForKeys: keys) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { url in
            guard url.pathExtension == "jsonl" else { return false }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return UInt64(size) != store.cursors[url.path]?.offset
        }
    }

    private func ingest(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        var cursor = store.cursors[url.path] ?? Cursor()
        let size = (try? handle.seekToEnd()) ?? 0
        if size < cursor.offset { cursor = Cursor() }
        guard size > cursor.offset, (try? handle.seek(toOffset: cursor.offset)) != nil,
              let chunk = try? handle.readToEnd(), let lastNewline = chunk.lastIndex(of: 0x0A)
        else { return false }

        let assistantMarker = Data(#""type":"assistant""#.utf8), errorMarker = Data(#""is_error":true"#.utf8)
        var start = chunk.startIndex
        while start <= lastNewline, let newline = chunk[start...].firstIndex(of: 0x0A) {
            let line = chunk[start..<newline]
            start = chunk.index(after: newline)
            // Parsing JSON is the expensive part; most lines carry nothing we aggregate.
            guard line.range(of: assistantMarker) != nil || line.range(of: errorMarker) != nil,
                  let event = TranscriptParser.parse(line: line), let date = event.timestamp
            else { continue }
            record(event, at: date, cursor: &cursor)
        }
        // Only consume complete lines; a partial tail is re-read next time.
        cursor.offset += UInt64(chunk.distance(from: chunk.startIndex, to: lastNewline) + 1)
        store.cursors[url.path] = cursor
        return true
    }

    private func record(_ event: TranscriptEvent, at date: Date, cursor: inout Cursor) {
        let dayKey = Int((date.timeIntervalSince1970 + zoneOffset) / 86_400)
        var day = store.days[dayKey] ?? Day()
        defer { store.days[dayKey] = day }

        if event.role == .user {
            for case .toolResult(_, true, _, _) in event.blocks { day.errors += 1 }
            return
        }
        guard event.role == .assistant, let model = event.model, model != "<synthetic>" else { return }
        for case .toolUse(let call) in event.blocks { day.tools[SessionState.displayName(call.name), default: 0] += 1 }

        guard let turn = event.usage else { return }
        let isContinuation = event.messageId != nil && event.messageId == cursor.lastMessageId
        let delta = turn - (isContinuation ? cursor.lastUsage : TokenUsage())
        cursor.lastMessageId = event.messageId
        cursor.lastUsage = turn
        guard delta != TokenUsage() else { return }

        day.models[model] = (day.models[model] ?? TokenUsage()) + delta
        if cursor.repo == nil { cursor.repo = event.cwd.map { ($0 as NSString).lastPathComponent } }
        if let repo = cursor.repo, !repo.isEmpty {
            day.repos[repo, default: 0] += delta.total
            day.repoModels[repo] = model
        }
        let slot = Int(date.timeIntervalSince1970) / Self.slotSeconds
        store.slots[slot] = (store.slots[slot] ?? TokenUsage()) + delta
        store.slotCost[slot, default: 0] += CostEstimator.cost(of: delta, model: model)
    }

    // MARK: Query

    private func snapshot(now: Date) -> StatsSnapshot {
        var stats = StatsSnapshot()
        stats.isBackfilling = false
        let nowSeconds = Int(now.timeIntervalSince1970)

        for range in BurnRange.allCases {
            let (count, step) = range.shape
            let end = (nowSeconds / step + 1) * step
            var points = [BurnPoint](repeating: BurnPoint(), count: count)
            for (slot, usage) in store.slots {
                let index = count - 1 - (end - 1 - slot * Self.slotSeconds) / step
                guard points.indices.contains(index), slot * Self.slotSeconds < end else { continue }
                points[index].input += usage.input + usage.cacheCreation
                points[index].output += max(0, usage.output - usage.thinking)
                points[index].cacheRead += usage.cacheRead
                points[index].thinking += usage.thinking
            }
            stats.burn[range] = points
        }

        let hourAgo = (nowSeconds - 3600) / Self.slotSeconds
        stats.costLastHour = store.slotCost.filter { $0.key >= hourAgo }.values.reduce(0, +)

        let todayKey = Int((now.timeIntervalSince1970 + zoneOffset) / 86_400)
        let today = store.days[todayKey] ?? Day()
        let total = today.models.values.reduce(TokenUsage(), +)
        stats.tokensToday = total.total
        stats.errorsToday = today.errors
        stats.cacheRead = total.cacheRead
        stats.cacheDenominator = total.context
        stats.costToday = today.models.reduce(0) { $0 + CostEstimator.cost(of: $1.value, model: $1.key) }

        // Mix by output tokens: cache reads would otherwise drown out everything.
        var mix: [String: Int] = [:]
        for (model, usage) in today.models { mix[CostEstimator.shortName(model), default: 0] += usage.output }
        let mixTotal = max(1, mix.values.reduce(0, +))
        stats.modelMix = mix.sorted { $0.value > $1.value }.map { ($0.key, Double($0.value) / Double(mixTotal)) }

        stats.tools = today.tools.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
        stats.repos = today.repos.sorted { $0.value > $1.value }.prefix(5).map {
            ($0.key, $0.value, CostEstimator.shortName(today.repoModels[$0.key] ?? ""))
        }

        // Day 0 of the epoch was a Thursday; shift so weeks start on Monday.
        let weekday = (todayKey + 3) % 7
        let firstDay = todayKey - weekday - 11 * 7
        let outputs = (0..<84).map { offset in store.days[firstDay + offset]?.models.values.reduce(0) { $0 + $1.output } ?? 0 }
        let peak = Double(max(1, outputs.max() ?? 1))
        stats.heatmap = (0..<12).map { week in
            (0..<7).map { dayOfWeek in
                let offset = week * 7 + dayOfWeek
                return firstDay + offset > todayKey ? nil : (Double(outputs[offset]) / peak).squareRoot()
            }
        }
        return stats
    }

    // MARK: Persistence

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: storeURL), let saved = try? JSONDecoder().decode(Store.self, from: data),
           saved.version == Store().version {
            store = saved
        }
    }

    private func prune(now: Date) {
        let oldestSlot = (Int(now.timeIntervalSince1970) - Self.slotRetention) / Self.slotSeconds
        store.slots = store.slots.filter { $0.key >= oldestSlot }
        store.slotCost = store.slotCost.filter { $0.key >= oldestSlot }
        let oldestDay = Int((now.timeIntervalSince1970 + zoneOffset) / 86_400) - Self.dayRetention
        store.days = store.days.filter { $0.key >= oldestDay }
        store.cursors = store.cursors.filter { FileManager.default.fileExists(atPath: $0.key) }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(store) { try? data.write(to: storeURL, options: .atomic) }
    }
}
