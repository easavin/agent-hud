import HUDCore
import SwiftUI

/// Left column: one card per session. Selected gets an ink border, an inner ink ring and a warm fill.
struct AgentCard: View {
    let agent: AgentSnapshot
    let selected: Bool
    static let height: CGFloat = 112

    var body: some View {
        let activity: ActivityKind = agent.isEnded ? .idle : (agent.isLooping ? .error : agent.activity)
        let color = Theme.color(for: activity)
        Card(padding: 0, fill: selected ? Theme.cardSelected : Theme.card,
             border: selected ? Theme.ink : Theme.border, ring: selected) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(agent.repo).font(Theme.ui(14, .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    ModelBadge(model: agent.model)
                }
                HStack(spacing: 6) {
                    Label(agent.gitBranch ?? "—", systemImage: "arrow.triangle.branch")
                        .font(Theme.ui(12)).foregroundStyle(Theme.mute)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    if !agent.plan.isEmpty {
                        ProgressRing(done: agent.planDone, total: agent.plan.count,
                                     color: Theme.modelColor(agent.model), side: 18)
                        if let eta = agent.etaMinutes {
                            Text("~\(eta)m").font(Theme.ui(11)).foregroundStyle(Theme.mute)
                        }
                    }
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                    Text(agent.isEnded ? "ended" : (agent.isLooping ? "loop ×\(agent.activeLoop?.count ?? 0)" : activity.word))
                        .font(Theme.ui(12, .medium)).foregroundStyle(color)
                    Spacer(minLength: 4)
                    Text(elapsed).font(Theme.ui(12)).foregroundStyle(Theme.mute)
                }
                BarTrack(fraction: agent.contextFill, color: contextColor)
                HStack(spacing: 6) {
                    // Sessions reach tens of millions of tokens, so this line has to survive "33.40M".
                    Text("context \(Int((agent.contextFill * 100).rounded()))% · \(agent.usage.total.compact) tokens")
                        .font(Theme.ui(11)).foregroundStyle(Theme.mute)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    Sparkline(values: agent.heartbeat, color: color, active: activity.isActive)
                        .frame(width: 64, height: 16)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .frame(height: Self.height)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var elapsed: String {
        agent.startedAt.map { (agent.endedAt ?? Date()).timeIntervalSince($0).elapsedText } ?? "—"
    }

    /// Blue under 60%, amber to 75%, red past it.
    private var contextColor: Color {
        agent.contextFill >= 0.75 ? Theme.error : agent.contextFill >= 0.6 ? Theme.editing : Theme.reading
    }
}
