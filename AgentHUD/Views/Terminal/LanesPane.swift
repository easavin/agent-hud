import HUDCore
import SwiftUI

/// ─ lanes · 60m ─ : one 90-cell row per agent, "now" pinned at the right edge.
struct LanesPane: View {
    let agents: [AgentSnapshot]
    @Binding var hover: String?

    static let cells = 90
    static let window: TimeInterval = 60 * 60
    static let rowHeight: CGFloat = 18
    static let nameWidth = 11
    /// Cell 0 of the track, in columns from the left edge of the pane's content.
    static let trackColumn = nameWidth + 1
    static let visibleRows = 5

    var body: some View {
        TermPane(title: "lanes · 60m", hint: hover.map { TermRow($0, Term.mute) } ?? extra) {
            // One redraw a second keeps the 40-second cell shift honest without costing anything.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(agents.prefix(Self.visibleRows))) { agent in
                        row(for: agent, now: timeline.date)
                    }
                    if agents.isEmpty {
                        TermText(TermRow("no sessions to plot", Term.mute), height: Self.rowHeight)
                    }
                    TermText(axis)
                }
            }
        }
    }

    private var extra: TermRow? {
        guard agents.count > Self.visibleRows else { return nil }
        return TermRow("+\(agents.count - Self.visibleRows) more", Term.mute)
    }

    private func row(for agent: AgentSnapshot, now: Date) -> some View {
        let cells = Self.cells(for: agent, now: now)
        return TermText(line(agent: agent, cells: cells), height: Self.rowHeight)
            .onContinuousHover { phase in
                guard case let .active(point) = phase else { return hover = nil }
                let cell = Int(point.x / Term.cell) - Self.trackColumn
                guard cells.indices.contains(cell) else { return hover = nil }
                let date = now.addingTimeInterval(-Self.window * Double(Self.cells - cell) / Double(Self.cells))
                hover = "\(date.shortClockText) · \(cells[cell].kind.word) · \(agent.repo)"
            }
    }

    private func line(agent: AgentSnapshot, cells: [Cell]) -> TermRow {
        var row = TermRow(Term.pad(agent.repo, Self.nameWidth) + " ", Term.ink)
        // Runs of the same color collapse into one attributed run, so a lane is a handful of spans.
        var index = 0
        while index < cells.count {
            var end = index
            while end < cells.count, cells[end] == cells[index] { end += 1 }
            let cell = cells[index]
            row.add(String(repeating: cell.glyph, count: end - index), cell.color)
            index = end
        }
        row.add("┃", Term.reading)
        return row
    }

    /// `-60m … -15m now`, positioned on the same cells the track uses.
    private var axis: TermRow {
        var row = TermRow()
        for (cell, label) in [(0, "-60m"), (22, "-45m"), (44, "-30m"), (66, "-15m")] {
            row.space(to: Self.trackColumn + cell)
            row.add(label, Term.mute)
        }
        row.space(to: Self.trackColumn + Self.cells - 3)
        row.add("now", Term.reading)
        return row
    }

    // MARK: Cells

    struct Cell: Equatable {
        var kind: ActivityKind
        var isPrompt = false

        var glyph: Character { isPrompt ? "▏" : "█" }
        var color: Color { isPrompt ? Term.ink : kind == .idle ? Term.border : Term.color(for: kind) }
    }

    /// Cell boundaries are cumulative (`end = round(t / 60min × 90)`) so every row is exactly 90 wide.
    static func cells(for agent: AgentSnapshot, now: Date) -> [Cell] {
        var cells = [Cell](repeating: Cell(kind: .idle), count: Self.cells)
        let start = now.addingTimeInterval(-window)
        func cell(_ date: Date) -> Int {
            Int((date.timeIntervalSince(start) / window * Double(Self.cells)).rounded())
        }
        for segment in agent.lanes {
            let end = segment.end ?? agent.endedAt ?? now
            guard end > start else { continue }
            let from = max(0, cell(segment.start)), to = min(Self.cells, cell(end))
            guard from < Self.cells, to > from else { continue }
            for index in from..<to { cells[index] = Cell(kind: segment.kind) }
        }
        for tick in agent.promptTicks where tick > start {
            let index = min(Self.cells - 1, max(0, cell(tick)))
            cells[index] = Cell(kind: cells[index].kind, isPrompt: true)
        }
        return cells
    }
}
