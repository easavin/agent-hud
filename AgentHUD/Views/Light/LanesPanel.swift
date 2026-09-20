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
        // As many lanes as the pane has room for, once the axis has its 24px.
        let rows = Array(agents.prefix(max(1, Int((size.height - 26) / Self.rowHeight))))
        let gridBottom = max(20, CGFloat(rows.count) * Self.rowHeight + 6)

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
            let top = CGFloat(row) * Self.rowHeight + 6
            context.label(String(agent.repo.prefix(13)), at: CGPoint(x: 0, y: top + 8), size: 12, weight: .medium,
                          color: Theme.ink, anchor: .leading)
            context.fill(Path(roundedRect: CGRect(x: Self.trackX, y: top, width: trackWidth, height: 16),
                              cornerRadius: Theme.Radius.laneTrack), with: .color(Theme.track))
            for segment in agent.lanes {
                // A finished session's last segment stops when the session did, not at the playhead.
                let end = segment.end ?? agent.endedAt ?? now
                guard end > start, segment.kind != .idle else { continue }
                let from = x(max(segment.start, start)), to = x(end)
                let rect = CGRect(x: from, y: top, width: max(1, to - from), height: 16)
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

        if rows.isEmpty {
            context.label("No sessions to plot", at: CGPoint(x: size.width / 2, y: 60), size: 13, color: Theme.mute)
        }
    }
}
