import Foundation

/// What an agent is doing right now. Drives every color in the UI.
public enum ActivityKind: String, Sendable, CaseIterable {
    case thinking, responding, reading, editing, running, subagent, error, waiting, idle

    public var isActive: Bool { self != .idle && self != .waiting }
}

public struct TokenUsage: Sendable, Equatable, Codable {
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheCreation = 0
    public var thinking = 0
    /// The part of `cacheCreation` written with the 1-hour TTL (billed higher than 5-minute writes).
    public var cacheCreation1h = 0

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheCreation: Int = 0, thinking: Int = 0, cacheCreation1h: Int = 0) {
        self.cacheCreation1h = cacheCreation1h
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.thinking = thinking
    }

    public var total: Int { input + output + cacheRead + cacheCreation }
    /// Tokens occupying the context window on the turn this usage belongs to.
    public var context: Int { input + cacheRead + cacheCreation }
    public var cacheHitRate: Double {
        let denominator = input + cacheRead + cacheCreation
        return denominator == 0 ? 0 : Double(cacheRead) / Double(denominator)
    }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, output: a.output + b.output,
                   cacheRead: a.cacheRead + b.cacheRead, cacheCreation: a.cacheCreation + b.cacheCreation,
                   thinking: a.thinking + b.thinking, cacheCreation1h: a.cacheCreation1h + b.cacheCreation1h)
    }

    public static func - (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input - b.input, output: a.output - b.output,
                   cacheRead: a.cacheRead - b.cacheRead, cacheCreation: a.cacheCreation - b.cacheCreation,
                   thinking: a.thinking - b.thinking, cacheCreation1h: a.cacheCreation1h - b.cacheCreation1h)
    }
}

/// One entry of `~/.claude/sessions/<pid>.json`.
public struct RegistryEntry: Sendable, Equatable {
    public var pid: Int32
    public var sessionId: String
    public var cwd: String
    public var name: String?
    public var isBusy: Bool
    public var startedAt: Date?
    public var entrypoint: String?
}

/// One line of the scrolling ticker / thought stream.
public struct TickerItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var date: Date
    public var kind: ActivityKind
    public var text: String
}

public struct PlanStep: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable {
        case pending, inProgress, completed, failed

        public init(raw: String?) {
            switch raw {
            case "in_progress": self = .inProgress
            case "completed": self = .completed
            case "failed": self = .failed
            default: self = .pending
            }
        }
    }

    public var id: String
    public var title: String
    public var status: Status

    public init(id: String = "", title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
    }
}

/// One node of the current turn: the prompt, a thinking block, a tool call or the final answer.
public struct TurnStep: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable { case prompt, thinking, tool, result }

    public var id: String
    public var kind: Kind
    public var activity: ActivityKind
    public var label: String
    public var detail: String
    public var tokens: Int
    public var startedAt: Date
    public var endedAt: Date?
    /// Steps emitted by the same assistant message ran in parallel.
    public var group: Int
    public var toolName: String?
    public var target: String = ""
    public var isError = false
    public var errorText: String?
    public var linesAdded = 0
    public var linesRemoved = 0
    /// How many times in a row this same call has failed, including this one.
    public var iteration = 0

    public var isRunning: Bool { kind == .tool && endedAt == nil }
    public var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
}

public struct LaneSegment: Sendable, Equatable {
    public var start: Date
    public var end: Date?
    public var kind: ActivityKind
}

/// A retry loop: the same call failing repeatedly with edits in between.
public struct LoopInfo: Sendable, Equatable {
    /// e.g. "edit→pytest"
    public var label: String
    public var tool: String
    public var signature: String
    public var iterations: [Iteration]
    public var resolved: Bool

    public struct Iteration: Sendable, Equatable {
        public var duration: TimeInterval
        public var tokens: Int
        public var errorText: String
    }

    public var count: Int { iterations.count }
    public var sameErrorCount: Int {
        guard let last = iterations.last?.errorText else { return 0 }
        return iterations.reversed().prefix { $0.errorText == last }.count
    }
}

