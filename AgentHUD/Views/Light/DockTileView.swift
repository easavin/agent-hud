import HUDCore
import SwiftUI

/// App icon and live Dock tile: a white card carrying the ink "A", tok/min and a stacked history of
/// output tokens over the last five minutes — Activity Monitor's CPU meter in this palette.
struct DockTileView: View {
    let monitor: AgentMonitor
    static let bars = 30
    /// One fixed color per session slot, so a bar keeps its color as it scrolls left.
    static let palette = [Theme.reading, Theme.editing, Theme.thinking, Theme.running, Theme.subagent]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // A live tile reads best large; leave just enough margin for the Dock's running dot.
            let body = side * 0.9, unit = body / 100
            let alert = monitor.mood == .alert
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: body * 0.18, style: .continuous).fill(Theme.card)
                Canvas { context, size in draw(&context, size: size, unit: unit) }
                    .padding(.horizontal, 9 * unit).padding(.top, 34 * unit).padding(.bottom, 10 * unit)
                HStack(alignment: .center, spacing: 5 * unit) {
                    RoundedRectangle(cornerRadius: 4 * unit, style: .continuous)
                        .fill(alert ? Theme.error : Theme.ink)
                        .frame(width: 16 * unit, height: 16 * unit)
                        .overlay(Text("A").font(.system(size: 10 * unit, weight: .bold)).foregroundStyle(.white))
                    Text(monitor.agents.isEmpty ? "—" : monitor.tokensPerMinute.compact)
                        .font(.system(size: 15 * unit, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text("t/m").font(.system(size: 9 * unit, weight: .medium)).foregroundStyle(Theme.mute)
                    Spacer(minLength: 0)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 10 * unit).padding(.top, 9 * unit)
                RoundedRectangle(cornerRadius: body * 0.18, style: .continuous)
                    .strokeBorder(alert ? Theme.error : Theme.border, lineWidth: max(1, 1.2 * unit))
            }
            .frame(width: body, height: body)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, unit: CGFloat) {
        // Heartbeats are 5s buckets; two per bar gives 30 bars of 10 seconds.
        let series = monitor.agents.prefix(Self.palette.count).map { agent -> [Int] in
            let beat = Array(agent.heartbeat.suffix(Self.bars * 2))
            return stride(from: 0, to: max(0, beat.count - 1), by: 2).map { beat[$0] + beat[$0 + 1] }
        }
        let totals = (0..<Self.bars).map { bar in series.reduce(0) { $0 + ($1.indices.contains(bar) ? $1[bar] : 0) } }
        // A floor keeps one tiny reply from filling the whole tile.
        let peak = CGFloat(max(400, totals.max() ?? 0))
        let pitch = size.width / CGFloat(Self.bars), width = pitch * 0.74

        for bar in 0..<Self.bars {
            let x = CGFloat(bar) * pitch + (pitch - width) / 2
            var y = size.height
            for (index, values) in series.enumerated() where values.indices.contains(bar) && values[bar] > 0 {
                // Square-root height: spikes stay readable without flattening everything else.
                let height = max(1.5 * unit, size.height * (CGFloat(values[bar]) / peak).squareRoot() * CGFloat(values[bar]) / CGFloat(max(1, totals[bar])))
                y -= height
                context.fill(Path(CGRect(x: x, y: max(0, y), width: width, height: height)), with: .color(Self.palette[index]))
            }
            if totals[bar] == 0 {
                context.fill(Path(CGRect(x: x, y: size.height - 1.2 * unit, width: width, height: 1.2 * unit)), with: .color(Theme.divider))
            }
        }
    }
}
