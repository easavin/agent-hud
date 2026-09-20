import Foundation
import HUDCore
import Observation

enum WidgetMood: Equatable { case empty, idle, busy, alert }

/// Polls the ingest engine and history index and publishes the results to SwiftUI.
@MainActor
@Observable
final class AgentMonitor {
    /// Live sessions. The widget, the Dock tile and every counter are about these.
    private(set) var agents: [AgentSnapshot] = []
    /// Sessions that ended in the last day, kept as browsable history in the dashboard.
    private(set) var recent: [AgentSnapshot] = []
    private(set) var stats = StatsSnapshot()
    var selectedId: String?
    /// When the ingest last produced new data, for the header's "last refreshed" line.
    private(set) var lastRefresh = Date()

    private let engine = IngestEngine()
    private let history = HistoryIndex()
    private var liveTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?

    var tokensPerMinute: Int { agents.reduce(0) { $0 + $1.tokensPerMinute } }
    var activeCount: Int { agents.filter(\.activity.isActive).count }
    var loopingAgents: [AgentSnapshot] { agents.filter(\.isLooping) }
    var selected: AgentSnapshot? { (agents + recent).first { $0.id == selectedId } ?? focus ?? agents.first ?? recent.first }

    /// The agent worth watching: a looping one first, otherwise whoever burns the most tokens.
    var focus: AgentSnapshot? {
        loopingAgents.first ?? agents.filter(\.activity.isActive).max { $0.tokensPerMinute < $1.tokensPerMinute }
    }

    /// "a few seconds ago" / "3 min ago" — deliberately vague, like the prototype's copy.
    var lastRefreshedText: String {
        let seconds = Date().timeIntervalSince(lastRefresh)
        if seconds < 45 { return "Last refreshed a few seconds ago" }
        return "Last refreshed \(Int(seconds / 60)) min ago"
    }

    var mood: WidgetMood {
        if agents.isEmpty { return .empty }
        if !loopingAgents.isEmpty { return .alert }
        return activeCount > 0 ? .busy : .idle
    }

    /// Non-nil when showing the prototype's sample fleet instead of real sessions (`--demo busy|idle|alert`).
    var demo: DemoData.Scenario?

    func start() {
        if let demo {
            agents = DemoData.agents(demo)
            recent = DemoData.recent()
            stats = DemoData.stats()
            return
        }
        guard liveTask == nil else { return }
        liveTask = Task { [weak self, engine] in
            while !Task.isCancelled {
                let snapshots = await engine.poll()
                let live = snapshots.filter { !$0.isEnded }, ended = snapshots.filter(\.isEnded)
                if self?.agents != live { self?.agents = live; self?.lastRefresh = Date() }
                if self?.recent != ended { self?.recent = ended }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        statsTask = Task { [weak self, history] in
            while !Task.isCancelled {
                let snapshot = await history.refresh()
                if self?.stats != snapshot { self?.stats = snapshot }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// The header's Refresh button: re-index history now instead of waiting for the next pass.
    func refreshNow() {
        lastRefresh = Date()
        guard demo == nil else { return }
        Task { [history] in
            let snapshot = await history.refresh()
            if self.stats != snapshot { self.stats = snapshot }
        }
    }

    func stop() {
        liveTask?.cancel()
        statsTask?.cancel()
        liveTask = nil
        statsTask = nil
    }
}
