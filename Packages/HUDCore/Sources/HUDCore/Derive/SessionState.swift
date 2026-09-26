import Foundation

/// Folds transcript events into the live state of one session.
public struct SessionState: Sendable {
    public static let bucketSeconds: TimeInterval = 5
    public static let bucketCount = 60
    static let tickerLimit = 40
    static let stepLimit = 240
    static let laneWindow: TimeInterval = 6 * 3600

    public private(set) var title: String?
    public private(set) var gitBranch: String?
    public private(set) var model: String?
    public private(set) var usage = TokenUsage()
    public private(set) var contextTokens = 0
    public private(set) var peakContextTokens = 0
    public private(set) var activity: ActivityKind = .idle
    public private(set) var activitySince: Date?
    public private(set) var toolCounts: [String: Int] = [:]
    public private(set) var errorCount = 0
    public private(set) var ticker: [TickerItem] = []
    public private(set) var turnIndex = 0
    public private(set) var steps: [TurnStep] = []
    public private(set) var lanes: [LaneSegment] = []
    public private(set) var promptTicks: [Date] = []
    public private(set) var plan: [PlanStep] = []
    public private(set) var loops: [LoopInfo] = []
    public private(set) var contextSplit = (files: 0, tools: 0, thinking: 0)
    public private(set) var fileChanges: [String: FileChange] = [:]
    /// Timestamp of the first transcript line: when the session really began, however often it was resumed.
    public private(set) var firstEventAt: Date?
    public private(set) var lastEventAt: Date?
    /// Where the session was started.
    public private(set) var cwd: String?

    /// Tool calls that have not received a result yet, by tool_use id.
    private var pendingTools: [String: String] = [:]
    /// Claude Code writes one line per content block, each repeating the message's usage.
    private var lastMessageId: String?
    private var lastMessageUsage = TokenUsage()
    /// Output tokens keyed by bucket index (`timestamp / bucketSeconds`).
    private var buckets: [Int: Int] = [:]
    private var serial = 0
    private var group = 0
    private var brainItems: [String: BrainItem] = [:]
    /// Consecutive failures per call signature, with the index of the loop they feed.
    private var failureStreaks: [String: Int] = [:]
    private var lastEditLabel: String?
    private var outputAtFirstTask: Int?

    public init() {}

    public mutating func apply(_ event: TranscriptEvent) {
        if let branch = event.gitBranch, !branch.isEmpty { gitBranch = branch }
        if event.role == .title { title = event.title ?? title; return }
        // Subagent chatter is accounted for in its own transcript.
        guard !event.isSidechain else { return }
        let date = event.timestamp ?? Date()
        if firstEventAt == nil, event.timestamp != nil { firstEventAt = date }
        if event.timestamp != nil { lastEventAt = date }
        if cwd == nil, let start = event.cwd, !start.isEmpty { cwd = start }

        switch event.role {
        case .assistant: applyAssistant(event, at: date)
        case .user: applyUser(event, at: date)
        case .title, .other: break
        }
    }

    // MARK: Assistant

    private mutating func applyAssistant(_ event: TranscriptEvent, at date: Date) {
        if let model = event.model, model != "<synthetic>" { self.model = model }

        let isContinuation = event.messageId != nil && event.messageId == lastMessageId
        if !isContinuation { group += 1 }
        if let turn = event.usage {
            let delta = turn - (isContinuation ? lastMessageUsage : TokenUsage())
            usage = usage + delta
            contextTokens = turn.context
            peakContextTokens = max(peakContextTokens, contextTokens)
            buckets[Self.bucket(for: date), default: 0] += max(0, delta.output)
            lastMessageId = event.messageId
            lastMessageUsage = turn
        }

        for block in event.blocks {
            switch block {
            case .thinking(let text):
                set(.thinking, at: date)
                let tokens = max(text.count / 4, event.usage?.thinking ?? 0)
                contextSplit.thinking += tokens
                addStep(.thinking, .thinking, label: "thinking", detail: text, tokens: tokens, at: date)
                if !text.isEmpty {
                    push(.thinking, text, at: date)
                    touchBrain(.reasoning, name: TranscriptParser.snippet(text, limit: 22), tokens: tokens, activity: .thinking, at: date)
                }
            case .text(let text):
                set(.responding, at: date)
                guard !text.isEmpty else { break }
                push(.responding, text, at: date)
                addStep(.result, .responding, label: "reply", detail: text, tokens: text.count / 4, at: date)
            case .toolUse(let call):
                applyToolUse(call, at: date)
            case .toolResult:
                break
            }
        }

        if event.stopReason == "end_turn" {
            // Waiting on the user's next prompt is idle time as far as the lanes go; drawn, it would
            // fill every hour between turns and drown out the work.
            set(.waiting, lane: .idle, at: date)
            touchBrain(.output, name: "summary", tokens: steps.last?.tokens ?? 0, activity: .responding, at: date)
        }
    }

