import HUDCore
import SwiftUI

/// Hero card, "Flow" tab: the current turn as a left→right node graph on white.
struct FlowGraphView: View {
    let agent: AgentSnapshot
    @State private var selectedId: String?
    @Environment(\.staticRendering) private var staticRendering
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            graph(in: CGSize(width: max(360, proxy.size.width), height: max(180, proxy.size.height)))
        }
    }

    private func graph(in size: CGSize) -> some View {
        let layout = FlowLayout(steps: agent.steps, subagents: agent.subagents, size: size)
        let selected = layout.nodes.first { $0.id == selectedId }
            ?? layout.nodes.last { $0.style == .error && $0.loopCount >= 2 }
        return ZStack(alignment: .topLeading) {
            // Static layer: edges, nodes, glyphs, labels, chips. Redrawn only when the turn changes.
            Canvas { context, _ in draw(layout, in: &context, selectedId: selected?.id) }
            // Motion layer: particles down the live edge and the looping error ring.
            if !staticRendering && !reduceMotion, needsMotion(layout) {
                TimelineView(.periodic(from: .now, by: 1.0 / 15)) { timeline in
                    Canvas { context, _ in drawMotion(layout, in: &context, at: timeline.date) }
                }
            } else {
                Canvas { context, _ in drawMotion(layout, in: &context, at: .distantPast) }
            }
            if layout.nodes.isEmpty {
                Text("Waiting for the first prompt")
                    .font(Theme.ui(13)).foregroundStyle(Theme.mute)
                    .frame(width: size.width, height: size.height)
            }
            if let selected { NodePopover(node: selected).position(popoverPosition(for: selected, in: size)) }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in
            let hit = layout.nodes.first { hypot($0.center.x - tap.location.x, $0.center.y - tap.location.y) <= $0.radius + 8 }
            selectedId = hit?.id == selectedId ? nil : hit?.id
        })
        .onChange(of: agent.id) { selectedId = nil }
    }

    private func needsMotion(_ layout: FlowLayout) -> Bool {
        layout.nodes.contains { $0.isRunning } || !layout.loopEdges.isEmpty
    }

    /// The popover sits under the node, or above it when the node hangs low on the canvas.
    private func popoverPosition(for node: FlowLayout.Node, in size: CGSize) -> CGPoint {
        let x = min(max(node.center.x, 120), max(120, size.width - 120))
        let below = node.center.y < size.height * 0.56
        return CGPoint(x: x, y: below ? node.center.y + node.radius + 78 : node.center.y - node.radius - 62)
    }

    // MARK: Static layer

    private func edgeEnds(_ edge: FlowLayout.Edge, _ nodes: [FlowLayout.Node]) -> (CGPoint, CGPoint) {
        let from = nodes[edge.from], to = nodes[edge.to]
        return (CGPoint(x: from.center.x + from.radius, y: from.center.y),
                CGPoint(x: to.center.x - to.radius, y: to.center.y))
    }

    private func draw(_ layout: FlowLayout, in context: inout GraphicsContext, selectedId: String?) {
        let nodes = layout.nodes
        for edge in layout.edges {
            let (start, end) = edgeEnds(edge, nodes)
            let color = Theme.color(for: nodes[edge.to].activity)
            context.stroke(Geometry.link(start, end), with: .color(color.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.5, dash: edge.dashed ? [3, 3] : []))
        }
        for loop in layout.loopEdges { drawLoop(loop, nodes: nodes, in: &context) }
        if layout.hiddenColumns > 0, nodes.count > 1 {
            context.label("⋯ +\(layout.hiddenColumns) steps", at: CGPoint(x: FlowLayout.firstX + FlowLayout.pitch / 2, y: 20),
                          size: 10, color: Theme.mute)
        }
        for node in nodes {
            drawChips(for: node, in: &context)
            drawNode(node, in: &context, selected: node.id == selectedId)
        }
    }

    private func drawNode(_ node: FlowLayout.Node, in context: inout GraphicsContext, selected: Bool) {
        let color = Theme.color(for: node.activity)
        let rect = CGRect(x: node.center.x - node.radius, y: node.center.y - node.radius,
                          width: node.radius * 2, height: node.radius * 2)
        let circle = Path(ellipseIn: rect)
        let onInk = node.style == .prompt || node.style == .result

        switch node.style {
        case .prompt, .result:
            context.fill(circle, with: .color(Theme.ink))
        case .error:
            context.fill(circle, with: .color(color.opacity(0.25)))
        default:
            context.fill(circle, with: .color(color.opacity(0.12)))
        }
        context.stroke(circle, with: .color(onInk ? Theme.ink : color),
                       style: StrokeStyle(lineWidth: 2, dash: node.style == .subagent ? [3, 3] : []))
        if selected {
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(Theme.ink), lineWidth: 1)
        }
        // A failed call is cracked across with two white strokes.
        if node.style == .error {
            var cracks = Path()
            cracks.move(to: Geometry.point(node.center, node.radius, 200))
            cracks.addLine(to: CGPoint(x: node.center.x + 1, y: node.center.y - 1))
            cracks.addLine(to: Geometry.point(node.center, node.radius, 55))
            cracks.move(to: CGPoint(x: node.center.x, y: node.center.y))
            cracks.addLine(to: Geometry.point(node.center, node.radius, 145))
            context.stroke(cracks, with: .color(.white), lineWidth: 1.5)
        } else {
            context.symbol(symbol(for: node), at: node.center, size: min(12, max(9, node.radius * 0.7)),
                           color: onInk ? Theme.onInk : color)
        }

        let labelY = node.center.y + node.radius + 10
        context.label(node.label, at: CGPoint(x: node.center.x, y: labelY), size: 11, weight: .semibold, color: Theme.ink)
        if !node.sub.isEmpty {
            context.label(node.sub, at: CGPoint(x: node.center.x, y: labelY + 13), size: 10, color: Theme.mute)
        }
    }

    private func symbol(for node: FlowLayout.Node) -> String {
        switch node.style {
        case .prompt: "text.alignleft"
        case .result: "checkmark"
        default: Theme.symbol(for: node.activity)
        }
    }

    /// The loop edge arcs over the row with a solid red pill carrying the iteration count. The handoff
    /// draws it below, but below the nodes is where the labels and the popover live.
    private func loopGeometry(_ loop: FlowLayout.LoopEdge, nodes: [FlowLayout.Node]) -> (path: Path, apex: CGPoint) {
        let from = nodes[loop.from].center, to = nodes[loop.to].center
        let rise = max(18, min(from.y, to.y) - 52)
        let apex = CGPoint(x: (from.x + to.x) / 2, y: rise + 6)
        var path = Path()
        path.move(to: CGPoint(x: from.x, y: from.y - nodes[loop.from].radius))
        path.addCurve(to: CGPoint(x: to.x, y: to.y - nodes[loop.to].radius),
                      control1: CGPoint(x: from.x, y: rise), control2: CGPoint(x: to.x, y: rise))
        return (path, apex)
    }

    private func drawLoop(_ loop: FlowLayout.LoopEdge, nodes: [FlowLayout.Node], in context: inout GraphicsContext) {
        let geometry = loopGeometry(loop, nodes: nodes)
        context.stroke(geometry.path, with: .color(Theme.error.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        let pill = CGRect(x: geometry.apex.x - 14, y: geometry.apex.y - 8, width: 28, height: 16)
        context.fill(Path(roundedRect: pill, cornerRadius: Theme.Radius.chip), with: .color(Theme.error))
        context.label("×\(loop.count)", at: geometry.apex, size: 11, weight: .semibold, color: Theme.onInk)
    }

    /// `retry.py +42 −17` chips hanging off an Edit node on a 1px amber connector.
    private func drawChips(for node: FlowLayout.Node, in context: inout GraphicsContext) {
        guard node.activity == .editing, node.step.linesAdded > 0 || node.step.linesRemoved > 0 else { return }
        let name = URL(fileURLWithPath: node.step.target).lastPathComponent
        let rect = CGRect(x: node.center.x - 46, y: node.center.y - node.radius - 30, width: 92, height: 16)
        var connector = Path()
        connector.move(to: CGPoint(x: node.center.x, y: node.center.y - node.radius))
        connector.addLine(to: CGPoint(x: node.center.x, y: rect.maxY))
        context.stroke(connector, with: .color(Theme.editing), lineWidth: 1)
        context.fill(Path(roundedRect: rect, cornerRadius: Theme.Radius.chip), with: .color(Theme.chipAmber))
        context.stroke(Path(roundedRect: rect, cornerRadius: Theme.Radius.chip), with: .color(Theme.editing), lineWidth: 1)

        context.label(name.count > 9 ? String(name.prefix(8)) + "…" : name, at: CGPoint(x: rect.minX + 6, y: rect.midY), size: 10, weight: .medium,
                      color: Theme.editing, anchor: .leading)
        var trailing = rect.maxX - 6
        if node.step.linesRemoved > 0 {
            context.label("−\(node.step.linesRemoved)", at: CGPoint(x: trailing, y: rect.midY), size: 10, color: Theme.error, anchor: .trailing)
            trailing -= 24
        }
        if node.step.linesAdded > 0 {
            context.label("+\(node.step.linesAdded)", at: CGPoint(x: trailing, y: rect.midY), size: 10, color: Theme.running, anchor: .trailing)
        }
    }

    // MARK: Motion layer

    private func drawMotion(_ layout: FlowLayout, in context: inout GraphicsContext, at date: Date) {
        let time = date == .distantPast ? 0 : date.timeIntervalSinceReferenceDate
        // 3 dots, 1.6s down the edge, staggered by a third of a lap.
        for edge in layout.edges where layout.nodes[edge.to].isRunning {
            let (start, end) = edgeEnds(edge, layout.nodes)
            for dot in 0..<3 {
                let progress = ((time / 1.6) + Double(dot) / 3).truncatingRemainder(dividingBy: 1)
                let point = Geometry.onCurve(start, end, progress)
                context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                             with: .color(Theme.running))
            }
        }
        // While a loop is live the failed node's ring alternates every 800ms — no pulse, no glow.
        for loop in layout.loopEdges {
            let node = layout.nodes[loop.from]
            let lit = time == 0 || Int(time / 0.8) % 2 == 0
            let rect = CGRect(x: node.center.x - node.radius, y: node.center.y - node.radius,
                              width: node.radius * 2, height: node.radius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(lit ? Theme.error : Theme.errorPale), lineWidth: 2)
        }
    }
}