/// A file the session has touched, from the transcript (Read / Edit / Write) or found changed on disk.
public struct FileChange: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case read, edited, created }

    public var id: String { path }
    /// Absolute path.
    public var path: String
    public var kind: Kind
    public var reads = 0
    public var edits = 0
    public var linesAdded = 0
    public var linesRemoved = 0
    /// Changed on disk without an Edit/Write call: a shell command, a build step, a formatter…
    public var viaShell = false
    public var lastTouched: Date

    public init(path: String, kind: Kind, lastTouched: Date) {
        self.path = path
        self.kind = kind
        self.lastTouched = lastTouched
    }
}

/// A subagent spawned by the session (Agent / Task tool), read from `<session>/subagents/agent-*.jsonl`.
public struct SubagentInfo: Sendable, Equatable, Identifiable {
    public var id: String
    /// The `tool_use` id of the call that spawned it; ties it to a node in the flow graph.
    public var toolUseId: String
    /// "Explore", "Plan", "general-purpose"…
    public var agentType: String
    public var description: String
    public var model: String?
    public var usage = TokenUsage()
    public var toolCalls = 0
    public var startedAt: Date?
    public var lastEventAt: Date?
    public var finished = false

    public init(id: String, toolUseId: String, agentType: String, description: String) {
        self.id = id
        self.toolUseId = toolUseId
        self.agentType = agentType
        self.description = description
    }

    public func isRunning(now: Date = Date()) -> Bool {
        guard !finished, let last = lastEventAt else { return false }
        return now.timeIntervalSince(last) < 90
    }

    public var cost: Double { model.map { CostEstimator.cost(of: usage, model: $0) } ?? 0 }
}

/// Something occupying the agent's context window.
public struct BrainItem: Sendable, Equatable, Identifiable {
    public enum Layer: Int, Sendable, CaseIterable { case prompt, files, tools, reasoning, output }

    public var id: String { "\(layer.rawValue)-\(name)" }
    public var layer: Layer
    public var name: String
    public var tokens: Int
    public var activity: ActivityKind
    public var lastTurn: Int
    public var lastTouched: Date
}

/// Everything the UI needs to draw one agent. Value type, rebuilt on every poll.
public struct AgentSnapshot: Sendable, Identifiable, Equatable {
    public var id: String { sessionId }
    public var sessionId: String
    public var pid: Int32
    public var name: String
    public var repo: String
    public var cwd: String
    public var gitBranch: String?
    public var model: String?
    public var activity: ActivityKind
    public var activitySince: Date?
    public var usage: TokenUsage
    public var contextTokens: Int
    public var tokensPerMinute: Int
    /// Output tokens per 5 s bucket, oldest first.
    public var heartbeat: [Int]
    public var toolCounts: [String: Int]
    public var errorCount: Int
    public var startedAt: Date?
    public var ticker: [TickerItem]
    public var contextMax: Int
    public var turnIndex: Int
    public var steps: [TurnStep]
    public var lanes: [LaneSegment]
    public var promptTicks: [Date]
    public var plan: [PlanStep]
    public var loops: [LoopInfo]
    public var brain: [BrainItem]
    /// Rough split of the context window: file reads, other tool results, thinking.
    public var contextSplit: (files: Int, tools: Int, thinking: Int)
    public var etaMinutes: Int?
    /// Files touched this session, most recent first.
    public var files: [FileChange] = []
    public var subagents: [SubagentInfo] = []
    /// Set once the session's process is gone. Ended sessions stay visible as history.
    public var endedAt: Date?

    public var isEnded: Bool { endedAt != nil }

    public var contextFill: Double { contextMax == 0 ? 0 : min(1, Double(contextTokens) / Double(contextMax)) }
    public var planDone: Int { plan.filter { $0.status == .completed }.count }
    public var activeLoop: LoopInfo? { loops.last { !$0.resolved } }
    public var isLooping: Bool { (activeLoop?.count ?? 0) >= 2 }

    public static func == (a: AgentSnapshot, b: AgentSnapshot) -> Bool {
        a.sessionId == b.sessionId && a.activity == b.activity && a.usage == b.usage && a.heartbeat == b.heartbeat
            && a.steps == b.steps && a.ticker == b.ticker && a.plan == b.plan && a.loops == b.loops
            && a.lanes.count == b.lanes.count && a.name == b.name && a.files == b.files && a.subagents == b.subagents && a.endedAt == b.endedAt
    }
}
