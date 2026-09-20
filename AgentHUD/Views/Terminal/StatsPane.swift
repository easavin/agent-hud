import HUDCore
import SwiftUI

/// ─ stats ─ : the right column. Six stacked groups, all of them block-character charts.
struct StatsPane: View {
    let monitor: AgentMonitor
    @Binding var range: BurnRange

    /// 37 cells fit the 296px column; every line below is padded to that.
    static let width = 37
    static let line: CGFloat = 15
    static let heatLine: CGFloat = 13

    private static let series: [(name: String, color: Color, value: (BurnPoint) -> Int)] = [
        ("input", Term.reading, { $0.input }), ("output", Term.editing, { $0.output }),
        ("cache-read", Term.subagent, { $0.cacheRead }), ("thinking", Term.thinking, { $0.thinking }),
    ]

    var body: some View {
        let stats = monitor.stats
        TermPane(title: "stats", hint: stats.isBackfilling ? TermRow("indexing…", Term.mute) : nil) {
            VStack(alignment: .leading, spacing: 10) {
                burn(stats)
                modelMix(stats)
                cache(stats)
                tools(stats)
                repos(stats)
                heatmap(stats)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Token burn

    private func burn(_ stats: StatsSnapshot) -> some View {
        let points = stats.burn[range] ?? []
        return VStack(alignment: .leading, spacing: 0) {
            TermText(burnHeader, height: Self.line)
            ForEach(Self.series, id: \.name) { series in
                let values = points.map(series.value)
                TermText(TermRow(Term.pad(series.name, 11), Term.mute)
                    + TermRow(Term.spark(values, 24), values.contains { $0 > 0 } ? series.color : Term.waiting),
                         height: Self.line)
            }
        }
    }

    private var burnHeader: TermRow {
        var row = TermRow("token burn", Term.mute)
        var picker = TermRow()
        for option in BurnRange.allCases {
            if !picker.isEmpty { picker.space() }
            picker.add(option == range ? "[\(option.rawValue)]" : " \(option.rawValue) ", option == range ? Term.ink : Term.mute)
        }
        row.space(to: Self.width - picker.cols)
        return row + picker
    }

    // MARK: Model mix

    private func modelMix(_ stats: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TermText(TermRow("model mix", Term.mute), height: Self.line)
            ForEach(stats.modelMix.prefix(4), id: \.model) { slice in
                TermText(TermRow(Term.pad(slice.model, 11), Term.modelColor(slice.model))
                    + TermRow(Term.bar(slice.share, 20), Term.reading)
                    + TermRow(Term.padStart("\(Int((slice.share * 100).rounded()))%", 5), Term.ink),
                         height: Self.line)
            }
            if stats.modelMix.isEmpty { TermText(TermRow("no usage today", Term.mute), height: Self.line) }
        }
    }

    // MARK: Cache + cost

    private func cache(_ stats: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TermText(TermRow("cache hit  ", Term.mute)
                + TermRow(Term.bar(stats.cacheHitRate, 20), Term.subagent)
                + TermRow(Term.padStart("\(Int((stats.cacheHitRate * 100).rounded()))%", 5), Term.ink),
                     height: Self.line)
            TermText(TermRow("est. cost  ", Term.mute)
                + TermRow(String(format: "$%.2f", stats.costToday), Term.ink)
                + TermRow(String(format: "  +$%.2f/h", stats.costLastHour), Term.mute),
                     height: Self.line)
        }
    }

    // MARK: Bar lists

    private func tools(_ stats: StatsSnapshot) -> some View {
        let peak = max(1, stats.tools.first?.count ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            TermText(TermRow("tools", Term.mute), height: Self.line)
            ForEach(stats.tools.prefix(5), id: \.name) { tool in
                TermText(TermRow(Term.pad(tool.name, 7), Term.ink2)
                    + TermRow(Term.bar(Double(tool.count) / Double(peak), 14), Term.editing)
                    + TermRow(Term.padStart("\(tool.count)", 5), Term.mute),
                         height: Self.line)
            }
            if stats.tools.isEmpty { TermText(TermRow("nothing yet today", Term.mute), height: Self.line) }
        }
    }

    private func repos(_ stats: StatsSnapshot) -> some View {
        let peak = max(1, stats.repos.first?.tokens ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            TermText(TermRow("repos", Term.mute), height: Self.line)
            ForEach(stats.repos.prefix(5), id: \.name) { repo in
                TermText(TermRow(Term.pad(repo.name, 12), Term.ink2)
                    + TermRow(Term.bar(Double(repo.tokens) / Double(peak), 10), Term.reading)
                    + TermRow(Term.padStart(repo.tokens.compact, 7), Term.mute),
                         height: Self.line)
            }
            if stats.repos.isEmpty { TermText(TermRow("nothing yet today", Term.mute), height: Self.line) }
        }
    }

    // MARK: Heatmap

    /// 7 rows (weekday) × 12 columns (week) of `░▒▓█`.
    private func heatmap(_ stats: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TermText(TermRow("activity · 12 weeks", Term.mute), height: Self.line)
            ForEach(0..<7, id: \.self) { day in
                let cells = stats.heatmap.map { week -> String in
                    guard week.indices.contains(day), let value = week[day] else { return " " }
                    return String(Term.heat(value))
                }
                TermText(TermRow(cells.joined(separator: " "), Term.reading), height: Self.heatLine)
            }
        }
    }
}
