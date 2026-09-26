import HUDCore
import SwiftUI

enum LaneRange: Int, CaseIterable {
    case quarter = 15, hour = 60, sixHours = 360
    var label: String { self == .sixHours ? "6h" : "\(rawValue)m" }
    var title: String { self == .sixHours ? "last 6 hours" : "last \(rawValue) min" }
}

/// Center bottom card: one profiler lane per session, "now" pinned at the playhead.
struct LanesPanel: View {
    let agents: [AgentSnapshot]
    @Binding var range: LaneRange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let trackX: CGFloat = 96, rowHeight: CGFloat = 28
    /// Lanes shrink toward this before any are left out.
    static let minRowHeight: CGFloat = 18
    /// Room kept to the right of the track for the playhead and its label.
    static let tailWidth: CGFloat = 32

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                CardHeader(title: "Activity", suffix: range.title) {
                    Segmented(options: LaneRange.allCases.map { ($0.label, $0) }, selection: $range)
                }
                // A redraw a second keeps the lane scroll honest without costing anything.
                TimelineView(.periodic(from: .now, by: reduceMotion ? 60 : 1)) { timeline in
                    Canvas { context, size in draw(&context, size: size, now: timeline.date) }
                }
                .padding(.leading, 8).padding(.trailing, 4).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let window = TimeInterval(range.rawValue * 60)
        let start = now.addingTimeInterval(-window)
        let trackWidth = max(120, size.width - Self.trackX - Self.tailWidth)
        let playheadX = Self.trackX + trackWidth + 2
        func x(_ date: Date) -> CGFloat {
            Self.trackX + trackWidth * max(0, min(1, date.timeIntervalSince(start) / window))
        }
        // Live sessions always get a lane; a finished one only if it did something in this range.
        let plotted = agents.filter { agent in
            guard let ended = agent.endedAt else { return true }
            return agent.promptTicks.contains { $0 > start }
                || agent.lanes.contains { $0.kind != .idle && ($0.end ?? ended) > start }
        }
        // Lanes shrink to fit the pane (less the axis' 26px) before any are left out.
        let room = size.height - 26 - 6
        let rowHeight = max(Self.minRowHeight, min(Self.rowHeight, room / CGFloat(max(1, plotted.count))))
        let rows = Array(plotted.prefix(max(1, Int(room / rowHeight))))
        let hidden = plotted.count - rows.count
        let barHeight = max(8, rowHeight - 12)
        let gridBottom = max(20, CGFloat(rows.count) * rowHeight + 6)

        // Dashed gridlines at each quarter of the window, labelled below the lanes.
        for quarter in 1..<4 {
            let gx = Self.trackX + trackWidth * CGFloat(quarter) / 4
            var line = Path()
            line.move(to: CGPoint(x: gx, y: 0)); line.addLine(to: CGPoint(x: gx, y: gridBottom))
            context.stroke(line, with: .color(Theme.divider), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        for quarter in 0..<4 {
            let gx = Self.trackX + trackWidth * CGFloat(quarter) / 4
            let minutes = range.rawValue * (4 - quarter) / 4
            context.label(minutes >= 120 ? "-\(minutes / 60)h" : "-\(minutes)m",
                          at: CGPoint(x: gx, y: gridBottom + 8), size: 10, color: Theme.mute)
        }

        for (row, agent) in rows.enumerated() {
            let top = CGFloat(row) * rowHeight + 6
            let name = context.fit(agent.repo, to: Self.trackX - 10, size: rowHeight < 24 ? 11 : 12, weight: .medium, cutEnd: true)
            context.label(name, at: CGPoint(x: 0, y: top + barHeight / 2), size: rowHeight < 24 ? 11 : 12, weight: .medium,
                          color: agent.isEnded ? Theme.mute : Theme.ink, anchor: .leading)
            context.fill(Path(roundedRect: CGRect(x: Self.trackX, y: top, width: trackWidth, height: barHeight),
                              cornerRadius: Theme.Radius.laneTrack), with: .color(Theme.track))
            for segment in agent.lanes {
                // A finished session's last segment stops when the session did, not at the playhead.
                let end = segment.end ?? agent.endedAt ?? now
                guard end > start, segment.kind != .idle else { continue }
                let from = x(max(segment.start, start)), to = x(end)
                let rect = CGRect(x: from, y: top, width: max(1, to - from), height: barHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: 1),
                             with: .color(Theme.color(for: segment.kind).opacity(segment.kind == .waiting ? 0.45 : 1)))
            }
            for tick in agent.promptTicks where tick > start {
                context.fill(Path(CGRect(x: x(tick), y: top - 5, width: 2, height: 4)), with: .color(Theme.ink))
            }
        }

        var playhead = Path()
        playhead.move(to: CGPoint(x: playheadX, y: 0)); playhead.addLine(to: CGPoint(x: playheadX, y: gridBottom))
        context.stroke(playhead, with: .color(Theme.ink), lineWidth: 2)
        context.label("now", at: CGPoint(x: playheadX, y: gridBottom + 8), size: 10, weight: .semibold, color: Theme.ink)

        if hidden > 0 {
            context.label("+\(hidden) more", at: CGPoint(x: 0, y: gridBottom + 8), size: 10, color: Theme.mute, anchor: .leading)
        }
        if rows.isEmpty {
            context.label("No sessions to plot", at: CGPoint(x: size.width / 2, y: 60), size: 13, color: Theme.mute)
        }
    }
}
