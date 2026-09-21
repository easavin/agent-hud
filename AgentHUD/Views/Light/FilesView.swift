import HUDCore
import SwiftUI

/// Hero card, "Files" tab: the session's working directory as a left→right dendrogram — folder pills
/// branch on curved links, files line up in one column with their dot sized by edits and a diff bar.
struct FilesView: View {
    let agent: AgentSnapshot
    static let legendHeight: CGFloat = 22
    /// Every file name starts here, whatever the size of its dot.
    private static let nameOffset: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let canvas = CGSize(width: max(320, proxy.size.width), height: max(120, proxy.size.height - Self.legendHeight))
            let tree = FileTreeLayout(agent: agent, size: canvas)
            VStack(spacing: 0) {
                Canvas { context, _ in draw(tree, in: &context) }
                    .frame(width: canvas.width, height: canvas.height)
                legend(tree)
            }
        }
        .overlay {
            if agent.files.isEmpty {
                Text("No files touched yet").font(Theme.ui(13)).foregroundStyle(Theme.mute)
            }
        }
    }

    // MARK: Drawing

    /// A folder is a pill holding its name and file count; links leave from its trailing edge.
    private struct Pill {
        var rect: CGRect
        var name: String
        var count: String
    }

    private func draw(_ tree: FileTreeLayout, in context: inout GraphicsContext) {
        var pills: [Int: Pill] = [:]
        for (index, node) in tree.nodes.enumerated() where node.file == nil {
            pills[index] = pill(for: node, in: tree, context: context)
        }
        // Folder links go down first so the coloured file links cross over them, not under.
        for edge in tree.edges where tree.nodes[edge.to].file == nil { drawEdge(tree, edge, pills, in: &context) }
        for edge in tree.edges where tree.nodes[edge.to].file != nil { drawEdge(tree, edge, pills, in: &context) }
        for (index, node) in tree.nodes.enumerated() {
            if let file = node.file {
                drawFile(node, file, in: tree, context: &context)
            } else if let pill = pills[index] {
                drawFolder(node, pill, in: &context)
            }
        }
    }

    private func pill(for node: FileTreeLayout.Node, in tree: FileTreeLayout, context: GraphicsContext) -> Pill {
        let count = node.total > node.leaves ? "\(node.leaves)/\(node.total)" : "\(node.leaves)"
        let countWidth = context.width(of: count, size: 10)
        let weight: Font.Weight = node.isRoot ? .semibold : .medium
        let name = folderName(node.name + "/", isRoot: node.isRoot, to: tree.pillMaxWidth(node.depth) - countWidth - 22, weight: weight, context: context)
        let width = 8 + context.width(of: name, size: 11, weight: weight) + 6 + countWidth + 8
        let rect = CGRect(x: node.point.x, y: node.point.y - FileTreeLayout.pillHeight / 2,
                          width: width, height: FileTreeLayout.pillHeight)
        return Pill(rect: rect, name: name, count: count)
    }

    /// Folders are cut from the front, so `AgentHUD/Views/Light/` becomes `…/Light/` rather than
    /// `AgentHUD/Vie…` — the tail is the part that says where you are.
    private func folderName(_ name: String, isRoot: Bool, to width: CGFloat, weight: Font.Weight, context: GraphicsContext) -> String {
        guard context.width(of: name, size: 11, weight: weight) > width else { return name }
        // The session folder is named in the card's title, so a cut version of it says nothing new.
        if isRoot { return "./" }
        let parts = name.split(separator: "/")
        if parts.count > 1, let last = parts.last {
            let short = "…/\(last)/"
            if context.width(of: short, size: 11, weight: weight) <= width { return short }
            return context.fit(name, to: width, size: 11, weight: weight, keepTail: true)
        }
        // A single name reads better cut at the end: `Resour…/`, not `…ources/`.
        let slash = context.width(of: "/", size: 11, weight: weight)
        return context.fit(String(name.dropLast()), to: width - slash, size: 11, weight: weight, cutEnd: true) + "/"
    }

    /// The link bends inside the gap after its parent's column and then runs flat along the child's
    /// own row, which nothing else occupies — so a link never crosses a pill or a label.
    private func drawEdge(_ tree: FileTreeLayout, _ edge: FileTreeLayout.Edge, _ pills: [Int: Pill], in context: inout GraphicsContext) {
        let parent = tree.nodes[edge.from], child = tree.nodes[edge.to]
        guard let from = pills[edge.from]?.rect else { return }
        let start = CGPoint(x: from.maxX, y: parent.point.y)
        let bend = CGPoint(x: tree.columnX(parent.depth + 1), y: child.point.y)
        var path = Geometry.link(start, bend)
        if let file = child.file {
            path.addLine(to: CGPoint(x: child.point.x - radius(file) - 3, y: child.point.y))
            // A file worked over hard pulls a heavier line, up to 3pt.
            let churn = Double(file.linesAdded + file.linesRemoved) / Double(tree.maxChurn)
            let width = file.kind == .read ? 1 : 1 + 2 * churn.squareRoot()
            context.stroke(path, with: .color(color(file).opacity(0.45)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
        } else {
            context.stroke(path, with: .color(Theme.borderStrong), lineWidth: 1)
        }
    }

    private func color(_ file: FileChange) -> Color {
        Theme.color(for: file.kind == .read ? .reading : file.kind == .created ? .running : .editing)
    }

    /// r = 4 + one point per edit, so a file worked over reads as the biggest dot in the column.
    private func radius(_ file: FileChange) -> CGFloat { min(9, 4 + CGFloat(file.edits)) }

    private func drawFolder(_ node: FileTreeLayout.Node, _ pill: Pill, in context: inout GraphicsContext) {
        let shape = Path(roundedRect: pill.rect, cornerRadius: Theme.Radius.badge)
        if node.isRoot {
            context.fill(shape, with: .color(Theme.ink))
        } else {
            context.fill(shape, with: .color(Theme.track))
            context.stroke(shape, with: .color(Theme.borderStrong), lineWidth: 1)
        }
        context.label(pill.name, at: CGPoint(x: pill.rect.minX + 8, y: pill.rect.midY), size: 11,
                      weight: node.isRoot ? .semibold : .medium,
                      color: node.isRoot ? Theme.onInk : Theme.ink, anchor: .leading)
        context.label(pill.count, at: CGPoint(x: pill.rect.maxX - 8, y: pill.rect.midY), size: 10,
                      color: node.isRoot ? Theme.onInk.opacity(0.65) : Theme.mute, anchor: .trailing)
    }

    private func drawFile(_ node: FileTreeLayout.Node, _ file: FileChange, in tree: FileTreeLayout, context: inout GraphicsContext) {
        let color = color(file)
        let y = node.point.y
        let r = min(radius(file), tree.rowHeight / 2 - 1)
        let circle = Path(ellipseIn: CGRect(x: node.point.x - r, y: y - r, width: r * 2, height: r * 2))
        context.fill(circle, with: .color(color.opacity(0.25)))
        // A change made by a shell command rather than an Edit call gets a dashed ring.
        context.stroke(circle, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5, dash: file.viaShell ? [2, 2] : []))

        // Right to left: diff bar, then the counts, then whatever is left goes to the name.
        let changed = file.linesAdded + file.linesRemoved > 0
        var trailing = tree.trailingX
        if tree.barWidth > 0 {
            if changed { drawBar(file, in: tree, y: y, context: &context) }
            trailing -= tree.barWidth + 8
        }
        if changed {
            let counts = [(file.linesRemoved, "−", Theme.error), (file.linesAdded, "+", Theme.running)]
            for (lines, sign, tint) in counts where lines > 0 {
                let text = sign + "\(lines)"
                context.label(text, at: CGPoint(x: trailing, y: y), size: 10, color: tint, anchor: .trailing)
                trailing -= context.width(of: text, size: 10) + 5
            }
        } else {
            let text = touch(file)
            context.label(text, at: CGPoint(x: trailing, y: y), size: 10, color: Theme.mute, anchor: .trailing)
            trailing -= context.width(of: text, size: 10) + 5
        }

        let isNewest = node.id == tree.newestId
        let weight: Font.Weight = isNewest ? .semibold : .regular
        let nameX = node.point.x + Self.nameOffset
        let name = context.fit(node.name, to: trailing - 10 - nameX, size: 11, weight: weight)
        context.label(name, at: CGPoint(x: nameX, y: y), size: 11, weight: weight, color: Theme.ink, anchor: .leading)

        // A dotted leader carries the eye from the name across to its numbers.
        let leaderStart = nameX + context.width(of: name, size: 11, weight: weight) + 8
        if trailing - 4 - leaderStart > 12 {
            var leader = Path()
            leader.move(to: CGPoint(x: leaderStart, y: y + 0.5))
            leader.addLine(to: CGPoint(x: trailing - 4, y: y + 0.5))
            context.stroke(leader, with: .color(Theme.borderStrong), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.5, 4]))
        }
    }

    /// Added and removed lines as one green-then-red bar, its length the file's share of the
    /// heaviest churn on the canvas (square-rooted, or one 400-line file flattens the rest).
    private func drawBar(_ file: FileChange, in tree: FileTreeLayout, y: CGFloat, context: inout GraphicsContext) {
        let track = CGRect(x: tree.trailingX - tree.barWidth, y: y - 2.5, width: tree.barWidth, height: 5)
        context.fill(Path(roundedRect: track, cornerRadius: Theme.Radius.bar), with: .color(Theme.track))
        let churn = file.linesAdded + file.linesRemoved
        let length = max(3, tree.barWidth * (Double(churn) / Double(tree.maxChurn)).squareRoot())
        let added = length * CGFloat(file.linesAdded) / CGFloat(churn)
        context.fill(Path(roundedRect: CGRect(x: track.minX, y: track.minY, width: added, height: 5), cornerRadius: Theme.Radius.bar),
                     with: .color(Theme.running))
        context.fill(Path(roundedRect: CGRect(x: track.minX + added, y: track.minY, width: length - added, height: 5), cornerRadius: Theme.Radius.bar),
                     with: .color(Theme.error))
    }

    /// What to say about a file with no line counts: how it was touched.
    private func touch(_ file: FileChange) -> String {
        if file.edits > 0 { return "\(file.edits) edit\(file.edits == 1 ? "" : "s")" }
        if file.reads > 0 { return "\(file.reads) read\(file.reads == 1 ? "" : "s")" }
        return file.viaShell ? "shell" : file.kind.rawValue
    }

    private func legend(_ tree: FileTreeLayout) -> some View {
        HStack(spacing: 12) {
            ForEach([("created", Theme.running), ("edited", Theme.editing), ("read", Theme.reading)], id: \.0) { entry in
                HStack(spacing: 4) {
                    Circle().fill(entry.1.opacity(0.25))
                        .overlay(Circle().strokeBorder(entry.1, lineWidth: 1.5))
                        .frame(width: 8, height: 8)
                    Text(entry.0).font(Theme.ui(10)).foregroundStyle(Theme.mute)
                }
            }
            Text("dot = edits · line and bar = lines changed · dashed = changed by a shell command")
                .font(Theme.ui(10)).foregroundStyle(Theme.waiting)
            Spacer(minLength: 0)
            if tree.hidden > 0 {
                Text("+\(tree.hidden) more files").font(Theme.ui(10)).foregroundStyle(Theme.mute)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Self.legendHeight)
    }
}
