import HUDCore
import SwiftUI

/// Shared chrome for both widget sizes: white card, 1px border, 8px radius, nothing else.
struct WidgetShell<Content: View>: View {
    let side: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: side, height: side, alignment: .topLeading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// The 320×320 widget: totals, one row per session, and the newest thought.
struct CompactWidgetView: View {
    let monitor: AgentMonitor
    static let rows = 5

    var body: some View {
        WidgetShell(side: 320) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle().fill(Theme.divider).frame(height: 1)
                totals.padding(.horizontal, 14).padding(.vertical, 10)
                Rectangle().fill(Theme.divider).frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(Array(monitor.agents.prefix(Self.rows))) { AgentLine(agent: $0) }
                    if monitor.agents.isEmpty {
                        VStack(spacing: 4) {
                            Text("No agents running").font(Theme.ui(12)).foregroundStyle(Theme.mute)
                            Text("Start a session with `claude`").font(Theme.mono(11)).foregroundStyle(Theme.waiting)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                Spacer(minLength: 0)
                Rectangle().fill(Theme.divider).frame(height: 1)
                ticker.padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // The first 44px belong to the widget's own window controls.
            RoundedRectangle(cornerRadius: 4).fill(Theme.ink).frame(width: 16, height: 16)
                .overlay(Text("A").font(Theme.ui(9, .bold)).foregroundStyle(Theme.onInk))
                .padding(.leading, 44)
            Text("Agents").font(Theme.ui(14, .semibold)).foregroundStyle(Theme.ink)
            Spacer(minLength: 4)
            RoundedRectangle(cornerRadius: 2).fill(statusColor).frame(width: 8, height: 8)
            Text(status).font(Theme.ui(11)).foregroundStyle(Theme.mute)
        }
        .padding(.trailing, 14)
        .frame(height: 38)
        .background(Theme.header)
    }

    private var statusColor: Color {
        switch monitor.mood {
        case .alert: Theme.error
        case .busy: Theme.running
        case .idle, .empty: Theme.waiting
        }
    }

    private var status: String {
        switch monitor.mood {
        case .alert: "\(monitor.loopingAgents.count) looping"
        case .busy: "\(monitor.activeCount) active"
        case .idle: "all quiet"
        case .empty: "no agents"
        }
    }

    private var totals: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(monitor.tokensPerMinute.compact)
                    .font(Theme.ui(26, .semibold))
                    .foregroundStyle(monitor.agents.isEmpty ? Theme.waiting : Theme.ink)
                    .contentTransition(.numericText())
                Text("tok/min").font(Theme.ui(11)).foregroundStyle(Theme.mute)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(monitor.stats.tokensToday.compact) today").font(Theme.ui(12)).foregroundStyle(Theme.ink)
                Text(String(format: "$%.2f est.", monitor.stats.costToday)).font(Theme.ui(12)).foregroundStyle(Theme.mute)
            }
        }
    }

    private var ticker: some View {
        let (text, color, symbol) = Self.tickerLine(monitor)
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
                .padding(.top, 2)
            Text(text).font(Theme.mono(11)).foregroundStyle(Theme.ink).lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(height: 28, alignment: .top)
    }

    static func tickerLine(_ monitor: AgentMonitor) -> (String, Color, String) {
        switch monitor.mood {
        case .alert:
            guard let agent = monitor.loopingAgents.first, let loop = agent.activeLoop else { return ("", Theme.error, "xmark") }
            let error = agent.steps.last { $0.isError }?.errorText ?? "same call keeps failing"
            return ("\(agent.repo) · loop ×\(loop.count): \(FlowLayout.shortError(error))", Theme.error, "xmark")
        case .busy:
            guard let agent = monitor.focus, let item = agent.ticker.last else { return ("", Theme.thinking, "brain") }
            return ("\(agent.repo) · \(item.text)", Theme.color(for: item.kind), Theme.symbol(for: item.kind))
        case .idle, .empty:
            let last = monitor.agents.compactMap(\.activitySince).max().map { Date().timeIntervalSince($0).elapsedText } ?? "—"
            return ("All quiet · last activity \(last) ago", Theme.mute, "ellipsis")
        }
    }
}

