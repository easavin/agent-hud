import Foundation

/// Owns the tailers and per-session state. All file IO happens on this actor.
public actor IngestEngine {
    private struct Tracked {
        var tailer: TranscriptTailer
        var subagents: SubagentTracker
        var state = SessionState()
        var diskChanges: [String: DirectoryScanner.Hit] = [:]
        var lastScan = Date.distantPast
        /// Last known registry entry; kept so an ended session can still be described.
        var entry: RegistryEntry?
        var endedAt: Date?

        init(url: URL) {
            tailer = TranscriptTailer(url: url)
            subagents = SubagentTracker(sessionTranscript: url)
        }
    }

    /// Walking a repo is cheap but not free; changes on disk do not need sub-second latency.
    static let scanInterval: TimeInterval = 10
    /// Finished sessions stay in the dashboard this long, newest first, up to `historyLimit`.
    public static let historyWindow: TimeInterval = 3 * 24 * 3600
    public static let historyLimit = 8

    private let registry: SessionRegistry
    private let projectsDirectory: URL
    private var tracked: [String: Tracked] = [:]
    /// Transcripts of sessions that ended before the app launched, loaded one per poll so startup stays snappy.
    private var backlog: [URL]?

    public init(claudeHome: URL = SessionRegistry.defaultClaudeHome) {
        registry = SessionRegistry(claudeHome: claudeHome)
        projectsDirectory = claudeHome.appendingPathComponent("projects")
    }

    /// Reads whatever was appended since the last call. Returns live agents first, then recently ended sessions.
    public func poll(now: Date = Date()) -> [AgentSnapshot] {
        let entries = registry.liveEntries()
        let liveIds = Set(entries.map(\.sessionId))

        for entry in entries {
            if tracked[entry.sessionId] == nil, let url = transcriptURL(sessionId: entry.sessionId) { tracked[entry.sessionId] = Tracked(url: url) }
            tracked[entry.sessionId]?.entry = entry
            // A resumed session comes back to life.
            tracked[entry.sessionId]?.endedAt = nil
        }
        for id in tracked.keys where !liveIds.contains(id) && tracked[id]?.endedAt == nil {
            // Read before writing: an optional-chained assignment holds a modify access on
            // `tracked` while its right-hand side runs, so reading it there is an exclusivity trap.
            let lastEvent = tracked[id]?.state.lastEventAt
            tracked[id]?.endedAt = lastEvent ?? now
        }
        loadNextFromBacklog(excluding: liveIds, now: now)
        tracked = tracked.filter { $0.value.endedAt.map { now.timeIntervalSince($0) < Self.historyWindow } ?? true }

        var live: [AgentSnapshot] = [], ended: [AgentSnapshot] = []
        for id in tracked.keys {
            guard var session = tracked[id] else { continue }
            let isLive = session.endedAt == nil
            var subagents: [SubagentInfo]?
            if isLive || session.lastScan == .distantPast {
                for event in session.tailer.poll() { session.state.apply(event) }
                subagents = session.subagents.poll()
            }
            let busy = session.entry?.isBusy ?? false
            // Idle and ended sessions change nothing, so they are only scanned once.
            // The registry's start time resets when a session is resumed; the transcript remembers the real one.
            if let started = [session.entry?.startedAt, session.state.firstEventAt].compactMap({ $0 }).min(),
               now.timeIntervalSince(session.lastScan) > Self.scanInterval, busy || session.lastScan == .distantPast,
               let root = session.entry?.cwd ?? session.state.cwd {
                // For a finished session, ignore whatever happened in its directory afterwards.
                let until = session.endedAt.map { $0.addingTimeInterval(120) } ?? .distantFuture
                session.diskChanges = DirectoryScanner.changedFiles(in: root, since: started, until: until)
                session.lastScan = now
            }
            var snapshot = Self.snapshot(id: id, session: &session, now: now)
            snapshot.subagents = subagents ?? session.subagents.poll()
            tracked[id] = session
            if isLive { live.append(snapshot) }
            // A transcript that never got an answer (opened and quit) is noise in the history.
            else if snapshot.usage.total > 0 { ended.append(snapshot) }
        }
        live.sort { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
        ended.sort { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
        return live + ended.prefix(Self.historyLimit)
    }

    /// The project slug is a lossy encoding of the cwd, so locate the file by session id instead.
    private func transcriptURL(sessionId: String) -> URL? {
        let projects = (try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)) ?? []
        return projects
            .map { $0.appendingPathComponent("\(sessionId).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Sessions that finished before launch: the newest transcripts touched inside the history window.
    private func loadNextFromBacklog(excluding liveIds: Set<String>, now: Date) {
        if backlog == nil {
            let projects = (try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)) ?? []
            let recent = projects.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] }
                .filter { $0.pathExtension == "jsonl" }
                .compactMap { url -> (URL, Date)? in
                    guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                          now.timeIntervalSince(modified) < Self.historyWindow else { return nil }
                    return (url, modified)
                }
                .sorted { $0.1 > $1.1 }
            backlog = recent.prefix(Self.historyLimit + liveIds.count).map(\.0)
        }
        guard let url = backlog?.first else { return }
        backlog?.removeFirst()
        let id = url.deletingPathExtension().lastPathComponent
        guard tracked[id] == nil, !liveIds.contains(id) else { return }
        var session = Tracked(url: url)
        session.endedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
        tracked[id] = session
    }

    private static func snapshot(id: String, session: inout Tracked, now: Date) -> AgentSnapshot {
        let entry = session.entry
        let isLive = session.endedAt == nil
        let busy = isLive && entry?.isBusy == true
        let heartbeat = session.state.heartbeat(now: now)
        // Output tokens land when a message completes, so the trailing minute lags; an idle agent burns nothing.
        let tokensPerMinute = busy ? session.state.tokensPerMinute(now: now) : 0
        let eta = busy ? session.state.etaMinutes(now: now) : nil
        let state = session.state
        let cwd = entry?.cwd ?? state.cwd ?? ""
        let repo = (cwd as NSString).lastPathComponent

        // The registry is the authority on busy/idle; the transcript says what "busy" means.
        var activity = state.activity
        if !busy {
            activity = isLive && state.activity == .waiting ? .waiting : .idle
        } else if activity == .idle || activity == .waiting {
            activity = .thinking
        }

        var snapshot = AgentSnapshot(
            sessionId: id, pid: entry?.pid ?? 0,
            name: entry?.name ?? state.title ?? repo, repo: repo.isEmpty ? "session" : repo, cwd: cwd,
            gitBranch: state.gitBranch, model: state.model,
            activity: activity, activitySince: state.activitySince,
            usage: state.usage, contextTokens: state.contextTokens,
            tokensPerMinute: tokensPerMinute, heartbeat: heartbeat,
            toolCounts: state.toolCounts, errorCount: state.errorCount,
            startedAt: entry?.startedAt ?? state.firstEventAt, ticker: state.ticker,
            // Sessions that have ever held more than 200k tokens must be on a 1M window.
            contextMax: state.peakContextTokens > 200_000 ? 1_000_000 : 200_000,
            turnIndex: state.turnIndex, steps: state.steps,
            lanes: state.lanes(since: now.addingTimeInterval(-SessionState.laneWindow)),
            promptTicks: state.promptTicks.filter { $0 > now.addingTimeInterval(-SessionState.laneWindow) },
            plan: state.plan, loops: state.loops, brain: state.brain(),
            contextSplit: state.contextSplit, etaMinutes: eta
        )
        snapshot.files = mergeFiles(transcript: state.fileChanges, disk: session.diskChanges)
        snapshot.endedAt = session.endedAt
        return snapshot
    }

    /// The transcript knows intent (read / edit / write, line counts); the disk knows what really changed.
    static func mergeFiles(transcript: [String: FileChange], disk: [String: DirectoryScanner.Hit], limit: Int = 80) -> [FileChange] {
        var merged = transcript
        for (path, hit) in disk {
            if var known = merged[path] {
                // Read by the agent, yet modified on disk: something other than Edit/Write changed it.
                if known.kind == .read { known.kind = .edited; known.viaShell = true }
                known.lastTouched = max(known.lastTouched, hit.modified)
                merged[path] = known
            } else {
                var change = FileChange(path: path, kind: hit.created ? .created : .edited, lastTouched: hit.modified)
                change.viaShell = true
                merged[path] = change
            }
        }
        return Array(merged.values.sorted { $0.lastTouched > $1.lastTouched }.prefix(limit))
    }
}
