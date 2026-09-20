import HUDCore
import SwiftUI

/// Turns the steps of a turn into an ASCII tree: one node per line, 6 cells of indent per depth,
/// `└─▶ ├─▶` connectors, dashed `╌╌▶` branches for subagents and a box return for retry loops.
struct FlowTree {
    struct Line: Identifiable {
        let id: Int
        var row: TermRow
        /// The step this line stands for; `nil` for the connector lines of a loop box.
        var stepId: String?
    }

    private(set) var lines: [Line] = []
    /// How many lines were dropped off the top to fit the pane.
    private(set) var hidden = 0

    /// Connector column for a depth; the node text starts 4 cells later.
    static func connectorColumn(_ depth: Int) -> Int { max(0, 6 * depth - 4) }
    /// Real turns run twenty rounds deep. Past this the tree stops nesting and rounds become
    /// siblings, so a long turn stays readable instead of marching off the right edge.
    static let maxDepth = 4
    /// Longest argument printed on a node line before it is cut.
    static let maxArgument = 64
    /// Where a subagent's dashed branch turns back down into the next line.
    static let returnColumn = 104

    init(agent: AgentSnapshot, maxLines: Int) {
        let subagents = Dictionary(agent.subagents.map { ($0.toolUseId, $0) }, uniquingKeysWith: { first, _ in first })
        let (steps, loopCounts) = Self.compressLoops(agent.steps)
        let depths = Self.depths(of: steps)

        var returnPending = false
        for (index, step) in steps.enumerated() {
            let depth = depths[index]
            let isLast = Self.isLastSibling(at: index, depths: depths)
            let subagent = step.toolName.map { ActivityClassifier.activity(forTool: $0) == .subagent } == true
                ? subagents[step.id] : nil

            var row = TermRow()
            if depth > 0 {
                row.space(to: Self.connectorColumn(depth))
                if subagent != nil || step.activity == .subagent {
                    row.add(isLast ? "└╌╌▶" : "├╌╌▶", Term.subagent)
                } else {
                    row.add(isLast ? "└─▶ " : "├─▶ ", Term.mute)
                }
            }
            row = row + Self.node(step, subagent: subagent)

            // A subagent's branch runs out to the right and merges back into the line below it.
            if subagent != nil, row.cols < Self.returnColumn - 2 {
                row.add(" " + String(repeating: "╌", count: Self.returnColumn - row.cols - 2) + "┐", Term.subagent)
                returnPending = true
            } else if returnPending, row.cols < Self.returnColumn - 2 {
                row.add(" ◀" + String(repeating: "─", count: Self.returnColumn - row.cols - 3) + "┘", Term.subagent)
                returnPending = false
            }

            // A failed call carries its failure on the same line, on the error background.
            if step.isError {
                row.add(" ──▶ ", Term.mute)
                row.add("✕ failed \(Self.shortError(step.errorText))", Term.error, bg: Term.errBg)
            }

            let count = loopCounts[step.id] ?? step.iteration
            if step.isError, count >= 2 {
                let right = row.cols + 3
                row.add(" ──┐ ", Term.ink)
                row.add("×\(count)", Term.error, weight: .bold)
                lines.append(Line(id: lines.count, row: row, stepId: step.id))
                lines.append(Line(id: lines.count, row: Self.loopArrow(depth: depth, right: right), stepId: nil))
                lines.append(Line(id: lines.count, row: Self.loopReturn(depth: depth, right: right), stepId: nil))
                continue
            }
            lines.append(Line(id: lines.count, row: row, stepId: step.id))
        }

        if lines.count > maxLines {
            hidden = lines.count - maxLines + 1
            var head = lines.first.map { [$0] } ?? []
            head.append(Line(id: -1, row: TermRow("  ⋯ +\(hidden) earlier", Term.mute), stepId: nil))
            lines = head + lines.suffix(maxLines - head.count)
        }
    }

    // MARK: One node