/// One session line in the compact widget: dot, name, context bar, heartbeat.
struct AgentLine: View {
    let agent: AgentSnapshot

    var body: some View {
        let activity: ActivityKind = agent.isLooping ? .error : agent.activity
        let color = Theme.color(for: activity)
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(agent.repo).font(Theme.ui(12, .medium)).foregroundStyle(Theme.ink)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            BarTrack(fraction: agent.contextFill,
                     color: agent.contextFill >= 0.75 ? Theme.error : Theme.borderStrong,
                     width: 28, height: 4, trackColor: Theme.divider)
            Sparkline(values: agent.heartbeat, color: color, active: activity.isActive)
                .frame(width: 56, height: 14)
        }
        .frame(height: 26)
        .opacity(activity.isActive ? 1 : 0.55)
    }
}

/// The 160×160 widget: the headline number and a line per session.
struct MiniWidgetView: View {
    let monitor: AgentMonitor
    static let rows = 3

    var body: some View {
        WidgetShell(side: 160) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(monitor.mood == .alert ? Theme.error : monitor.activeCount > 0 ? Theme.running : Theme.waiting)
                        .frame(width: 8, height: 8)
                        .padding(.leading, 38)
                    Text("\(monitor.activeCount)/\(monitor.agents.count)").font(Theme.ui(11)).foregroundStyle(Theme.mute)
                    Spacer(minLength: 0)
                }
                .frame(height: 30)
                .padding(.trailing, 10)
                .background(Theme.header)
                Rectangle().fill(Theme.divider).frame(height: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(monitor.tokensPerMinute.compact)
                        .font(Theme.ui(22, .semibold))
                        .foregroundStyle(monitor.agents.isEmpty ? Theme.waiting : Theme.ink)
                        .contentTransition(.numericText())
                    Text("tok/min · \(monitor.stats.tokensToday.compact) today")
                        .font(Theme.ui(10)).foregroundStyle(Theme.mute)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                Rectangle().fill(Theme.divider).frame(height: 1)
                VStack(spacing: 2) {
                    ForEach(Array(monitor.agents.prefix(Self.rows))) { agent in
                        let activity: ActivityKind = agent.isLooping ? .error : agent.activity
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1.5).fill(Theme.color(for: activity)).frame(width: 6, height: 6)
                            Text(agent.repo).font(Theme.ui(10)).foregroundStyle(Theme.ink)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 2)
                            Sparkline(values: agent.heartbeat, color: Theme.color(for: activity), active: activity.isActive)
                                .frame(width: 34, height: 10)
                        }
                    }
                    if monitor.agents.isEmpty {
                        Text("no agents").font(Theme.ui(10)).foregroundStyle(Theme.mute)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Hosts whichever widget size is active and wires it to the app.
struct WidgetRoot: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        ZStack(alignment: .topLeading) {
            if delegate.isMini { MiniWidgetView(monitor: delegate.monitor) } else { CompactWidgetView(monitor: delegate.monitor) }
            WidgetControls(delegate: delegate, dot: delegate.isMini ? 8 : 9)
                .padding(.leading, delegate.isMini ? 10 : 14).padding(.top, delegate.isMini ? 11 : 15)
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

/// Window controls for the borderless widget: hide · resize · open the dashboard.
struct WidgetControls: View {
    @ObservedObject var delegate: AppDelegate
    let dot: CGFloat
    @State private var hovering = false

    var body: some View {
        HStack(spacing: dot * 0.7) {
            control(Theme.error, "xmark", "Hide widget (bring it back from the Dock or menu bar icon)") { delegate.toggleWidget() }
            control(Theme.editing, delegate.isMini ? "plus" : "minus", delegate.isMini ? "Compact size" : "Mini size") { delegate.toggleMini() }
            control(Theme.running, "arrow.up.left.and.arrow.down.right", "Open dashboard") { delegate.showDashboard() }
        }
        .onHover { hovering = $0 }
    }

    private func control(_ color: Color, _ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color.opacity(hovering ? 1 : 0.6))
                .frame(width: dot, height: dot)
                .overlay {
                    if hovering {
                        Image(systemName: symbol).font(.system(size: dot * 0.6, weight: .black)).foregroundStyle(.white)
                    }
                }
                // A forgiving hit target around a 9px dot.
                .padding(2).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
