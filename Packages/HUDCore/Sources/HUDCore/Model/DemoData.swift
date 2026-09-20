import Foundation

/// The sample fleet from the design prototype. Used by `--demo` and by snapshot rendering to check
/// every widget state (busy / idle / alert) without waiting for real agents to misbehave.
public enum DemoData {
    public enum Scenario: String, Sendable { case busy, idle, alert }

    public static func agents(_ scenario: Scenario, now: Date = Date()) -> [AgentSnapshot] {
        let fleet: [(String, String, String, ActivityKind, Double, Int, TimeInterval, Int)] = [
            ("orbit-core", "fix/retry-race", "claude-fable-5-1", .thinking, 0.62, 1_240_000, 42 * 60, 2_900),
            ("lumen-ui", "feat/theme-toggle", "claude-opus-5", .editing, 0.41, 612_000, 68 * 60, 1_500),
            ("lantern", "perf/cache-warm", "claude-sonnet-5", .running, 0.78, 2_050_000, 151 * 60, 1_900),
            ("sandpiper", "chore/py312", "claude-haiku-4-5", .reading, 0.23, 88_000, 12 * 60, 980),
            ("willow", "main", "claude-sonnet-5", .waiting, 0.55, 340_000, 182 * 60, 0),
        ]
        return fleet.enumerated().map { index, entry -> AgentSnapshot in
            var snapshot = agent(index, entry, scenario, now)
            snapshot.files = files(root: snapshot.cwd, now: now)
            if !snapshot.steps.isEmpty { snapshot.subagents = subagents(now: now) }
            return snapshot
        }
    }

    /// The flow graph's "explore tests" helper ran on Haiku; two earlier ones on Sonnet and Haiku.
    static func subagents(now: Date) -> [SubagentInfo] {
        let sample: [(String, String, String, String, Int)] = [
            ("a1", "Explore", "explore tests", "claude-haiku-4-5", 38_000), ("old1", "Explore", "map retry call sites", "claude-haiku-4-5", 52_000),
            ("old2", "Plan", "design backoff strategy", "claude-sonnet-5", 140_000),
        ]
        return sample.map { id, type, description, model, tokens in
            var info = SubagentInfo(id: id, toolUseId: id, agentType: type, description: description)
            info.model = model
            info.usage = TokenUsage(input: tokens / 20, output: tokens / 18, cacheRead: tokens * 8 / 10, cacheCreation: tokens / 12)
            info.toolCalls = tokens / 4_000
            info.startedAt = now.addingTimeInterval(-500)
            info.lastEventAt = now.addingTimeInterval(-420)
            info.finished = true
            return info
        }
    }

    /// Two sessions that finished earlier today.
    public static func recent(now: Date = Date()) -> [AgentSnapshot] {
        let fleet: [(String, String, String, ActivityKind, Double, Int, TimeInterval, Int)] = [
            ("juniper", "feat/landing-page", "claude-sonnet-5", .idle, 0.34, 410_000, 95 * 60, 0),
            ("harbor", "fix/queue-retries", "claude-opus-5", .idle, 0.51, 980_000, 210 * 60, 0),
        ]
        return fleet.enumerated().map { index, entry in
            var snapshot = agent(index, entry, .idle, now)
            snapshot.activity = .idle
            snapshot.endedAt = now.addingTimeInterval(-Double(index + 1) * 2.4 * 3600)
            snapshot.files = Array(files(root: snapshot.cwd, now: now).prefix(7 - index * 2))
            return snapshot
        }
    }

    static func files(root: String, now: Date) -> [FileChange] {
        let sample: [(String, FileChange.Kind, Int, Int, Int, Int, Bool)] = [
            ("src/retry/retry.py", .edited, 2, 4, 42, 17, false), ("src/retry/backoff.py", .edited, 1, 1, 9, 3, false),
            ("src/retry/jitter.py", .created, 0, 1, 38, 0, false), ("tests/test_retry.py", .edited, 1, 2, 8, 3, false),
            ("tests/test_backoff.py", .created, 0, 1, 61, 0, false), ("tests/fixtures/timeline.json", .created, 0, 0, 0, 0, true),
            ("src/config.py", .read, 1, 0, 0, 0, false), ("src/api/client.py", .read, 3, 0, 0, 0, false),
            ("src/api/errors.py", .edited, 1, 1, 4, 1, false), ("pyproject.toml", .edited, 1, 0, 0, 0, true),
            ("CLAUDE.md", .read, 1, 0, 0, 0, false), ("README.md", .read, 1, 0, 0, 0, false), ("docs/retries.md", .created, 0, 1, 24, 0, false),
        ]
        return sample.enumerated().map { offset, entry in
            var change = FileChange(path: root + "/" + entry.0, kind: entry.1, lastTouched: now.addingTimeInterval(-Double(offset) * 45 - 5))
            (change.reads, change.edits, change.linesAdded, change.linesRemoved, change.viaShell) = (entry.2, entry.3, entry.4, entry.5, entry.6)
            return change
        }
    }