/// The selected node spelled out: 230 wide, 1px ink border, hard 2px offset shadow.
struct NodePopover: View {
    let node: FlowLayout.Node

    var body: some View {
        let step = node.step
        let failed = node.style == .error || step.isError
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.label + (failed ? " · failed" : step.isRunning ? " · running" : ""))
                    .font(Theme.ui(12, .semibold)).foregroundStyle(failed ? Theme.error : Theme.ink)
                Spacer(minLength: 6)
                if step.iteration >= 2 {
                    Text("iteration \(step.iteration)/\(max(step.iteration, node.loopCount))")
                        .font(Theme.ui(10)).foregroundStyle(Theme.mute)
                }
            }
            if !step.detail.isEmpty {
                Text(step.detail).font(Theme.mono(11)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            Text(facts).font(Theme.ui(11)).foregroundStyle(Theme.mute).lineLimit(1)
            if let error = step.errorText, !error.isEmpty {
                Text(FlowLayout.shortError(error)).font(Theme.ui(11)).foregroundStyle(Theme.error).lineLimit(2)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(width: 230, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.ink, lineWidth: 1))
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.ink).offset(x: 2, y: 2))
        .allowsHitTesting(false)
    }

    private var facts: String {
        var parts: [String] = []
        if let duration = node.step.duration { parts.append(duration.secondsText) }
        if node.step.tokens > 0 { parts.append("\(node.step.tokens.compact) tokens") }
        if node.step.isError { parts.append(FlowLayout.shortError(node.step.errorText)) }
        return parts.isEmpty ? node.sub : parts.joined(separator: " · ")
    }
}
