import HUDCore
import SwiftUI

/// App icon and live Dock tile: a flat terminal square with a block-bar history of output tokens
/// over the last five minutes, one color per session — Activity Monitor's CPU meter in this palette.
struct DockTileView: View {
    let monitor: AgentMonitor
    static let bars = 30
    /// One fixed color per session slot, so a bar keeps its color as it scrolls left.
    static let palette = [Term.running, Term.reading, Term.editing, Term.thinking, Term.subagent]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // A live tile reads best large; leave just enough margin for the Dock's running dot.
            let body = side * 0.9, unit = body / 100
            let alert = monitor.mood == .alert
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: body * 0.18, style: .continuous).fill(Term.bg)
                Canvas { context, size in draw(&context, size: size, unit: unit) }
                    .padding(.horizontal, 9 * unit).padding(.top, 30 * unit).padding(.bottom, 10 * unit)
                HStack(alignment: .firstTextBaseline, spacing: 3 * unit) {
                    Text(monitor.agents.isEmpty ? "—" : monitor.tokensPerMinute.compact)
                        .font(.custom(Term.fontName, fixedSize: 17 * unit).weight(.bold))
                        .foregroundStyle(alert ? Term.error : Term.ink)
                    Text("t/m").font(.custom(Term.fontName, fixedSize: 9 * unit)).foregroundStyle(Term.mute)
                    Spacer(minLength: 0)
                    Rectangle().fill(alert ? Term.error : monitor.activeCount > 0 ? Term.running : Term.waiting)
                        .frame(width: 7 * unit, height: 7 * unit)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 10 * unit).padding(.top, 8 * unit)
                RoundedRectangle(cornerRadius: body * 0.18, style: .continuous)
                    .strokeBorder(alert ? Term.error : Term.border, lineWidth: max(1, 1.2 * unit))
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
                context.fill(Path(CGRect(x: x, y: size.height - 1.2 * unit, width: width, height: 1.2 * unit)), with: .color(Term.border))
            }
        }
    }
}