    private static func agent(_ index: Int, _ entry: (String, String, String, ActivityKind, Double, Int, TimeInterval, Int),
                              _ scenario: Scenario, _ now: Date) -> AgentSnapshot {
        var (repo, branch, model, activity, fill, tokens, elapsed, rate) = entry
        if scenario == .idle { activity = .waiting; rate = 0 }
        let looping = scenario == .alert && repo == "lantern"
        if looping { activity = .error; rate = 2_400 }
        let contextMax = model.contains("haiku") ? 200_000 : 1_000_000
        let heartbeat = (0..<60).map { step -> Int in
            guard rate > 0 else { return 0 }
            let noise = sin(Double(step * (index + 3)) * 12.9898) * 43758.5453
            return Int((noise - noise.rounded(.down)) * Double(rate) / 6)
        }
        let planTotal = [7, 5, 9, 4, 5][index], planDone = [3, 2, 6, 1, 3][index]
        let plan = (0..<planTotal).map { step in
            PlanStep(id: "\(step + 1)", title: "step \(step + 1)",
                     status: step < planDone ? .completed : step == planDone && activity.isActive ? .inProgress : .pending)
        }
        let loop = LoopInfo(label: "edit→pytest", tool: "Bash", signature: "Bash|pytest", iterations: (0..<4).map {
            LoopInfo.Iteration(duration: 38 + Double($0) * 4, tokens: 2_100 + $0 * 300, errorText: "assertionerror")
        }, resolved: false)
        let resolved = LoopInfo(label: "edit→pytest", tool: "Bash", signature: "Bash|pytest -k retry", iterations: (0..<3).map {
            LoopInfo.Iteration(duration: 40 + Double($0), tokens: 1_900, errorText: "expected retries")
        }, resolved: true)
        return AgentSnapshot(
            sessionId: "demo-\(repo)", pid: Int32(index), name: repo, repo: repo, cwd: "/demo/\(repo)",
            gitBranch: branch, model: model, activity: activity, activitySince: now.addingTimeInterval(-14 * 60),
            usage: TokenUsage(input: tokens / 50, output: tokens / 25, cacheRead: tokens * 9 / 10, cacheCreation: tokens / 25),
            contextTokens: Int(Double(contextMax) * fill), tokensPerMinute: rate, heartbeat: heartbeat,
            toolCounts: ["Read": 41, "Edit": 18, "Bash": 14], errorCount: looping ? 4 : 1,
            startedAt: now.addingTimeInterval(-elapsed), ticker: ticker(repo: repo, activity: activity, looping: looping, now: now),
            contextMax: contextMax, turnIndex: 7, steps: repo == "orbit-core" || looping ? steps(now: now) : [],
            lanes: lanes(seed: index, waiting: activity == .waiting, now: now),
            promptTicks: [52, 33, 14].map { now.addingTimeInterval(-Double($0 + index * 2) * 60) },
            plan: plan, loops: looping ? [loop] : repo == "orbit-core" ? [resolved] : [], brain: brain(now: now),
            contextSplit: (files: 61_000, tools: 34_000, thinking: 21_000), etaMinutes: activity.isActive ? 18 - index * 3 : nil
        )
    }

    static func ticker(repo: String, activity: ActivityKind, looping: Bool, now: Date) -> [TickerItem] {
        let text: String = switch repo {
        case "orbit-core": "the race is in the retry handler — the backoff timer fires before the mutex releases, so the second attempt reads stale state…"
        case "lumen-ui": "Edit · ThemeToggle.swift  +18 −4  ·  switched palette to semantic tokens"
        case "lantern": looping ? "Bash failed — pytest exit 1 — AssertionError in test_cache::test_warm_hit" : "Bash · pytest tests/test_cache.py -x -q  ·  12 passed in 3.8s"
        case "sandpiper": "Read · pyproject.toml, requirements.txt  ·  checking pinned versions against py3.12"
        default: "waiting for user — “should I also migrate the legacy events table?”"
        }
        let kind: ActivityKind = looping ? .error : activity
        return [TickerItem(id: repo, date: now.addingTimeInterval(-Double(repo.count)), kind: kind, text: text)]
    }

    /// prompt → thinking → {Read, Grep, subagent} → thinking → Edit → Bash ✕ ×3 (running again)
    static func steps(now: Date) -> [TurnStep] {
        func step(_ id: String, _ kind: TurnStep.Kind, _ activity: ActivityKind, _ label: String, _ detail: String, _ tokens: Int,
                  group: Int, tool: String? = nil, ago: TimeInterval, done: Bool = true) -> TurnStep {
            TurnStep(id: id, kind: kind, activity: activity, label: label, detail: detail, tokens: tokens,
                     startedAt: now.addingTimeInterval(-ago), endedAt: done ? now.addingTimeInterval(-ago + 4.2) : nil,
                     group: group, toolName: tool, target: detail)
        }
        var edit = step("e1", .tool, .editing, "Edit", "retry.py", 1_800, group: 4, tool: "Edit", ago: 120)
        edit.linesAdded = 42
        edit.linesRemoved = 17
        var failed = step("b1", .tool, .error, "Bash", "pytest", 1_900, group: 5, tool: "Bash", ago: 60)
        failed.isError = true
        failed.iteration = 3
        failed.errorText = "Exit code 1 — AssertionError: expected 3 retries, got 2"
        failed.target = "pytest tests/test_retry.py -x -q"
        return [
            step("p1", .prompt, .waiting, "prompt", "fix flaky retry", 40, group: 0, ago: 600),
            step("t1", .thinking, .thinking, "thinking", "locate the race", 8_400, group: 1, ago: 560),
            step("r1", .tool, .reading, "Read", "retry.py", 1_400, group: 2, tool: "Read", ago: 500),
            step("s1", .tool, .reading, "Grep", "\"backoff\"", 400, group: 2, tool: "Grep", ago: 500),
            step("a1", .tool, .subagent, "Agent", "explore tests", 2_100, group: 2, tool: "Agent", ago: 500),
            step("t2", .thinking, .thinking, "thinking", "patch plan", 14_200, group: 3, ago: 300),
            edit, failed,
            step("b2", .tool, .running, "Bash", "pytest", 300, group: 6, tool: "Bash", ago: 8, done: false),
        ]
    }

