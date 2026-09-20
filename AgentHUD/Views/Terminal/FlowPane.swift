import HUDCore
import SwiftUI

/// The hero pane: flow tree, brain, loops or files for the selected agent.
struct HeroPane: View {
    let agent: AgentSnapshot?
    @Binding var tab: HeroTab

    var body: some View {
        TermPane(title: title, hint: tabs) {
            if let agent {
                switch tab {
                case .flow: FlowPane(agent: agent)
                case .brain: BrainPane(agent: agent)
                case .loops: LoopsPane(agent: agent)
                case .files: FilesPane(agent: agent)
                }
            } else {
                TermText(TermRow("no session selected — start one with `claude`", Term.mute))
            }
        }
    }

    private var title: String {
        guard let agent else { return tab.rawValue }
        return "\(tab.rawValue) · \(agent.repo) · turn \(agent.turnIndex)" + (agent.isEnded ? " · ended" : "")
    }

    private var tabs: TermRow {
        var row = TermRow()
        for option in HeroTab.allCases {
            if !row.isEmpty { row.add("  ", Term.mute) }
            row.add(option.hint, option == tab ? Term.ink : Term.mute)
        }
        return row
    }
}

/// ─ flow ─ : the current turn as an ASCII tree, with the selected node spelled out below a rule.
struct FlowPane: View {
    let agent: AgentSnapshot
    @State private var selectedStepId: String?

    /// Margin + rule + padding + three 16px lines.
    private static let detailHeight: CGFloat = 12 + 1 + 6 + 3 * Term.line

    var body: some View {
        GeometryReader { proxy in
            let maxLines = max(3, Int((proxy.size.height - Self.detailHeight) / Term.line))
            let tree = FlowTree(agent: agent, maxLines: maxLines)
            let step = selectedStep
            VStack(alignment: .leading, spacing: 0) {
                if tree.lines.isEmpty {
                    TermText(TermRow("waiting for the first prompt", Term.mute))
                }
                ForEach(tree.lines) { line in
                    TermText(line.row)
                        .contentShape(Rectangle())
                        .onTapGesture { if let id = line.stepId { selectedStepId = id } }
                }
                Spacer(minLength: 12)
                TermRule()
                VStack(alignment: .leading, spacing: 0) {
                    TermText(headline(step))
                    TermText(TermRow(String(repeating: " ", count: 11) + FlowTree.clip(detail(step), 104), Term.mute))
                    ParticleLine(active: agent.steps.contains(where: \.isRunning) && !agent.isEnded, label: particleLabel)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: agent.id) { selectedStepId = nil }
    }

    /// Defaults to whatever is worth looking at: the looping failure, else the newest step.
    private var selectedStep: TurnStep? {
        if let selectedStepId, let step = agent.steps.first(where: { $0.id == selectedStepId }) { return step }
        return agent.steps.last { $0.isError && $0.iteration >= 2 } ?? agent.steps.last
    }

    private func headline(_ step: TurnStep?) -> TermRow {
        var row = TermRow("selected ▸ ", Term.mute)
        guard let step else {
            row.add("nothing yet", Term.mute)
            return row
        }
        let activity = step.isError ? ActivityKind.error : step.activity
        row.add(step.label + (step.isError ? " · failed" : step.isRunning ? " · running" : ""), Term.color(for: activity))
        if !step.detail.isEmpty { row.add("  " + FlowTree.clip(step.detail, 48), Term.ink) }

        var facts: [String] = []
        if let duration = step.duration { facts.append(duration.secondsText) }
        if step.tokens > 0 { facts.append("\(step.tokens.compact) tok") }
        if step.isError { facts.append(FlowTree.shortError(step.errorText)) }
        if step.iteration >= 2, let loop = agent.activeLoop { facts.append("iter \(step.iteration)/\(loop.count)") }
        if !facts.isEmpty { row.add("  " + facts.joined(separator: " · "), Term.mute) }
        return row
    }

    private func detail(_ step: TurnStep?) -> String {
        guard let step else { return "" }
        if let error = step.errorText, !error.isEmpty { return FlowTree.clean(error) }
        if step.kind == .thinking || step.kind == .prompt || step.kind == .result { return step.detail }
        return step.target.isEmpty ? "" : step.target
    }

    private var particleLabel: String {
        guard let running = agent.steps.last(where: \.isRunning) else { return agent.activity.word }
        return "\(running.label) running"
    }
}

/// Three `●` walking the active edge, one cell every 130 ms. Still when nothing is running.
struct ParticleLine: View {
    let active: Bool
    let label: String
    @Environment(\.staticRendering) private var staticRendering
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let track = 12

    var body: some View {
        if active && !staticRendering && !reduceMotion {
            TimelineView(.periodic(from: .now, by: 0.13)) { timeline in
                TermText(row(step: Int(timeline.date.timeIntervalSinceReferenceDate / 0.13)))
            }
        } else {
            TermText(row(step: 4))
        }
    }

    private func row(step: Int) -> TermRow {
        var cells = [Character](repeating: " ", count: Self.track)
        if active {
            for dot in 0..<3 { cells[((step - dot * 2) % Self.track + Self.track) % Self.track] = "●" }
        }
        var row = TermRow(String(cells), Term.running)
        row.add(" " + label, Term.mute)
        return row
    }
}