    private mutating func applyToolUse(_ call: TranscriptEvent.ToolCall, at date: Date) {
        pendingTools[call.id] = call.name
        toolCounts[call.name, default: 0] += 1
        let kind = ActivityClassifier.activity(forTool: call.name)
        set(kind, at: date)
        push(kind, call.summary.isEmpty ? call.name : "\(call.name) · \(call.summary)", at: date)

        let short = Self.shortTarget(call)
        var step = TurnStep(id: call.id, kind: .tool, activity: kind, label: Self.displayName(call.name), detail: short,
                            tokens: call.inputChars / 4, startedAt: date, group: group, toolName: call.name, target: call.target)
        step.linesAdded = call.linesAdded
        step.linesRemoved = call.linesRemoved
        append(step)

        if kind == .editing {
            lastEditLabel = "edit"
            touchBrain(.output, name: short, tokens: call.inputChars / 4, activity: .editing, at: date)
        }
        if let op = call.planOp { applyPlan(op) }
    }

    // MARK: User

    private mutating func applyUser(_ event: TranscriptEvent, at date: Date) {
        if event.isUserPrompt {
            let text = event.blocks.lazy.compactMap { if case .text(let text) = $0 { text } else { nil } }.first ?? "(attachment)"
            guard !Self.isSystemNoise(text) else { return }
            pendingTools.removeAll()
            turnIndex += 1
            promptTicks.append(date)
            steps.removeAll()
            set(.thinking, at: date)
            addStep(.prompt, .waiting, label: "prompt", detail: text, tokens: text.count / 4, at: date)
            touchBrain(.prompt, name: TranscriptParser.snippet(text, limit: 22), tokens: text.count / 4, activity: .waiting, at: date)
            return
        }
        for case .toolResult(let id, let isError, let chars, let errorText) in event.blocks {
            let name = pendingTools.removeValue(forKey: id)
            finishStep(id: id, isError: isError, chars: chars, errorText: errorText, at: date)
            if isError {
                errorCount += 1
                push(.error, "\(name ?? "tool") failed — \(errorText ?? "")", at: date)
            }
            if let next = pendingTools.values.first {
                set(ActivityClassifier.activity(forTool: next), at: date)
            } else {
                // All results are in; the model is digesting them.
                set(isError ? .error : .thinking, at: date)
            }
        }
    }

    /// Lines Claude Code injects as "user" that no human typed.
    static func isSystemNoise(_ text: String) -> Bool {
        text.hasPrefix("<") || text.hasPrefix("Caveat:") || text.hasPrefix("[Request interrupted") || text.hasPrefix("[Image:")
            || text.hasPrefix("Base directory for this skill")
    }

    // MARK: Steps, loops, brain

    private mutating func addStep(_ kind: TurnStep.Kind, _ activity: ActivityKind, label: String, detail: String, tokens: Int, at date: Date) {
        serial += 1
        append(TurnStep(id: "s\(serial)", kind: kind, activity: activity, label: label,
                        detail: TranscriptParser.snippet(detail, limit: 140), tokens: tokens,
                        startedAt: date, endedAt: date, group: group))
    }

    private mutating func append(_ step: TurnStep) {
        steps.append(step)
        // Keep the prompt, drop the oldest work.
        if steps.count > Self.stepLimit { steps.remove(at: steps.first?.kind == .prompt ? 1 : 0) }
    }

