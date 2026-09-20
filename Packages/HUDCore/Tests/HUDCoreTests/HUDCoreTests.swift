import Foundation
import Testing
@testable import HUDCore

private func assistantLine(messageId: String, output: Int, block: String, stop: String? = nil,
                           timestamp: String = "2026-09-18T09:00:00.000Z") -> String {
    let stopJSON = stop.map { "\"\($0)\"" } ?? "null"
    return """
    {"type":"assistant","uuid":"u-\(messageId)-\(output)","timestamp":"\(timestamp)","gitBranch":"main","message":{"id":"\(messageId)","model":"claude-opus-5","stop_reason":\(stopJSON),"usage":{"input_tokens":10,"output_tokens":\(output),"cache_read_input_tokens":1000,"cache_creation_input_tokens":200,"output_tokens_details":{"thinking_tokens":5}},"content":[\(block)]}}
    """
}

private func toolResultLine(id: String, isError: Bool) -> String {
    """
    {"type":"user","timestamp":"2026-09-18T09:00:02.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\(id)","is_error":\(isError),"content":"out"}]}}
    """
}

private func events(_ lines: [String]) -> [TranscriptEvent] {
    lines.compactMap { TranscriptParser.parse(line: Data($0.utf8)) }
}

@Suite struct ParserTests {
    @Test func parsesAssistantUsageAndBlocks() throws {
        let line = assistantLine(messageId: "m1", output: 50,
                                 block: #"{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a/b/Foo.swift"}}"#)
        let event = try #require(TranscriptParser.parse(line: Data(line.utf8)))
        #expect(event.role == .assistant)
        #expect(event.model == "claude-opus-5")
        #expect(event.usage == TokenUsage(input: 10, output: 50, cacheRead: 1000, cacheCreation: 200, thinking: 5))
        guard case .toolUse(let call)? = event.blocks.first else { Issue.record("expected tool use"); return }
        #expect(call.name == "Read")
        #expect(call.summary == "Foo.swift")
        #expect(call.target == "/a/b/Foo.swift")
        #expect(event.timestamp != nil)
    }

    @Test func distinguishesPromptFromToolResult() {
        let prompt = #"{"type":"user","message":{"role":"user","content":"fix the bug"}}"#
        let parsed = events([prompt, toolResultLine(id: "t1", isError: false)])
        #expect(parsed[0].isUserPrompt)
        #expect(!parsed[1].isUserPrompt)
    }

    @Test func toleratesGarbageAndUnknownTypes() {
        #expect(TranscriptParser.parse(line: Data("not json".utf8)) == nil)
        #expect(TranscriptParser.parse(line: Data(#"{"type":"queue-operation"}"#.utf8))?.role == .other)
    }
}

@Suite struct SessionStateTests {
    @Test func usageIsCountedOncePerMessage() {
        var state = SessionState()
        // Same message id split over two lines, the second carrying the final usage.
        let lines = [
            assistantLine(messageId: "m1", output: 20, block: #"{"type":"thinking","thinking":"hmm"}"#),
            assistantLine(messageId: "m1", output: 50, block: #"{"type":"text","text":"done"}"#),
            assistantLine(messageId: "m2", output: 30, block: #"{"type":"text","text":"more"}"#),
        ]
        events(lines).forEach { state.apply($0) }
        #expect(state.usage.output == 80)
        #expect(state.usage.input == 20)
        #expect(state.contextTokens == 1210)
    }

    @Test func activityFollowsToolLifecycle() {
        var state = SessionState()
        let bash = #"{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"swift test"}}"#
        state.apply(events([assistantLine(messageId: "m1", output: 5, block: bash)])[0])
        #expect(state.activity == .running)

        state.apply(events([toolResultLine(id: "t1", isError: true)])[0])
        #expect(state.activity == .error)
        #expect(state.errorCount == 1)

        let edit = #"{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/x/A.swift"}}"#
        state.apply(events([assistantLine(messageId: "m2", output: 5, block: edit)])[0])
        #expect(state.activity == .editing)

        state.apply(events([toolResultLine(id: "t2", isError: false)])[0])
        #expect(state.activity == .thinking)

        state.apply(events([assistantLine(messageId: "m3", output: 5, block: #"{"type":"text","text":"ok"}"#, stop: "end_turn")])[0])
        #expect(state.activity == .waiting)
        #expect(state.toolCounts == ["Bash": 1, "Edit": 1])
        #expect(state.ticker.map(\.kind) == [.running, .error, .editing, .responding])
        #expect(state.lanes.map(\.kind) == [.running, .error, .editing, .thinking, .responding, .waiting])
    }

    @Test func heartbeatBucketsOutputTokens() throws {
        var state = SessionState()
        state.apply(events([assistantLine(messageId: "m1", output: 120, block: #"{"type":"text","text":"x"}"#)])[0])
        let now = try #require(TranscriptParser.parseDate("2026-09-18T09:00:12.000Z"))
        let beat = state.heartbeat(now: now)
        #expect(beat.count == SessionState.bucketCount)
        #expect(beat.reduce(0, +) == 120)
        #expect(state.tokensPerMinute(now: now) == 120)
        #expect(state.tokensPerMinute(now: now.addingTimeInterval(600)) == 0)
    }
}

@Suite struct LoopAndPlanTests {
    private func bash(_ id: String, message: String) -> String {
        assistantLine(messageId: message, output: 5, block: #"{"type":"tool_use","id":"\#(id)","name":"Bash","input":{"command":"cd pkg && swift test","description":"Run tests"}}"#)
    }

    @Test func repeatedFailuresBecomeALoopAndSuccessResolvesIt() {
        var state = SessionState()
        state.apply(events([#"{"type":"user","message":{"role":"user","content":"fix the tests"}}"#])[0])
        for round in 1...3 {
            let edit = #"{"type":"tool_use","id":"e\#(round)","name":"Edit","input":{"file_path":"/x/A.swift","old_string":"a","new_string":"b\nc"}}"#
            events([assistantLine(messageId: "me\(round)", output: 5, block: edit), toolResultLine(id: "e\(round)", isError: false),
                    bash("b\(round)", message: "mb\(round)"), toolResultLine(id: "b\(round)", isError: true)]).forEach { state.apply($0) }
        }
        #expect(state.loops.count == 1)
        #expect(state.loops[0].count == 3)
        #expect(state.loops[0].sameErrorCount == 3)
        #expect(state.loops[0].label == "edit→swift")
        #expect(!state.loops[0].resolved)
        #expect(state.steps.last?.iteration == 3)
        #expect(state.steps.first?.kind == .prompt)

        events([bash("b4", message: "mb4"), toolResultLine(id: "b4", isError: false)]).forEach { state.apply($0) }
        #expect(state.loops[0].resolved)
    }

    @Test func planTracksTaskToolCalls() {
        var state = SessionState()
        let lines = [
            assistantLine(messageId: "p1", output: 5, block: #"{"type":"tool_use","id":"c1","name":"TaskCreate","input":{"subject":"Port rules"}}"#),
            assistantLine(messageId: "p2", output: 5, block: #"{"type":"tool_use","id":"c2","name":"TaskCreate","input":{"subject":"Add schema"}}"#),
            assistantLine(messageId: "p3", output: 5, block: #"{"type":"tool_use","id":"c3","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}"#),
            assistantLine(messageId: "p4", output: 5, block: #"{"type":"tool_use","id":"c4","name":"TaskUpdate","input":{"taskId":"2","status":"in_progress"}}"#),
        ]
        events(lines).forEach { state.apply($0) }
        #expect(state.plan.map(\.status) == [.completed, .inProgress])
        #expect(state.plan.map(\.title) == ["Port rules", "Add schema"])
    }

    @Test func editsCarryLineCounts() {
        var state = SessionState()
        let edit = #"{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"/x/A.swift","old_string":"a","new_string":"b\nc\nd"}}"#
        state.apply(events([assistantLine(messageId: "m", output: 5, block: edit)])[0])
        #expect(state.steps.last?.linesAdded == 3)
        #expect(state.steps.last?.linesRemoved == 1)
        #expect(state.steps.last?.detail == "A.swift")
    }
}

@Suite struct TailerTests {
    @Test func emitsOnlyAppendedCompleteLines() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hud-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = assistantLine(messageId: "m1", output: 1, block: #"{"type":"text","text":"a"}"#)
        let second = assistantLine(messageId: "m2", output: 2, block: #"{"type":"text","text":"b"}"#)

        try Data((first + "\n").utf8).write(to: url)
        var tailer = TranscriptTailer(url: url)
        #expect(tailer.poll().count == 1)
        #expect(tailer.poll().isEmpty)

        // Half a line now, the rest later.
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let half = second.index(second.startIndex, offsetBy: 40)
        try handle.write(contentsOf: Data(second[..<half].utf8))
        #expect(tailer.poll().isEmpty)
        try handle.write(contentsOf: Data((second[half...] + "\n").utf8))
        let tail = tailer.poll()
        #expect(tail.count == 1)
        #expect(tail.first?.messageId == "m2")
    }
}

@Suite struct RegistryTests {
    @Test func parsesEntry() throws {
        let json = #"{"pid":13293,"sessionId":"abc","cwd":"/Users/x/repo","startedAt":1789721929494,"name":"My agent","status":"busy","entrypoint":"claude-desktop"}"#
        let entry = try #require(SessionRegistry.parse(Data(json.utf8)))
        #expect(entry.pid == 13293)
        #expect(entry.isBusy)
        #expect(entry.name == "My agent")
    }

    @Test func detectsLiveProcess() {
        #expect(SessionRegistry.isAlive(pid: getpid()))
    }
}

@Suite struct HistoryTests {
    @Test func indexesOnceAndCountsEachMessageOnce() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("hud-home-\(UUID().uuidString)")
        let project = home.appendingPathComponent("projects/-x-repo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let now = Date()
        let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(now.addingTimeInterval(-300))
        let read = #"{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a"}}"#
        let lines = [
            assistantLine(messageId: "m1", output: 20, block: #"{"type":"thinking","thinking":"hmm"}"#, timestamp: stamp),
            assistantLine(messageId: "m1", output: 50, block: read, timestamp: stamp),
            assistantLine(messageId: "m2", output: 30, block: #"{"type":"text","text":"x"}"#, timestamp: stamp),
        ].map { $0.replacingOccurrences(of: #""gitBranch":"main""#, with: #""gitBranch":"main","cwd":"/x/repo""#) }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: project.appendingPathComponent("s.jsonl"))

        let index = HistoryIndex(claudeHome: home, storeURL: home.appendingPathComponent("index.json"))
        let first = await index.refresh(now: now)
        let second = await index.refresh(now: now)
        let hour = try #require(first.burn[.hour])
        #expect(hour.reduce(0) { $0 + $1.output + $1.thinking } == 80)
        #expect(first == second)
        #expect(first.tools.first?.name == "Read")
        #expect(first.repos.first?.name == "repo")
        #expect(first.modelMix.first?.model == "opus-5")
        #expect(abs(first.costToday - CostEstimator.cost(of: TokenUsage(input: 20, output: 80, cacheRead: 2000, cacheCreation: 400, thinking: 10), model: "claude-opus-5")) < 1e-9)
    }

    @Test func shortModelNames() {
        #expect(CostEstimator.shortName("claude-fable-5-1") == "fable-5.1")
        #expect(CostEstimator.shortName("claude-haiku-4-5-20251001") == "haiku-4.5")
        #expect(CostEstimator.shortName("claude-opus-5") == "opus-5")
    }
}

@Suite struct FileChangeTests {
    private func tool(_ id: String, _ name: String, _ input: String) -> String {
        assistantLine(messageId: "m-\(id)", output: 5, block: #"{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":\#(input)}"#)
    }

    @Test func transcriptClassifiesReadsEditsAndNewFiles() {
        var state = SessionState()
        let lines = [
            tool("r1", "Read", #"{"file_path":"/repo/a.swift"}"#), toolResultLine(id: "r1", isError: false),
            tool("e1", "Edit", #"{"file_path":"/repo/a.swift","old_string":"x","new_string":"y\nz"}"#), toolResultLine(id: "e1", isError: false),
            tool("w1", "Write", #"{"file_path":"/repo/new.swift","content":"1\n2\n3"}"#), toolResultLine(id: "w1", isError: false),
            tool("e2", "Edit", #"{"file_path":"/repo/b.swift","old_string":"x","new_string":"y"}"#), toolResultLine(id: "e2", isError: true),
            tool("r2", "Read", #"{"file_path":"/repo/c.swift"}"#), toolResultLine(id: "r2", isError: false),
        ]
        events(lines).forEach { state.apply($0) }
        #expect(state.fileChanges["/repo/a.swift"]?.kind == .edited)
        #expect(state.fileChanges["/repo/a.swift"]?.linesAdded == 2)
        #expect(state.fileChanges["/repo/new.swift"]?.kind == .created)
        #expect(state.fileChanges["/repo/new.swift"]?.linesAdded == 3)
        #expect(state.fileChanges["/repo/b.swift"] == nil, "a failed edit changed nothing")
        #expect(state.fileChanges["/repo/c.swift"]?.kind == .read)
    }

    @Test func scannerFindsShellChangesAndSkipsNoise() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hud-scan-\(UUID().uuidString)/work/repo")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent()) }
        for folder in ["src", "node_modules/pkg", ".git"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for file in ["src/main.swift", "node_modules/pkg/index.js", ".git/HEAD"] {
            try Data("x".utf8).write(to: root.appendingPathComponent(file))
        }
        let old = root.appendingPathComponent("src/old.swift")
        try Data("x".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200), .creationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: old.path)

        let hits = DirectoryScanner.changedFiles(in: root.path, since: Date(timeIntervalSinceNow: -60))
        #expect(hits.keys.map { ($0 as NSString).lastPathComponent }.sorted() == ["main.swift"])
        #expect(hits.values.first?.created == true)

        var read = FileChange(path: hits.keys.first!, kind: .read, lastTouched: Date(timeIntervalSinceNow: -30))
        read.reads = 1
        let merged = IngestEngine.mergeFiles(transcript: [read.path: read], disk: hits)
        #expect(merged.first?.kind == .edited)
        #expect(merged.first?.viaShell == true)
    }
}

@Suite struct SubagentAndHistoryTests {
    @Test func readsSubagentModelAndKeepsEndedSessions() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("hud-hist-\(UUID().uuidString)")
        let project = home.appendingPathComponent("projects/-x-repo")
        let subagents = project.appendingPathComponent("sess1/subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let now = Date()
        let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(now.addingTimeInterval(-600))
        let spawn = #"{"type":"tool_use","id":"toolu_A","name":"Agent","input":{"description":"Explore tests","subagent_type":"Explore"}}"#
        let parent = assistantLine(messageId: "m1", output: 40, block: spawn, timestamp: stamp)
            .replacingOccurrences(of: #""gitBranch":"main""#, with: #""gitBranch":"main","cwd":"/x/repo""#)
        try Data((parent + "\n").utf8).write(to: project.appendingPathComponent("sess1.jsonl"))

        let child = [
            assistantLine(messageId: "c1", output: 10, block: #"{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/x/a"}}"#, timestamp: stamp),
            assistantLine(messageId: "c2", output: 25, block: #"{"type":"text","text":"done"}"#, stop: "end_turn", timestamp: stamp),
        ].map { $0.replacingOccurrences(of: "claude-opus-5", with: "claude-haiku-4-5-20251001").replacingOccurrences(of: #""type":"assistant","#, with: #""type":"assistant","isSidechain":true,"#) }
        try Data((child.joined(separator: "\n") + "\n").utf8).write(to: subagents.appendingPathComponent("agent-abc.jsonl"))
        try Data(#"{"agentType":"Explore","description":"Explore tests","toolUseId":"toolu_A","spawnDepth":1}"#.utf8)
            .write(to: subagents.appendingPathComponent("agent-abc.meta.json"))

        // No registry entry: the session ended before launch, and must still show up as history.
        let engine = IngestEngine(claudeHome: home)
        let snapshots = await engine.poll(now: now)
        let session = try #require(snapshots.first)
        #expect(session.isEnded)
        #expect(session.repo == "repo")
        #expect(session.activity == .idle)
        #expect(session.usage.output == 40)
        let subagent = try #require(session.subagents.first)
        #expect(subagent.toolUseId == "toolu_A")
        #expect(subagent.agentType == "Explore")
        #expect(subagent.model == "claude-haiku-4-5-20251001")
        #expect(subagent.usage.output == 35)
        #expect(subagent.toolCalls == 1)
        #expect(subagent.finished)

        let later = await engine.poll(now: now.addingTimeInterval(IngestEngine.historyWindow + 60))
        #expect(later.isEmpty, "history expires")
    }
}
