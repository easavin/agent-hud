import HUDCore
import SwiftUI

/// Shared chrome for both widget sizes: flat near-black, 1px frame, 8px radius, nothing else.
struct WidgetShell<Content: View>: View {
    let side: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            .frame(width: side, height: side, alignment: .topLeading)
            .background(Term.bg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .circular))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .circular).strokeBorder(Term.borderOuter, lineWidth: 1))
    }
}

/// The 320×320 widget: header, totals, one line per session, a 60-minute lane strip and the newest thought.
struct CompactWidgetView: View {
    let monitor: AgentMonitor
    static let rows = 5
    /// 320 − 20 of padding.
    static let columns = 41
    /// The header line starts after the traffic lights, so it has fewer cells to play with.
    static let headerColumns = 34
    static let laneCells = 28

    var body: some View {
        WidgetShell(side: 320) {
            VStack(alignment: .leading, spacing: 0) {
                TermText(header).padding(.leading, 44)
                rule
                TermText(totals)
                TermText(second)
                rule
                ForEach(Array(monitor.agents.prefix(Self.rows))) { TermText(line(for: $0)) }
                if monitor.agents.isEmpty {
                    TermText(TermRow("no agents running", Term.mute))
                    TermText(TermRow("start a session with `claude`", Term.waiting))
                }
                rule
                TimelineView(.periodic(from: .now, by: 2)) { timeline in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(monitor.agents.prefix(Self.rows))) { TermText(lane(for: $0, now: timeline.date)) }
                    }
                }
                Spacer(minLength: 0)
                rule
                ForEach(Array(Self.ticker(monitor).enumerated()), id: \.offset) { _, row in TermText(row, ellipsize: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rule: some View { TermRule().padding(.vertical, 6) }

    private var header: TermRow {
        var row = TermRow("agent-hud", Term.ink, weight: .bold)
        let live = monitor.activeCount > 0
        row.space(to: Self.headerColumns - 12)
        row.add("● ", monitor.mood == .alert ? Term.error : live ? Term.running : Term.waiting)
        row.add(Term.pad(status, 10), Term.mute)
        return row
    }

    private var status: String {
        switch monitor.mood {
        case .alert: "\(monitor.loopingAgents.count) looping"
        case .busy: "\(monitor.activeCount) active"
        case .idle: "all quiet"
        case .empty: "no agents"
        }
    }

    private var totals: TermRow {
        var row = TermRow(Term.padStart(monitor.tokensPerMinute.compact, 7), monitor.agents.isEmpty ? Term.waiting : Term.ink)
        row.add(" tok/min", Term.mute)
        row.space(to: 22)
        row.add(Term.padStart(monitor.stats.tokensToday.compact, 7), Term.ink)
        row.add(" today", Term.mute)
        return row
    }

    private var second: TermRow {
        var row = TermRow(Term.padStart(String(format: "$%.2f", monitor.stats.costToday), 7), Term.ink)
        row.add(" est.", Term.mute)
        row.space(to: 22)
        row.add(Term.padStart("\(monitor.agents.count)", 7), Term.ink)
        row.add(" sessions", Term.mute)
        return row
    }

    private func line(for agent: AgentSnapshot) -> TermRow {
        let activity = agent.isLooping ? ActivityKind.error : agent.activity
        let color = Term.color(for: activity)
        var row = TermRow(Term.pad(agent.repo, 11) + " ", Term.ink)
        row.add(Term.glyph(for: activity) + " " + Term.pad(activity.word, 8), color)
        row.add(Term.bar(agent.contextFill, 6, fill: "█"),
                agent.contextFill >= 0.75 ? Term.error : Term.border)
        row.add(" ")
        row.add(activity.isActive ? Term.spark(agent.heartbeat, 11) : String(repeating: "▁", count: 11),
                activity.isActive ? color : Term.waiting)
        return row
    }

    /// The same 60-minute lane as the dashboard, at 28 cells instead of 90.
    private func lane(for agent: AgentSnapshot, now: Date) -> TermRow {
        let cells = LanesPane.cells(for: agent, now: now)
        var row = TermRow(Term.pad(agent.repo, 11) + " ", Term.mute)
        let per = cells.count / Self.laneCells
        for index in 0..<Self.laneCells {
            // One widget cell covers several dashboard cells; whatever dominates it wins.
            let slice = cells[(index * per)..<((index + 1) * per)]
            let cell = slice.first { $0.kind != .idle } ?? slice[slice.startIndex]
            row.add(String(cell.glyph), cell.color)
        }
        row.add("┃", Term.reading)
        return row
    }

    /// Two ellipsized lines: who, and what they are saying.
    static func ticker(_ monitor: AgentMonitor) -> [TermRow] {
        switch monitor.mood {
        case .alert:
            guard let agent = monitor.loopingAgents.first, let loop = agent.activeLoop else { return [] }
            let error = agent.steps.last { $0.isError }?.errorText ?? "same call keeps failing"
            var head = TermRow("✕ ", Term.error)
            head.add(Term.pad(agent.repo, 11) + " ", Term.ink)
            head.add("loop ×\(loop.count) · \(loop.label)", Term.error)
            return [head, TermRow("  " + error, Term.ink2)]
        case .busy:
            guard let agent = monitor.focus, let item = agent.ticker.last else { return [] }
            var head = TermRow(Term.glyph(for: item.kind) + " ", Term.color(for: item.kind))
            head.add(Term.pad(agent.repo, 11) + " ", Term.modelColor(agent.model))
            head.add(item.kind.word, Term.color(for: item.kind))
            return [head, TermRow("  " + item.text, Term.ink2)]
        case .idle, .empty:
            let last = monitor.agents.compactMap(\.activitySince).max().map { Date().timeIntervalSince($0).elapsedText } ?? "—"
            return [TermRow("· all quiet", Term.mute), TermRow("  last activity \(last) ago", Term.waiting)]
        }
    }
}

/// The 160×160 widget: totals and a line per session, nothing else.
struct MiniWidgetView: View {
    let monitor: AgentMonitor
    static let columns = 19
    static let rows = 4

    var body: some View {
        WidgetShell(side: 160) {
            VStack(alignment: .leading, spacing: 0) {
                TermText(header).padding(.leading, 36)
                TermText(TermRow(Term.padStart(monitor.tokensPerMinute.compact, 8), monitor.agents.isEmpty ? Term.waiting : Term.ink)
                    + TermRow(" tok/min", Term.mute))
                TermText(TermRow(Term.padStart(monitor.stats.tokensToday.compact, 8), Term.ink) + TermRow(" today", Term.mute))
                TermText(TermRow(Term.padStart(String(format: "$%.2f", monitor.stats.costToday), 8), Term.ink)
                    + TermRow(" est.", Term.mute))
                TermRule().padding(.vertical, 5)
                ForEach(Array(monitor.agents.prefix(Self.rows))) { agent in
                    let activity = agent.isLooping ? ActivityKind.error : agent.activity
                    let color = Term.color(for: activity)
                    TermText(TermRow(Term.pad(agent.repo, 8) + " ", Term.ink)
                        + TermRow(Term.glyph(for: activity), color)
                        + TermRow(activity.isActive ? Term.spark(agent.heartbeat, 9) : String(repeating: "▁", count: 9),
                                  activity.isActive ? color : Term.waiting))
                }
                if monitor.agents.isEmpty { TermText(TermRow("no agents", Term.mute)) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: TermRow {
        var row = TermRow("●", monitor.mood == .alert ? Term.error : monitor.activeCount > 0 ? Term.running : Term.waiting)
        row.add(" \(monitor.activeCount)/\(monitor.agents.count)", Term.mute)
        return row
    }
}

/// Hosts whichever widget size is active and wires it to the app.
struct WidgetRoot: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        ZStack(alignment: .topLeading) {
            if delegate.isMini { MiniWidgetView(monitor: delegate.monitor) } else { CompactWidgetView(monitor: delegate.monitor) }
            WidgetControls(delegate: delegate, dot: delegate.isMini ? 8 : 9)
                .padding(.leading, delegate.isMini ? 9 : 11).padding(.top, delegate.isMini ? 9 : 11)
        }
        .onTapGesture(count: 2) { delegate.showDashboard() }
        .contextMenu {
            Button("Open Dashboard") { delegate.showDashboard() }
            Button(delegate.isMini ? "Compact Widget (320)" : "Mini Widget (160)") { delegate.toggleMini() }
            Button("Hide Widget") { delegate.toggleWidget() }
            Divider()
            Button("Quit Agent HUD") { NSApp.terminate(nil) }
        }
    }
}

/// Window controls for the borderless widget: square, in the palette — hide · resize · dashboard.
struct WidgetControls: View {
    @ObservedObject var delegate: AppDelegate
    let dot: CGFloat
    @State private var hovering = false

    var body: some View {
        HStack(spacing: dot * 0.6) {
            control(Term.error, "×", "Hide widget (bring it back from the Dock or menu bar icon)") { delegate.toggleWidget() }
            control(Term.editing, delegate.isMini ? "+" : "−", delegate.isMini ? "Compact size" : "Mini size") { delegate.toggleMini() }
            control(Term.running, "▣", "Open dashboard") { delegate.showDashboard() }
        }
        .onHover { hovering = $0 }
    }

    private func control(_ color: Color, _ glyph: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Rectangle().fill(color.opacity(hovering ? 1 : 0.55))
                .frame(width: dot, height: dot)
                .overlay {
                    if hovering {
                        Text(glyph).font(.custom(Term.fontName, fixedSize: dot * 0.8)).foregroundStyle(Term.bg)
                    }
                }
                // A forgiving hit target around a 9px square.
                .padding(2).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