    private mutating func finishStep(id: String, isError: Bool, chars: Int, errorText: String?, at date: Date) {
        guard let index = steps.lastIndex(where: { $0.id == id }) else { return }
        steps[index].endedAt = date
        steps[index].tokens += chars / 4
        steps[index].isError = isError
        steps[index].errorText = errorText
        if isError { steps[index].activity = .error }
        let step = steps[index]
        guard let tool = step.toolName else { return }

        let tokens = chars / 4
        if ActivityClassifier.activity(forTool: tool) == .reading, tool == "Read" {
            contextSplit.files += tokens
            touchBrain(.files, name: step.detail, tokens: tokens, activity: .reading, at: date)
        } else {
            contextSplit.tools += tokens
        }
        touchBrain(.tools, name: step.label, tokens: step.tokens, activity: ActivityClassifier.activity(forTool: tool), at: date)
        if !isError { recordFile(step, tool: tool, at: date) }
        trackLoop(step, index: index)
    }

    /// Only successful calls count: a rejected Edit changed nothing on disk.
    private mutating func recordFile(_ step: TurnStep, tool: String, at date: Date) {
        let path = step.target
        guard path.hasPrefix("/") else { return }
        let isRead = tool == "Read" || tool == "NotebookRead"
        guard isRead || ActivityClassifier.activity(forTool: tool) == .editing else { return }

        let known = fileChanges[path]
        var change = known ?? FileChange(path: path, kind: .read, lastTouched: date)
        change.lastTouched = date
        if isRead {
            change.reads += 1
        } else {
            change.edits += 1
            change.linesAdded += step.linesAdded
            change.linesRemoved += step.linesRemoved
            // A Write to a file the agent never looked at is (almost always) a new file.
            if tool == "Write", known == nil { change.kind = .created } else if change.kind == .read { change.kind = .edited }
        }
        fileChanges[path] = change
    }

    /// Same call failing again and again = a loop. A success of that call resolves it.
    private mutating func trackLoop(_ step: TurnStep, index: Int) {
        guard let tool = step.toolName else { return }
        let signature = tool + "|" + Self.normalize(step.target)
        if step.isError {
            let streak = (failureStreaks[signature] ?? 0) + 1
            failureStreaks[signature] = streak
            steps[index].iteration = streak
            let iteration = LoopInfo.Iteration(duration: step.duration ?? 0, tokens: step.tokens,
                                               errorText: Self.normalize(step.errorText ?? ""))
            if streak == 1 { return }
            let label = "\(lastEditLabel ?? "retry")→\(Self.commandWord(step))"
            if streak == 2 {
                // The first failure only becomes part of a loop in hindsight.
                let first = steps[..<index].last { $0.toolName == tool && Self.normalize($0.target) == Self.normalize(step.target) && $0.isError }
                let opening = LoopInfo.Iteration(duration: first?.duration ?? 0, tokens: first?.tokens ?? 0,
                                                 errorText: Self.normalize(first?.errorText ?? ""))
                loops.append(LoopInfo(label: label, tool: tool, signature: signature, iterations: [opening, iteration], resolved: false))
            } else if let open = loops.lastIndex(where: { !$0.resolved && $0.signature == signature }) {
                loops[open].iterations.append(iteration)
            }
        } else if failureStreaks.removeValue(forKey: signature) != nil {
            for open in loops.indices where loops[open].signature == signature { loops[open].resolved = true }
        }
    }

    private mutating func touchBrain(_ layer: BrainItem.Layer, name: String, tokens: Int, activity: ActivityKind, at date: Date) {
        guard !name.isEmpty else { return }
        let key = "\(layer.rawValue)-\(name)"
        var item = brainItems[key] ?? BrainItem(layer: layer, name: name, tokens: 0, activity: activity, lastTurn: turnIndex, lastTouched: date)
        item.tokens += tokens
        item.lastTurn = turnIndex
        item.lastTouched = date
        brainItems[key] = item
    }

    /// The heaviest, most recent items per layer.
    public func brain(perLayer limit: Int = 6) -> [BrainItem] {
        BrainItem.Layer.allCases.flatMap { layer in
            brainItems.values.filter { $0.layer == layer }
                .sorted { ($0.lastTurn, $0.tokens) > ($1.lastTurn, $1.tokens) }
                .prefix(limit)
                .sorted { $0.lastTouched < $1.lastTouched }
        }
    }

