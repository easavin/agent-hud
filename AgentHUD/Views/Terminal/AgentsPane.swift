import HUDCore
import SwiftUI

/// ─ agents ─ : one padded line per session, selected row marked `▸` on a full-width band.
struct AgentsPane: View {
    let rows: [AgentSnapshot]
    let selectedId: String?
    let select: (String) -> Void

    /// 118px pane − 20 top − 8 bottom leaves 90: six 15px lines, header included, with nothing clipped.
    static let rowHeight: CGFloat = 15
    static let visibleRows = 5

    private var window: ArraySlice<AgentSnapshot> {
        guard rows.count > Self.visibleRows else { return rows[...] }
        let selected = rows.firstIndex { $0.id == selectedId } ?? 0
        let start = max(0, min(rows.count - Self.visibleRows, selected - Self.visibleRows + 1))
        return rows[start..<(start + Self.visibleRows)]
    }

    var body: some View {
        TermPane(title: "agents", hint: hint) {
            VStack(alignment: .leading, spacing: 0) {
                TermText(header, height: Self.rowHeight)
                ForEach(Array(window)) { agent in
                    TermText(line(for: agent), height: Self.rowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(agent.id == selectedId ? Term.rowSelected : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { select(agent.id) }
                }
                if rows.isEmpty {
                    TermText(TermRow("no sessions — start one with `claude`", Term.mute), height: Self.rowHeight)
                }
            }
        }
    }

    private var hint: TermRow? {
        guard rows.count > Self.visibleRows else { return nil }
        return TermRow("+\(rows.count - Self.visibleRows) more  [↑↓]", Term.mute)
    }

    private var header: TermRow {
        TermRow("  " + Term.pad("NAME", 11) + "  " + Term.pad("MODEL", 10) + "  " + Term.pad("STATUS", 9)
                + "  " + Term.pad("CTX", 10) + "  " + Term.padStart("TOK", 6) + "  " + Term.padStart("UP", 7)
                + "   " + "HEARTBEAT", Term.mute)
    }

    private func line(for agent: AgentSnapshot) -> TermRow {
        let selected = agent.id == selectedId
        let activity: ActivityKind = agent.isEnded ? .idle : (agent.isLooping ? .error : agent.activity)
        let color = Term.color(for: activity)
        let status = agent.isEnded ? "ended" : (agent.isLooping ? "loop ×\(agent.activeLoop?.count ?? 0)" : activity.word)

        var row = TermRow(selected ? "▸" : " ", Term.reading)
        row.add(" " + Term.pad(agent.repo, 11), Term.ink)
        row.add("  " + Term.pad(CostEstimator.shortName(agent.model ?? "—"), 10), Term.mute)
        row.add("  " + Term.pad(status, 9), color)

        let fill = agent.contextFill
        row.add("  ")
        row.add(Term.bar(fill, 10, fill: "█"), fill >= 0.75 ? Term.error : fill >= 0.6 ? Term.editing : Term.reading)

        row.add("  " + Term.padStart(agent.usage.total.compact, 6), Term.ink)
        let up = agent.startedAt.map { (agent.endedAt ?? Date()).timeIntervalSince($0).elapsedText } ?? "—"
        row.add("  " + Term.padStart(up, 7), Term.ink)
        row.add("   ")
        // A waiting agent's heartbeat is flat, not noise from an old burst.
        row.add(activity.isActive ? Term.spark(agent.heartbeat, 12) : String(repeating: "▁", count: 12),
                activity.isActive ? color : Term.waiting)
        return row
    }
}
