import HUDCore
import SwiftUI

/// Hero card, "Files" tab: the session's working directory as a schematic — folders branch,
/// files hang off them sized by how much they were edited.
struct FilesView: View {
    let agent: AgentSnapshot
    static let legendHeight: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let canvas = CGSize(width: max(320, proxy.size.width), height: max(120, proxy.size.height - Self.legendHeight))
            let rows = max(3, Int((canvas.height - FileTreeLayout.topY) / FileTreeLayout.rowHeight))
            let tree = FileTreeLayout(agent: agent, maxRows: rows)
            VStack(spacing: 0) {
                Canvas { context, size in draw(tree, in: &context, size: size) }
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

    private func draw(_ tree: FileTreeLayout, in context: inout GraphicsContext, size: CGSize) {
        for edge in tree.edges { drawEdge(tree, edge, in: &context) }
        for node in tree.nodes {
            if let file = node.file {
                drawFile(node, file, in: &context, width: size.width)
            } else {
                drawFolder(node, in: &context)
            }
        }
    }

    /// Classic file-tree elbow: down the parent's spine, then across into the child.
    private func drawEdge(_ tree: FileTreeLayout, _ edge: FileTreeLayout.Edge, in context: inout GraphicsContext) {
        let parent = tree.nodes[edge.from], child = tree.nodes[edge.to]
        let spine = parent.point.x
        let corner: CGFloat = 5
        var path = Path()
        path.move(to: CGPoint(x: spine, y: parent.point.y + 7))
        path.addLine(to: CGPoint(x: spine, y: child.point.y - corner))
        path.addQuadCurve(to: CGPoint(x: spine + corner, y: child.point.y),
                          control: CGPoint(x: spine, y: child.point.y))
        path.addLine(to: CGPoint(x: child.point.x - radius(child) - 3, y: child.point.y))
        context.stroke(path, with: .color(Theme.divider), lineWidth: 1)
    }

    private func radius(_ node: FileTreeLayout.Node) -> CGFloat {
        guard let file = node.file else { return 5 }
        // r = 4 + one point per edit, so a file worked over reads as the biggest dot on its row.
        return min(9, 4 + CGFloat(file.edits))
    }

    private func drawFolder(_ node: FileTreeLayout.Node, in context: inout GraphicsContext) {
        let box = CGRect(x: node.point.x - 5, y: node.point.y - 5, width: 10, height: 10)
        if node.isRoot {
            context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(Theme.ink))
        } else {
            context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(Theme.track))
            context.stroke(Path(roundedRect: box, cornerRadius: 3), with: .color(Theme.borderStrong), lineWidth: 1)
        }
        var x = node.point.x + 11
        // A folder label has to stay inside its column or it runs over the files in the next one.
        let name = folderName(node.name, to: FileTreeLayout.columnWidth - 34)
        context.label(name + "/", at: CGPoint(x: x, y: node.point.y), size: 11,
                      weight: node.isRoot ? .semibold : .medium,
                      color: node.isRoot ? Theme.ink : Theme.mute, anchor: .leading)
        x += CGFloat(name.count + 1) * 6.1 + 6
        context.label("\(node.leaves)", at: CGPoint(x: x, y: node.point.y), size: 10, color: Theme.waiting, anchor: .leading)
    }

    private func drawFile(_ node: FileTreeLayout.Node, _ file: FileChange, in context: inout GraphicsContext, width: CGFloat) {
        let activity: ActivityKind = file.kind == .read ? .reading : file.kind == .created ? .running : .editing
        let color = Theme.color(for: activity)
        let r = radius(node)
        let circle = Path(ellipseIn: CGRect(x: node.point.x - r, y: node.point.y - r, width: r * 2, height: r * 2))
        context.fill(circle, with: .color(color.opacity(0.25)))
        // A change made by a shell command rather than an Edit call gets a dashed ring.
        context.stroke(circle, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5, dash: file.viaShell ? [2, 2] : []))

        var x = node.point.x + r + 6
        let counts = trailing(file)
        let room = width - x - CGFloat(counts.count) * 6.4 - 12
        let name = clip(node.name, to: room)
        context.label(name, at: CGPoint(x: x, y: node.point.y), size: 11, color: Theme.ink, anchor: .leading)
        x += CGFloat(name.count) * 6.1 + 8

        if file.linesAdded > 0 {
            context.label("+\(file.linesAdded)", at: CGPoint(x: x, y: node.point.y), size: 10, color: Theme.running, anchor: .leading)
            x += CGFloat("+\(file.linesAdded)".count) * 6.1 + 5
        }
        if file.linesRemoved > 0 {
            context.label("−\(file.linesRemoved)", at: CGPoint(x: x, y: node.point.y), size: 10, color: Theme.error, anchor: .leading)
            x += CGFloat("−\(file.linesRemoved)".count) * 6.1 + 5
        }
        if file.linesAdded == 0, file.linesRemoved == 0 {
            context.label(counts, at: CGPoint(x: x, y: node.point.y), size: 10, color: Theme.mute, anchor: .leading)
        }
    }

    /// What to say about a file with no line counts: how it was touched.
    private func trailing(_ file: FileChange) -> String {
        if file.edits > 0 { return "\(file.edits) edit\(file.edits == 1 ? "" : "s")" }
        if file.reads > 0 { return "\(file.reads) read\(file.reads == 1 ? "" : "s")" }
        return file.viaShell ? "shell" : file.kind.rawValue
    }

    /// Folders are cut from the front, so `AgentHUD/Views/Light` becomes `…/Light` rather than
    /// `AgentHUD/Vie…` — the tail is the part that says where you are.
    private func folderName(_ name: String, to width: CGFloat) -> String {
        let fits = max(4, Int(width / 6.1))
        guard name.count > fits else { return name }
        if let last = name.split(separator: "/").last, last.count + 2 <= fits { return "…/" + last }
        return "…" + String(name.suffix(fits - 1))
    }

    /// Canvas text does not truncate itself; 6.1pt per character is close enough at 11pt.
    private func clip(_ text: String, to width: CGFloat) -> String {
        let fits = max(4, Int(width / 6.1))
        return text.count <= fits ? text : String(text.prefix(fits - 1)) + "…"
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
            Text("size = edits · dashed = changed by a shell command")
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
