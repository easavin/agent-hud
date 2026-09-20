import HUDCore
import SwiftUI

/// Hero card, "Brain" tab: what the agent is holding in context, laid out in five layers.
struct BrainView: View {
    let agent: AgentSnapshot
    /// Column centres as a fraction of the pane's width, so the graph stretches with it.
    static let layerFraction: [CGFloat] = [0.08, 0.30, 0.51, 0.73, 0.92]
    static let layerNames = ["Prompt", "Files", "Tools", "Reasoning", "Output"]

    private struct Placed {
        let item: BrainItem
        let center: CGPoint
        let radius: CGFloat
        let active: Bool
        let color: Color
    }

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: max(360, proxy.size.width - 28), height: max(140, proxy.size.height - 58))
            VStack(spacing: 10) {
                Canvas { context, _ in draw(place(agent.brain, in: size), in: &context, size: size) }
                    .frame(width: size.width, height: size.height)
                ContextWindowBar(agent: agent).frame(width: size.width)
            }
            .padding(.horizontal, 14)
        }
    }

    private func place(_ items: [BrainItem], in size: CGSize) -> [[Placed]] {
        BrainItem.Layer.allCases.map { layer in
            let members = items.filter { $0.layer == layer }.sorted { $0.tokens > $1.tokens }.prefix(5)
            // Rows have to clear a node's radius plus its label, so five is the most a layer can show.
            let spacing = min(48, (size.height - 60) / CGFloat(max(1, members.count)))
            return members.enumerated().map { index, item in
                let y = size.height * 0.52 + (CGFloat(index) - CGFloat(members.count - 1) / 2) * spacing
                // r = 4 + √(tokens/60), clamped 5–14
                let radius = min(14, max(5, 4 + (Double(item.tokens) / 60).squareRoot()))
                let active = item.lastTurn >= agent.turnIndex
                let color: Color = layer == .prompt ? Theme.ink : Theme.color(for: item.activity)
                return Placed(item: item, center: CGPoint(x: Self.layerFraction[layer.rawValue] * size.width, y: y),
                              radius: radius, active: active, color: color)
            }
        }
    }

    private func draw(_ layers: [[Placed]], in context: inout GraphicsContext, size: CGSize) {
        for (index, name) in Self.layerNames.enumerated() {
            context.label(name.uppercased(), at: CGPoint(x: Self.layerFraction[index] * size.width, y: 12),
                          size: 10, weight: .semibold, color: Theme.mute)
        }
        // Edges run layer to layer. Connecting every pair turns into a hairball, so each node reaches
        // the two biggest nodes of the next layer, plus any edge that is live this turn.
        for (left, right) in zip(layers, layers.dropFirst()) {
            let principal = Set(right.prefix(2).map(\.item.id))
            for a in left {
                for b in right {
                    let hot = a.active && b.active
                    guard hot || principal.contains(b.item.id) else { continue }
                    context.stroke(Geometry.link(CGPoint(x: a.center.x + a.radius, y: a.center.y),
                                                 CGPoint(x: b.center.x - b.radius, y: b.center.y)),
                                   with: .color(hot ? b.color.opacity(0.7) : Theme.divider),
                                   lineWidth: hot ? 1.5 : 1)
                }
            }
        }
        for layer in layers {
            for node in layer {
                let rect = CGRect(x: node.center.x - node.radius, y: node.center.y - node.radius,
                                  width: node.radius * 2, height: node.radius * 2)
                let circle = Path(ellipseIn: rect)
                context.fill(circle, with: .color(node.color.opacity(node.active ? 0.35 : 0.12)))
                context.stroke(circle, with: .color(node.color.opacity(node.active ? 1 : 0.4)), lineWidth: node.active ? 2 : 1)
                context.label(FlowLayout.snippet(node.item.name, 18), at: CGPoint(x: node.center.x, y: node.center.y + node.radius + 10),
                              size: 10, weight: node.active ? .semibold : .regular,
                              color: node.active ? Theme.ink : Theme.mute)
            }
        }
        if layers.allSatisfy(\.isEmpty) {
            context.label("Nothing in context yet", at: CGPoint(x: size.width / 2, y: size.height / 2), size: 13, color: Theme.mute)
        }
    }
}

/// 688×6 bar splitting the context window into system, files, tool results and thinking.
struct ContextWindowBar: View {
    let agent: AgentSnapshot