    static func lanes(seed: Int, waiting: Bool, now: Date) -> [LaneSegment] {
        let palette: [ActivityKind] = waiting ? [.waiting, .waiting, .reading, .waiting, .thinking]
                                              : [.thinking, .reading, .editing, .running, .thinking, .editing, .running, .reading]
        var segments: [LaneSegment] = []
        var minute = 0.0, index = 0
        while minute < 60 {
            let noise = sin(Double(seed * 31 + index) * 12.9898) * 43758.5453
            let length = min(60 - minute, 1.5 + (noise - noise.rounded(.down)) * 7)
            let kind: ActivityKind = seed == 0 && minute > 34 && index % 2 == 1 ? .error : palette[index % palette.count]
            segments.append(LaneSegment(start: now.addingTimeInterval((minute - 60) * 60), end: now.addingTimeInterval((minute + length - 60) * 60), kind: kind))
            minute += length
            index += 1
        }
        return segments
    }

    static func brain(now: Date) -> [BrainItem] {
        let items: [(BrainItem.Layer, String, Int, ActivityKind, Bool)] = [
            (.prompt, "fix flaky retry", 900, .waiting, true),
            (.files, "retry.py", 18_400, .reading, true), (.files, "test_retry.py", 9_100, .reading, true), (.files, "backoff.py", 6_200, .reading, false),
            (.files, "config.py", 2_100, .reading, false), (.files, "CLAUDE.md", 4_800, .reading, false), (.files, "README.md", 1_200, .reading, false),
            (.tools, "Read", 14_200, .reading, true), (.tools, "Grep", 3_900, .reading, false), (.tools, "Edit", 7_600, .editing, true),
            (.tools, "Bash", 12_800, .running, true), (.tools, "Write", 900, .editing, false),
            (.reasoning, "hypothesis", 4_100, .thinking, false), (.reasoning, "locate race", 8_400, .thinking, false), (.reasoning, "patch", 6_200, .thinking, true),
            (.reasoning, "verify", 14_200, .thinking, true), (.reasoning, "conclude", 1_800, .thinking, false),
            (.output, "plan.md", 2_400, .editing, false), (.output, "diff", 5_100, .editing, true), (.output, "summary", 800, .responding, false),
        ]
        return items.map { BrainItem(layer: $0.0, name: $0.1, tokens: $0.2, activity: $0.3, lastTurn: $0.4 ? 7 : 5, lastTouched: now) }
    }

    public static func stats(now: Date = Date()) -> StatsSnapshot {
        var stats = StatsSnapshot()
        stats.isBackfilling = false
        for range in BurnRange.allCases {
            stats.burn[range] = (0..<range.shape.points).map { index in
                let wobble = 1 + 0.4 * sin(Double(index) / 3) + Double(index) * 0.04
                return BurnPoint(input: Int(30_000 * wobble), output: Int(14_000 * wobble), cacheRead: Int(220_000 * wobble), thinking: Int(18_000 * wobble))
            }
        }
        stats.modelMix = [("fable-5.1", 0.38), ("sonnet-5", 0.31), ("opus-5", 0.22), ("haiku-4.5", 0.09)]
        stats.cacheRead = 1_900_000
        stats.cacheDenominator = 2_700_000
        stats.costToday = 41.27
        stats.costLastHour = 3.10
        stats.tokensToday = 3_120_000
        stats.errorsToday = 12
        stats.tools = [("Read", 412), ("Edit", 188), ("Bash", 143), ("Grep", 97), ("Write", 31)]
        stats.repos = [("lantern", 2_050_000, "sonnet-5"), ("orbit-core", 1_240_000, "fable-5.1"), ("lumen-ui", 612_000, "opus-5"),
                       ("willow", 340_000, "sonnet-5"), ("sandpiper", 88_000, "haiku-4.5")]
        stats.heatmap = (0..<12).map { week in (0..<7).map { day in
            let noise = sin(Double(week * 7 + day * 3) * 12.9898) * 43758.5453
            let value = noise - noise.rounded(.down)
            return value < 0.15 ? 0 : value
        } }
        return stats
    }
}
