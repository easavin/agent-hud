import HUDCore
import SwiftUI

/// ─ thoughts ─ : the five newest lines across every session, newest at the bottom.
struct ThoughtsPane: View {
    let agents: [AgentSnapshot]
    @Binding var blur: Bool

    static let line: CGFloat = 15
    static let rows = 5
    /// time(5) + agent(11) + glyph(1) and their separators.
    static let prefixColumns = 20

    private struct Line: Identifiable {
        let id: String
        let agent: AgentSnapshot
        let item: TickerItem
    }

    private var lines: [Line] {
        agents.flatMap { agent in agent.ticker.suffix(Self.rows).map { Line(id: agent.id + $0.id, agent: agent, item: $0) } }
            .sorted { $0.item.date > $1.item.date }
            .prefix(Self.rows)
            .reversed()
    }

    var body: some View {
        TermPane(title: "thoughts",
                 hint: TermRow("[p] blur: \(blur ? "on" : "off")", Term.mute),
                 insets: EdgeInsets(top: 18, leading: 10, bottom: 6, trailing: 10)) {
            VStack(alignment: .leading, spacing: 0) {
                let lines = lines
                if lines.isEmpty {
                    TermText(TermRow("nothing said yet", Term.mute), height: Self.line)
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    row(line, newest: index == lines.count - 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { blur.toggle() }
        }
    }

    private func row(_ line: Line, newest: Bool) -> some View {
        var prefix = TermRow(line.item.date.shortClockText + " ", Term.mute)
        prefix.add(Term.pad(line.agent.repo, 11) + " ", Term.modelColor(line.agent.model))
        prefix.add(Term.glyph(for: line.item.kind) + " ", Term.color(for: line.item.kind))
        return HStack(spacing: 0) {
            TermText(prefix, height: Self.line)
            TermText(TermRow(line.item.text, Term.ink2), height: Self.line, ellipsize: true)
                .blur(radius: blur ? 4 : 0)
                .opacity(blur ? 0.7 : 1)
                .layoutPriority(-1)
            if newest { BlinkingCursor().frame(height: Self.line) }
            Spacer(minLength: 0)
        }
        .frame(height: Self.line)
    }
}

/// `▌` blinking once a second, in steps.
struct BlinkingCursor: View {
    @Environment(\.staticRendering) private var staticRendering
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if staticRendering || reduceMotion {
            TermText(TermRow("▌", Term.reading))
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                TermText(TermRow("▌", Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? Term.reading : .clear))
            }
        }
    }
}