    var body: some View {
        let split = agent.contextSplit
        let used = max(1, agent.contextTokens)
        let system = max(0, used - split.files - split.tools - split.thinking)
        let segments: [(Int, Color, String)] = [
            (system, Theme.waiting, "system"), (split.files, Theme.reading, "files"),
            (split.tools, Theme.running, "tool results"), (split.thinking, Theme.thinking, "thinking"),
        ]
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                let scale = proxy.size.width * agent.contextFill / CGFloat(used)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.Radius.bar).fill(Theme.divider)
                    HStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            Rectangle().fill(segment.1).frame(width: max(0, CGFloat(segment.0) * scale))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.bar))
                }
            }
            .frame(height: 6)
            HStack(spacing: 10) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(segment.1).frame(width: 6, height: 6)
                        Text(segment.2).font(Theme.ui(10)).foregroundStyle(Theme.mute)
                    }
                }
                Spacer(minLength: 0)
                Text("\(agent.contextTokens.compact) of \(agent.contextMax.compact) · \(Int((agent.contextFill * 100).rounded()))%")
                    .font(Theme.ui(11)).foregroundStyle(Theme.mute)
            }
        }
    }
}

/// Hero card, "Loops" tab: one orbit per failed iteration around the retried tool.
struct LoopsView: View {
    let agent: AgentSnapshot
    static let firstOrbit: CGFloat = 34
    static let orbitStep: CGFloat = 22

    static func ringColor(_ index: Int, of count: Int) -> Color {
        guard count > 1 else { return Theme.editing }
        let progress = Double(index) / Double(count - 1)
        return progress < 0.34 ? Theme.editing : progress < 0.67 ? Theme.loopMid : Theme.error
    }

    var body: some View {
        let loop = agent.activeLoop ?? agent.loops.last
        GeometryReader { proxy in
            HStack(spacing: 16) {
                Canvas { context, size in draw(loop, in: &context, size: size) }
                    .frame(width: max(200, min(340, proxy.size.width * 0.44)))
                iterations(loop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func draw(_ loop: LoopInfo?, in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2 - 10)
        guard let loop, loop.count > 0 else {
            context.label("No loops this session", at: center, size: 13, color: Theme.mute)
            return
        }
        // Orbits have to stay inside whatever the pane is now.
        let step = min(Self.orbitStep, (min(size.width, size.height) / 2 - Self.firstOrbit - 12) / CGFloat(max(1, loop.count - 1)))
        for index in 0..<loop.count {
            let radius = Self.firstOrbit + step * CGFloat(index)
            let color = Self.ringColor(index, of: loop.count)
            let current = index == loop.count - 1 && !loop.resolved
            context.stroke(Geometry.arc(center, radius, 0, 360), with: .color(color),
                           style: current ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 1.25, dash: [2, 3]))
            // Each iteration's failure sits on its ring.
            let marker = Geometry.point(center, radius, 40 + Double(index) * 24)
            let dot = CGRect(x: marker.x - 3, y: marker.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: dot), with: .color(.white))
            context.stroke(Path(ellipseIn: dot), with: .color(Theme.error), lineWidth: 1.5)
        }
        // A resolved loop breaks out of the last orbit on a green tangent.
        if loop.resolved {
            let radius = Self.firstOrbit + step * CGFloat(loop.count - 1)
            var escape = Path()
            escape.move(to: Geometry.point(center, radius, 300))
            escape.addLine(to: Geometry.point(center, radius + 34, 310))
            context.stroke(escape, with: .color(Theme.running), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        let hub = Path(ellipseIn: CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32))
        context.fill(hub, with: .color(Theme.editing.opacity(0.12)))
        context.stroke(hub, with: .color(Theme.editing), lineWidth: 2)
        context.symbol("arrow.triangle.2.circlepath", at: center, size: 13, color: Theme.editing)
        context.label(loop.tool, at: CGPoint(x: center.x, y: center.y + 28), size: 11, weight: .semibold, color: Theme.ink)
    }

    @ViewBuilder private func iterations(_ loop: LoopInfo?) -> some View {
        if let loop {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(loop.label).font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink)
                    Text("×\(loop.count)")
                        .font(Theme.ui(11, .semibold)).foregroundStyle(Theme.onInk)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.chip).fill(loop.resolved ? Theme.running : Theme.error))
                    Text(loop.resolved ? "resolved" : "same error ×\(loop.sameErrorCount)")
                        .font(Theme.ui(11)).foregroundStyle(loop.resolved ? Theme.running : Theme.error)
                }
                ForEach(Array(loop.iterations.enumerated()), id: \.offset) { index, iteration in
                    let last = index == loop.count - 1
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(Theme.ui(10, .semibold)).foregroundStyle(Theme.mute)
                            .frame(width: 14, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(iteration.duration.secondsText) · \(iteration.tokens.compact) tokens")
                                .font(Theme.ui(11)).foregroundStyle(Theme.mute)
                            Text(last && loop.resolved ? "passed" : FlowLayout.shortError(iteration.errorText))
                                .font(Theme.ui(11)).foregroundStyle(last && loop.resolved ? Theme.running : Theme.error)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 14).padding(.top, 20)
        }
    }
}
