import CoreGraphics
import HUDCore

/// Turns the steps of a turn into positioned nodes and edges for the flow graph.
struct FlowLayout {
    enum Style { case prompt, thinking, tool, error, subagent, result }

    struct Node: Identifiable {
        let id: String
        var style: Style
        var activity: ActivityKind
        var center: CGPoint
        var radius: CGFloat
        var label: String
        var sub: String
        var step: TurnStep
        var loopCount = 0
        var isRunning = false
        /// Set for nodes that spawned a subagent whose transcript we found.
        var subagent: SubagentInfo?
    }

    struct Edge {
        var from: Int
        var to: Int
        var dashed = false
    }

    struct LoopEdge {
        var from: Int
        var to: Int
        var count: Int
    }

    var nodes: [Node] = []
    var edges: [Edge] = []
    var loopEdges: [LoopEdge] = []
    /// Columns dropped from the middle because the turn is longer than the canvas.
    var hiddenColumns = 0

    static let canvas = CGSize(width: 688, height: 300)
    static let pitch: CGFloat = 84
    static let firstX: CGFloat = 36
    static let maxPerColumn = 4

    /// The canvas this layout was built for; a wider pane simply fits more columns.
    private(set) var size = FlowLayout.canvas
    var midY: CGFloat { size.height * 0.47 }

    init(steps: [TurnStep], subagents: [SubagentInfo] = [], size: CGSize = FlowLayout.canvas) {
        self.size = size
        let width = size.width
        let spawned = Dictionary(subagents.map { ($0.toolUseId, $0) }, uniquingKeysWith: { first, _ in first })
        let compressed = Self.compressLoops(steps)
        var columns = Self.columns(from: compressed.steps)
        let capacity = max(3, Int((width - Self.firstX * 2) / Self.pitch) + 1)
        if columns.count > capacity {
            hiddenColumns = columns.count - capacity
            columns = [columns[0]] + columns.suffix(capacity - 1)
        }

        var columnNodes: [[Int]] = []
        for (columnIndex, column) in columns.enumerated() {
            let shown = Array(column.prefix(Self.maxPerColumn))
            let spacing = min(56, (size.height - 70) / CGFloat(max(1, shown.count)))
            var indices: [Int] = []
            for (row, entry) in shown.enumerated() {
                let y = midY + (CGFloat(row) - CGFloat(shown.count - 1) / 2) * spacing
                var node = Self.node(for: entry, at: CGPoint(x: Self.firstX + CGFloat(columnIndex) * Self.pitch, y: y))
                if row == Self.maxPerColumn - 1, column.count > shown.count { node.sub = "+\(column.count - shown.count) more" }
                node.loopCount = compressed.loopCounts[entry.step.id] ?? 0
                if node.style == .subagent, let info = spawned[entry.step.id] {
                    // Show who did the work: agent type on top, the model it ran on and what it spent below.
                    node.subagent = info
                    node.label = info.agentType
                    node.sub = "\(CostEstimator.shortName(info.model ?? "?")) · \(info.usage.total.compact)"
                    node.radius = min(20, max(10, 10 + 0.9 * (Double(info.usage.output) / 100).squareRoot()))
                    node.isRunning = info.isRunning()
                }
                indices.append(nodes.count)
                nodes.append(node)
            }
            columnNodes.append(indices)
        }

        for (left, right) in zip(columnNodes, columnNodes.dropFirst()) {
            if left.count > 1, right.count > 1 {
                for (a, b) in zip(left, right) { edges.append(Edge(from: a, to: b, dashed: nodes[b].style == .subagent)) }
            } else {
                for a in left { for b in right { edges.append(Edge(from: a, to: b, dashed: nodes[b].style == .subagent || nodes[a].style == .subagent)) } }
            }
        }

        // A loop edge runs from the failed node back to the edit that retried it.
        for (index, node) in nodes.enumerated() where node.style == .error && node.loopCount >= 2 {
            let target = nodes[..<index].lastIndex { $0.activity == .editing } ?? max(0, index - 2)
            loopEdges.append(LoopEdge(from: index, to: target, count: node.loopCount))
        }
    }

