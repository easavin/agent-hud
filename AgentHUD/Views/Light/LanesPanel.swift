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

    static let trackX: CGFloat = 96, trackWidth: CGFloat = 560, rowHeight: CGFloat = 28
    static let playheadX: CGFloat = 658
    static let canvas = CGSize(width: 688, height: 170)

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                CardHeader(title: "Activity", suffix: range.title) {
                    Segmented(options: LaneRange.allCases.map { ($0.label, $0) }, selection: $range)
                }
                // A redraw a second is plenty: 560px cover at least 15 minutes.
                TimelineView(.periodic(from: .now, by: reduceMotion ? 60 : 1)) { timeline in
                    Canvas { context, _ in draw(&context, now: timeline.date) }
                        .frame(width: Self.canvas.width, height: Self.canvas.height)
                }
                .padding(.leading, 8).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, now: Date) {
        let window = TimeInterval(range.rawValue * 60)
        let start = now.addingTimeInterval(-window)
        func x(_ date: Date) -> CGFloat {
            Self.trackX + Self.trackWidth * max(0, min(1, date.timeIntervalSince(start) / window))
        }
        let rows = Array(agents.prefix(5))
        let gridBottom: CGFloat = 146

        // Dashed gridlines at each quarter of the window, labelled below the lanes.
        for quarter in 1..<4 {
            let gx = Self.trackX + Self.trackWidth * CGFloat(quarter) / 4
            var line = Path()
            line.move(to: CGPoint(x: gx, y: 0)); line.addLine(to: CGPoint(x: gx, y: gridBottom))
            context.stroke(line, with: .color(Theme.divider), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        for quarter in 0..<4 {
            let gx = Self.trackX + Self.trackWidth * CGFloat(quarter) / 4
            let minutes = range.rawValue * (4 - quarter) / 4
            context.label(minutes >= 120 ? "-\(minutes / 60)h" : "-\(minutes)m",
                          at: CGPoint(x: gx, y: 154), size: 10, color: Theme.mute)
        }

        for (row, agent) in rows.enumerated() {
            let top = CGFloat(row) * Self.rowHeight + 6
            context.label(String(agent.repo.prefix(13)), at: CGPoint(x: 0, y: top + 8), size: 12, weight: .medium,
                          color: Theme.ink, anchor: .leading)
            context.fill(Path(roundedRect: CGRect(x: Self.trackX, y: top, width: Self.trackWidth, height: 16),
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
        playhead.move(to: CGPoint(x: Self.playheadX, y: 0)); playhead.addLine(to: CGPoint(x: Self.playheadX, y: gridBottom))
        context.stroke(playhead, with: .color(Theme.ink), lineWidth: 2)
        context.label("now", at: CGPoint(x: Self.playheadX, y: 154), size: 10, weight: .semibold, color: Theme.ink)

        if rows.isEmpty {
            context.label("No sessions to plot", at: CGPoint(x: Self.canvas.width / 2, y: 70), size: 13, color: Theme.mute)
        }
    }
}
