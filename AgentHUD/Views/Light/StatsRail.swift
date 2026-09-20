import HUDCore
import SwiftUI

/// Right column: token burn, model mix + cache, tools + repos, the 12-week heatmap.
struct StatsRail: View {
    let monitor: AgentMonitor
    @Binding var burnRange: BurnRange

    var body: some View {
        let stats = monitor.stats
        VStack(spacing: 8) {
            burn(stats)
            mixAndCache(stats)
            toolsAndRepos(stats)
            heatmap(stats)
            Spacer(minLength: 0)
        }
    }

    // MARK: Token burn

    private func burn(_ stats: StatsSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Token burn").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 6)
                    Segmented(options: BurnRange.allCases.map { ($0.rawValue, $0) }, selection: $burnRange, compact: true)
                }
                BurnChart(points: stats.burn[burnRange] ?? [])
                    .frame(height: 72)
                HStack(spacing: 10) {
                    ForEach(BurnChart.series, id: \.name) { series in
                        HStack(spacing: 4) {
                            Rectangle().fill(series.color).frame(width: 7, height: 7)
                            Text(series.name).font(Theme.ui(10)).foregroundStyle(Theme.mute)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Model mix + cache

    private func mixAndCache(_ stats: StatsSnapshot) -> some View {
        Card {
            ViewThatFits(in: .horizontal) {
                mixAndCacheRow(stats, axis: .horizontal)
                mixAndCacheRow(stats, axis: .vertical)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func mixAndCacheRow(_ stats: StatsSnapshot, axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        layout {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model mix").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink)
                    HStack(spacing: 6) {
                        Donut(slices: stats.modelMix).frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(stats.modelMix.prefix(4), id: \.model) { slice in
                                HStack(spacing: 4) {
                                    Rectangle().fill(Theme.modelColor(slice.model)).frame(width: 7, height: 7)
                                    Text(slice.model).font(Theme.ui(10)).foregroundStyle(Theme.mute)
                                    Text("\(Int((slice.share * 100).rounded()))%")
                                        .font(Theme.ui(10, .semibold)).foregroundStyle(Theme.ink)
                                }
                                .lineLimit(1).fixedSize()
                            }
                            if stats.modelMix.isEmpty {
                                Text("no usage today").font(Theme.ui(10)).foregroundStyle(Theme.mute)
                            }
                        }
                    }
                }
                // The donut plus its legend never compresses; the cache figure takes what is left.
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cache hit rate").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink)
                    Text("\(Int((stats.cacheHitRate * 100).rounded()))%")
                        .font(Theme.ui(26, .semibold)).foregroundStyle(Theme.subagent)
                        .contentTransition(.numericText())
                    Text("\(stats.cacheRead.compact) / \(stats.cacheDenominator.compact) input")
                        .font(Theme.ui(11)).foregroundStyle(Theme.mute)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Tools + repos

    private func toolsAndRepos(_ stats: StatsSnapshot) -> some View {
        let toolPeak = max(1, stats.tools.first?.count ?? 1)
        let repoPeak = max(1, stats.repos.first?.tokens ?? 1)
        return Card {
            ViewThatFits(in: .horizontal) {
                toolsAndReposRow(stats, toolPeak: toolPeak, repoPeak: repoPeak, axis: .horizontal)
                toolsAndReposRow(stats, toolPeak: toolPeak, repoPeak: repoPeak, axis: .vertical)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func toolsAndReposRow(_ stats: StatsSnapshot, toolPeak: Int, repoPeak: Int, axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        layout {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Tools").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink)
                    ForEach(stats.tools.prefix(5), id: \.name) { tool in
                        row(tool.name, nameWidth: 36, barWidth: 52,
                            fraction: Double(tool.count) / Double(toolPeak),
                            color: Theme.color(for: ActivityClassifier.activity(forTool: tool.name)),
                            value: "\(tool.count)", valueWidth: 30)
                    }
                    if stats.tools.isEmpty { Text("nothing yet today").font(Theme.ui(11)).foregroundStyle(Theme.mute) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Repos").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink)
                    ForEach(stats.repos.prefix(5), id: \.name) { repo in
                        row(repo.name, nameWidth: 58, barWidth: 20,
                            fraction: Double(repo.tokens) / Double(repoPeak),
                            color: Theme.modelColor(repo.model),
                            value: repo.tokens.compact, valueWidth: 44)
                    }
                    if stats.repos.isEmpty { Text("nothing yet today").font(Theme.ui(11)).foregroundStyle(Theme.mute) }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// `Read ▇▇▇▇░ 412` — square bars on a `track` rail.
    private func row(_ name: String, nameWidth: CGFloat, barWidth: CGFloat, fraction: Double,
                     color: Color, value: String, valueWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(name).font(Theme.ui(11)).foregroundStyle(Theme.ink)
                .lineLimit(1).truncationMode(.tail).frame(width: nameWidth, alignment: .leading)
            BarTrack(fraction: fraction, color: color, width: barWidth, height: 8,
                     trackColor: Theme.track, radius: 0)
            Spacer(minLength: 0)
            Text(value).font(Theme.ui(11)).foregroundStyle(Theme.mute)
                .lineLimit(1).fixedSize().frame(width: valueWidth, alignment: .trailing)
        }
    }

    // MARK: Heatmap

    private func heatmap(_ stats: StatsSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Activity · 12 weeks").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 6)
                    Text(stats.isBackfilling ? "indexing…" : "tokens / day")
                        .font(Theme.ui(11)).foregroundStyle(Theme.mute)
                }
                Canvas { context, size in
                    // 12 columns of cells, sized to whatever width the rail has now.
                    let pitch = size.width / 12
                    for (week, days) in stats.heatmap.enumerated() {
                        for (day, value) in days.enumerated() {
                            guard let value else { continue }
                            let rect = CGRect(x: CGFloat(week) * pitch, y: CGFloat(day) * 10,
                                              width: max(4, pitch - 2), height: 8)
                            context.fill(Path(roundedRect: rect, cornerRadius: 1),
                                         with: .color(Theme.reading.opacity(0.06 + value * 0.89)))
                        }
                    }
                }
                .frame(height: 68)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Stacked area: input, output, cache-read, thinking. Flat fills at 90%, no top line.
struct BurnChart: View {
    let points: [BurnPoint]
    static let series: [(name: String, color: Color, value: (BurnPoint) -> Int)] = [
        ("input", Theme.reading, { $0.input }), ("output", Theme.editing, { $0.output }),
        ("cache-read", Theme.subagent, { $0.cacheRead }), ("thinking", Theme.thinking, { $0.thinking }),
    ]

    var body: some View {
        Canvas { context, size in
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height - 0.5)); baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(baseline, with: .color(Theme.borderStrong), lineWidth: 1)
            guard points.count > 1 else { return }

            // Cache reads are ~10× everything else; a square-root scale keeps the other series visible.
            let scaled = points.map { point in Self.series.map { Double($0.value(point)).squareRoot() } }
            let peak = max(1, scaled.map { $0.reduce(0, +) }.max() ?? 1) * 1.06
            let step = size.width / CGFloat(points.count - 1)
            var lower = [Double](repeating: 0, count: points.count)
            for (index, series) in Self.series.enumerated() {
                let upper = zip(lower, scaled).map { $0 + $1[index] }
                func y(_ value: Double) -> CGFloat { size.height - size.height * value / peak }
                var area = Path()
                for i in points.indices {
                    let point = CGPoint(x: CGFloat(i) * step, y: y(upper[i]))
                    if i == 0 { area.move(to: point) } else { area.addLine(to: point) }
                }
                for i in points.indices.reversed() { area.addLine(to: CGPoint(x: CGFloat(i) * step, y: y(lower[i]))) }
                area.closeSubpath()
                context.fill(area, with: .color(series.color.opacity(0.9)))
                lower = upper
            }
        }
    }
}

/// 56×56 donut, 9px stroke, 3° gaps, one arc per model.
struct Donut: View {
    let slices: [(model: String, share: Double)]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2 - 4.5
            context.stroke(Geometry.arc(center, radius, 0, 360), with: .color(Theme.track), lineWidth: 9)
            var cursor = 0.0
            for slice in slices where slice.share > 0.005 {
                let sweep = slice.share * 360
                let gap = slices.count > 1 ? 3.0 : 0
                context.stroke(Geometry.arc(center, radius, cursor + gap / 2, max(cursor + gap / 2 + 0.5, cursor + sweep - gap / 2)),
                               with: .color(Theme.modelColor(slice.model)), lineWidth: 9)
                cursor += sweep
            }
        }
    }
}