    /// `◐ thinking 8.4k`, `✎ Edit retry.py  [retry.py +42 −17]`, `◌ subagent explore tests ╌╌▶ ◌ 2.1k`.
    private static func node(_ step: TurnStep, subagent: SubagentInfo?) -> TermRow {
        var row = TermRow()
        switch step.kind {
        case .prompt:
            row.add("■ prompt", Term.ink)
            row.add(" " + clip(step.detail, 100), Term.mute)
        case .result:
            row.add("■ result", Term.ink)
            row.add(" " + clip(step.detail, 100), Term.mute)
        case .thinking:
            row.add("◐ thinking", Term.thinking)
            row.add(" " + step.tokens.compact, Term.mute)
        case .tool:
            let activity = step.isError ? ActivityClassifier.activity(forTool: step.toolName ?? "") : step.activity
            let label = activity == .subagent ? "subagent" : step.label
            row.add("\(Term.glyph(for: activity)) \(label)", Term.color(for: activity))
            if !step.detail.isEmpty { row.add(" " + clip(step.detail, maxArgument), Term.ink) }
            if let subagent {
                row.add(" ╌╌▶ ◌ " + subagent.usage.total.compact, Term.subagent)
            } else if step.tokens > 0 {
                row.add(" " + step.tokens.compact, Term.mute)
            }
            if step.linesAdded > 0 || step.linesRemoved > 0 {
                row.add("  [" + URL(fileURLWithPath: step.target).lastPathComponent, Term.editing)
                if step.linesAdded > 0 { row.add(" +\(step.linesAdded)", Term.running) }
                if step.linesRemoved > 0 { row.add(" −\(step.linesRemoved)", Term.error) }
                row.add("]", Term.editing)
            }
            if step.isRunning { row.add(" …", Term.mute) }
        }
        return row
    }

    /// `│   ▲                     │` — the upward arrow of a loop's box return.
    private static func loopArrow(depth: Int, right: Int) -> TermRow {
        var row = TermRow()
        row.space(to: connectorColumn(depth))
        row.add("│   ▲", Term.ink)
        row.space(to: right)
        row.add("│", Term.ink)
        return row
    }

    /// `│   └─────────────────────┘`
    private static func loopReturn(depth: Int, right: Int) -> TermRow {
        var row = TermRow()
        row.space(to: connectorColumn(depth))
        row.add("│   └", Term.ink)
        row.add(String(repeating: "─", count: max(0, right - row.cols)), Term.ink)
        row.add("┘", Term.ink)
        return row
    }

    /// A node is the last of its siblings when no later step sits at the same depth before the tree
    /// climbs back out — children (deeper steps) do not make it a `├`.
    private static func isLastSibling(at index: Int, depths: [Int]) -> Bool {
        let depth = depths[index]
        for next in depths[(index + 1)...] {
            if next == depth { return false }
            if next < depth { return true }
        }
        return true
    }

    // MARK: Steps → depth

    /// The prompt is depth 0, its first thinking depth 1, and every new group of tool calls nests one
    /// level deeper. Thinking between two groups is a sibling of the group it follows, so a long turn
    /// grows by one indent per round of tools rather than two.
    private static func depths(of steps: [TurnStep]) -> [Int] {
        var result: [Int] = []
        var current = 0
        var lastGroup: Int?
        for step in steps {
            switch step.kind {
            case .prompt:
                current = 0
            case .thinking:
                current = result.isEmpty ? 1 : current
                lastGroup = nil
            case .tool:
                if step.group != lastGroup { current = min(maxDepth, current + 1) }
                lastGroup = step.group
            case .result:
                lastGroup = nil
            }
            result.append(current)
        }
        return result
    }

    // MARK: Loop compression

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

    /// Cuts a value to `width` cells, marking the cut with `…`.
    static func clip(_ text: String, _ width: Int) -> String {
        text.count <= width ? text : String(text.prefix(width - 1)) + "…"
    }

    static func shortError(_ text: String?) -> String {
        guard let text = text.map(clean), !text.isEmpty else { return "error" }
        if let range = text.range(of: #"[Ee]xit code \d+"#, options: .regularExpression) {
            return String(text[range]).lowercased().replacingOccurrences(of: " code", with: "")
        }
        return clip(text, 20)
    }

    /// Tool results arrive wrapped in `<tool_use_error>…`; the wrapper is noise on a one-line node.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"</?tool_use_error>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
