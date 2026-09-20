import CoreGraphics
import Foundation
import HUDCore

/// Turns the files a session touched into a positioned directory tree: folders branch, files are leaves,
/// each leaf on its own row and each folder centred on the rows it spans.
struct FileTreeLayout {
    struct Node: Identifiable {
        let id: String
        var name: String
        var depth: Int
        var point: CGPoint
        /// nil for folders.
        var file: FileChange?
        var isRoot = false
        /// How many files sit under this folder, for its badge.
        var leaves = 0
    }

    struct Edge {
        var from: Int
        var to: Int
    }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    /// Files left out because the canvas ran out of rows.
    private(set) var hidden = 0

    static let rowHeight: CGFloat = 16
    static let columnWidth: CGFloat = 116
    static let firstX: CGFloat = 14
    static let topY: CGFloat = 12
    /// Folders deeper than this are folded into one name, so the tree stays three columns wide.
    static let maxFolderDepth = 2

    // MARK: Build

    private final class Branch {
        let name: String
        var children: [Branch] = []
        var file: FileChange?
        /// Most recent touch anywhere under this branch, which is how siblings are ordered.
        var touched: Date = .distantPast

        init(name: String) { self.name = name }

        func child(named name: String) -> Branch {
            if let existing = children.first(where: { $0.name == name && $0.file == nil }) { return existing }
            let branch = Branch(name: name)
            children.append(branch)
            return branch
        }
    }

    init(agent: AgentSnapshot, maxRows: Int) {
        let shown = Array(agent.files.prefix(maxRows))
        hidden = agent.files.count - shown.count
        guard !shown.isEmpty else { return }

        let rootPath = agent.cwd
        let root = Branch(name: URL(fileURLWithPath: rootPath).lastPathComponent)
        for file in shown {
            let inside = file.path.hasPrefix(rootPath)
            let relative = inside ? String(file.path.dropFirst(rootPath.count)) : file.path
            var parts = relative.split(separator: "/").map(String.init)
            guard let name = parts.popLast() else { continue }
            if inside {
                // Everything past the second folder is folded into one name: "src" / "retry/deep".
                if parts.count > Self.maxFolderDepth {
                    parts = Array(parts.prefix(Self.maxFolderDepth - 1)) + [parts.dropFirst(Self.maxFolderDepth - 1).joined(separator: "/")]
                }
            } else {
                // A file outside the session's folder keeps only its immediate parent: reproducing an
                // absolute path would put a 90-character folder name across the whole schematic.
                parts = ["…/" + (parts.last ?? "elsewhere")]
            }
            var cursor = root
            for folder in parts { cursor = cursor.child(named: folder) }
            let leaf = Branch(name: name)
            leaf.file = file
            leaf.touched = file.lastTouched
            cursor.children.append(leaf)
        }
        Self.propagate(root)
        Self.sortBranches(root)
        Self.compress(root)

        var row = 0
        _ = place(root, depth: 0, row: &row, parent: nil)
    }

    /// A folder is as recent as its most recent file.
    @discardableResult private static func propagate(_ branch: Branch) -> Date {
        for child in branch.children { branch.touched = max(branch.touched, propagate(child)) }
        return branch.touched
    }

    /// Folders first, then files; newest first within each.
    private static func sortBranches(_ branch: Branch) {
        branch.children.sort { a, b in
            if (a.file == nil) != (b.file == nil) { return a.file == nil }
            return a.touched > b.touched
        }
        branch.children.forEach(sortBranches)
    }

    /// A folder holding nothing but one folder is drawn as `src/api`, not as two hops.
    private static func compress(_ branch: Branch) {
        for child in branch.children { compress(child) }
        for (index, child) in branch.children.enumerated() {
            var current = child
            while current.file == nil, current.children.count == 1, let only = current.children.first, only.file == nil {
                let merged = Branch(name: current.name + "/" + only.name)
                merged.children = only.children
                merged.touched = current.touched
                current = merged
            }
            branch.children[index] = current
        }
    }

    /// Depth-first: every leaf takes the next row, every folder sits at the middle of its span.
    private mutating func place(_ branch: Branch, depth: Int, row: inout Int, parent: Int?) -> Int {
        let index = nodes.count
        let x = Self.firstX + CGFloat(depth) * Self.columnWidth
        nodes.append(Node(id: "\(index)-\(branch.name)", name: branch.name, depth: depth,
                          point: CGPoint(x: x, y: 0), file: branch.file, isRoot: depth == 0))
        if let parent { edges.append(Edge(from: parent, to: index)) }

        if branch.children.isEmpty {
            nodes[index].point.y = Self.topY + CGFloat(row) * Self.rowHeight
            nodes[index].leaves = 1
            row += 1
            return index
        }
        var first: CGFloat?, last: CGFloat = 0, leaves = 0
        for child in branch.children {
            let placed = place(child, depth: depth + 1, row: &row, parent: index)
            if first == nil { first = nodes[placed].point.y }
            last = nodes[placed].point.y
            leaves += nodes[placed].leaves
        }
        nodes[index].point.y = ((first ?? 0) + last) / 2
        nodes[index].leaves = leaves
        return index
    }
}