    private mutating func applyPlan(_ op: TranscriptEvent.PlanOp) {
        if outputAtFirstTask == nil { outputAtFirstTask = usage.output }
        switch op {
        case .create(let subject):
            plan.append(PlanStep(id: "\(plan.count + 1)", title: subject, status: .pending))
        case .update(let taskId, let status):
            guard let index = plan.firstIndex(where: { $0.id == taskId }) else { return }
            if status == "deleted" { plan.remove(at: index) } else { plan[index].status = PlanStep.Status(raw: status) }
        case .replace(let todos):
            plan = todos.enumerated().map { PlanStep(id: "\($0.offset + 1)", title: $0.element.title, status: $0.element.status) }
        }
    }

    /// Remaining steps × mean output tokens per finished step ÷ current output rate.
    public mutating func etaMinutes(now: Date = Date()) -> Int? {
        let done = plan.filter { $0.status == .completed }.count
        let rate = tokensPerMinute(now: now)
        guard done > 0, done < plan.count, rate > 0, let start = outputAtFirstTask else { return nil }
        let perStep = Double(usage.output - start) / Double(done)
        return max(1, Int(Double(plan.count - done) * perStep / Double(rate)))
    }

    // MARK: Activity + ticker

    private mutating func set(_ kind: ActivityKind, lane: ActivityKind? = nil, at date: Date) {
        guard kind != activity else { return }
        activity = kind
        activitySince = date
        if let last = lanes.indices.last, lanes[last].end == nil { lanes[last].end = date }
        lanes.append(LaneSegment(start: date, end: nil, kind: lane ?? kind))
        if lanes.count > 4000 { lanes.removeFirst(lanes.count - 4000) }
    }

    private mutating func push(_ kind: ActivityKind, _ text: String, at date: Date) {
        serial += 1
        ticker.append(TickerItem(id: "\(serial)", date: date, kind: kind,
                                 text: TranscriptParser.snippet(text, limit: 200)))
        if ticker.count > Self.tickerLimit { ticker.removeFirst(ticker.count - Self.tickerLimit) }
    }

    public func lanes(since cutoff: Date) -> [LaneSegment] {
        lanes.filter { ($0.end ?? .distantFuture) > cutoff }
    }

    // MARK: Throughput

    static func bucket(for date: Date) -> Int { Int(date.timeIntervalSince1970 / bucketSeconds) }

    /// Output tokens per bucket for the window ending at `now`, oldest first.
    public mutating func heartbeat(now: Date = Date()) -> [Int] {
        let last = Self.bucket(for: now)
        let first = last - Self.bucketCount + 1
        buckets = buckets.filter { $0.key >= first }
        return (first...last).map { buckets[$0] ?? 0 }
    }

    /// Output tokens over the trailing minute.
    public mutating func tokensPerMinute(now: Date = Date()) -> Int {
        heartbeat(now: now).suffix(Int(60 / Self.bucketSeconds)).reduce(0, +)
    }

    // MARK: Naming helpers

    static func displayName(_ tool: String) -> String {
        guard tool.hasPrefix("mcp__") else { return tool }
        return tool.split(separator: "_").last.map(String.init) ?? tool
    }

    static func shortTarget(_ call: TranscriptEvent.ToolCall) -> String {
        if call.target.hasPrefix("/") { return (call.target as NSString).lastPathComponent }
        return TranscriptParser.snippet(call.name == "Bash" ? call.target : (call.summary.isEmpty ? call.target : call.summary), limit: 28)
    }

    /// First meaningful word of a command: "cd x && swift test" → "swift".
    static func commandWord(_ step: TurnStep) -> String {
        let last = step.target.components(separatedBy: "&&").last ?? step.target
        let word = last.split(separator: " ").first { !$0.contains("=") }.map(String.init) ?? step.label
        return (word as NSString).lastPathComponent.lowercased()
    }

    /// Strips digits and whitespace noise so "exit 1 in 3.2s" equals "exit 1 in 4.0s".
    static func normalize(_ text: String) -> String {
        String(text.lowercased().filter { !$0.isNumber && !$0.isWhitespace }.prefix(120))
    }
}