    // MARK: Steps → columns

    struct Entry {
        var step: TurnStep
        var isFailureMarker = false
    }

    /// Thinking, results and the prompt get their own column; tools called by one message share one.
    static func columns(from steps: [TurnStep]) -> [[Entry]] {
        var columns: [[Entry]] = []
        var lastToolGroup: Int?
        for step in steps {
            if step.kind == .tool, step.group == lastToolGroup, !columns.isEmpty, columns[columns.count - 1].allSatisfy({ !$0.isFailureMarker }) {
                columns[columns.count - 1].append(Entry(step: step))
            } else {
                columns.append([Entry(step: step)])
            }
            lastToolGroup = step.kind == .tool ? step.group : nil
            // A failed call is drawn as the call plus a red "failed" node after it.
            if step.isError {
                columns.append([Entry(step: step, isFailureMarker: true)])
                lastToolGroup = nil
            }
        }
        return columns
    }

    /// Collapses retries: keeps the first attempt's lead-up and only the latest iteration of the loop.
    static func compressLoops(_ steps: [TurnStep]) -> (steps: [TurnStep], loopCounts: [String: Int]) {
        var result = steps
        var counts: [String: Int] = [:]
        var index = 0
        while index < result.count {
            let step = result[index]
            defer { index += 1 }
            guard step.isError, step.iteration >= 2 else { continue }
            counts[step.id] = step.iteration
            // Earlier attempts may already have scrolled out of the step buffer.
            guard let first = result[..<index].firstIndex(where: { $0.isError && $0.toolName == step.toolName && $0.target == step.target })
            else { continue }
            let previous = result[..<index].lastIndex { $0.isError && $0.toolName == step.toolName && $0.target == step.target } ?? first
            let resume = result[(previous + 1)..<index].firstIndex { $0.activity == .editing } ?? index
            result.removeSubrange(first..<resume)
            index -= resume - first
        }
        return (result, counts)
    }

    static func node(for entry: Entry, at center: CGPoint) -> Node {
        let step = entry.step
        if entry.isFailureMarker {
            return Node(id: step.id + "-fail", style: .error, activity: .error, center: center, radius: 14,
                        label: "failed", sub: shortError(step.errorText), step: step)
        }
        // r = 10 + 0.9·√(tokens/100), clamped 10–26
        let radius = min(26, max(10, 10 + 0.9 * (Double(step.tokens) / 100).squareRoot()))
        switch step.kind {
        case .prompt:
            return Node(id: step.id, style: .prompt, activity: .waiting, center: center, radius: 13, label: "prompt", sub: snippet(step.detail), step: step)
        case .result:
            return Node(id: step.id, style: .result, activity: .responding, center: center, radius: 11, label: "reply", sub: snippet(step.detail), step: step)
        case .thinking:
            return Node(id: step.id, style: .thinking, activity: .thinking, center: center, radius: radius,
                        label: "thinking", sub: "\(step.tokens.compact) tok", step: step)
        case .tool:
            let isSubagent = ActivityClassifier.activity(forTool: step.toolName ?? "") == .subagent
            let activity = step.isError ? ActivityClassifier.activity(forTool: step.toolName ?? "") : step.activity
            return Node(id: step.id, style: isSubagent ? .subagent : .tool, activity: activity, center: center,
                        radius: isSubagent ? 10 : radius, label: step.label, sub: snippet(step.detail), step: step, isRunning: step.isRunning)
        }
    }

    /// Node subtitles sit in an 88px column on an 84px pitch, so they are cut well before they collide.
    static func snippet(_ text: String, _ limit: Int = 14) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    static func shortError(_ text: String?) -> String {
        guard let text = text?.replacingOccurrences(of: #"</?tool_use_error>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "error" }
        if let range = text.range(of: #"[Ee]xit code \d+"#, options: .regularExpression) { return String(text[range]).lowercased() }
        return snippet(text)
    }
}
