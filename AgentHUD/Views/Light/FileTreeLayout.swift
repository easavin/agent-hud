import CoreGraphics
import Foundation
import HUDCore

/// Turns the files a session touched into a left→right dendrogram: the session folder on the left,
/// folders in the columns after it, and every file in one aligned column on the right — each file on
/// its own row, each folder centred on the rows it spans.
struct FileTreeLayout {
    struct Node: Identifiable {
        let id: String
        var name: String
        var depth: Int
        /// Folders: the leading edge of the pill. Files: the centre of the dot.
        var point: CGPoint
        /// nil for folders.
        var file: FileChange?
        var isRoot = false
        /// How many files sit under this folder on the canvas…
        var leaves = 0
        /// …and how many the session touched there in all, shown or not.
        var total = 0
    }

    struct Edge {
        var from: Int
        var to: Int
    }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    /// Files left out because the canvas ran out of rows.
    private(set) var hidden = 0
    private(set) var rowHeight: CGFloat = FileTreeLayout.minRowHeight
    private(set) var columnWidth: CGFloat = 0
    /// x of the file dots.
    private(set) var leafX: CGFloat = 0
    /// Trailing edge of the diff bars, the right end of every file row.
    private(set) var trailingX: CGFloat = 0
    /// Largest `linesAdded + linesRemoved` on the canvas; the diff bars are scaled against it.
    private(set) var maxChurn = 1
    /// The file touched last, which the view rings.
    private(set) var newestId: String?

    static let minRowHeight: CGFloat = 19
    static let maxRowHeight: CGFloat = 28
    static let firstX: CGFloat = 14
    static let inset: CGFloat = 12
    static let pillHeight: CGFloat = 17
    /// Folders deeper than this are folded into one name, so the tree stays three columns wide.
    static let maxFolderDepth = 2

    /// A folder pill may grow this wide before its name is cut; the rest of the column is for links.
    var pillMaxWidth: CGFloat { columnWidth - 34 }

    func columnX(_ depth: Int) -> CGFloat { Self.firstX + CGFloat(depth) * columnWidth }

    // MARK: Build

    private final class Branch {
        let name: String
        var children: [Branch] = []
        var file: FileChange?
        /// Most recent touch anywhere under this branch, which is how siblings are ordered.
        var touched: Date = .distantPast
        var total = 0
        var shown = false

        init(name: String) { self.name = name }

        func child(named name: String) -> Branch {
            if let existing = children.first(where: { $0.name == name && $0.file == nil }) { return existing }
            let branch = Branch(name: name)
            children.append(branch)
            return branch
        }
    }

    init(agent: AgentSnapshot, size: CGSize) {
        let usable = size.height - Self.inset * 2
        let maxRows = max(3, Int(usable / Self.minRowHeight))
        let shownCount = min(agent.files.count, maxRows)
        hidden = agent.files.count - shownCount
        guard shownCount > 0 else { return }

        // The whole session goes into the tree first so a folder can say "3/14"; only the most
        // recent files survive the prune and get a row.
        let rootPath = agent.cwd
        let root = Branch(name: URL(fileURLWithPath: rootPath).lastPathComponent)
        for (index, file) in agent.files.enumerated() {
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
            leaf.shown = index < shownCount
            cursor.children.append(leaf)
        }
        Self.propagate(root)
        Self.prune(root)
        Self.sortBranches(root)
        Self.compress(root)

        let shown = agent.files.prefix(shownCount)
        maxChurn = max(1, shown.map { $0.linesAdded + $0.linesRemoved }.max() ?? 1)
        newestId = shown.max { $0.lastTouched < $1.lastTouched }?.path

        // Columns: one per folder level, then the files. The file column keeps about two fifths of
        // the width for names and diff bars; folder columns share the rest, within reason.
        let folderColumns = CGFloat(Self.folderDepth(root) + 1)
        let leafRoom = min(480, max(230, size.width * 0.4))
        columnWidth = min(240, max(96, (size.width - Self.firstX - leafRoom) / folderColumns))
        leafX = Self.firstX + folderColumns * columnWidth + 10
        trailingX = min(size.width - 14, leafX + 520)

        // Few files spread out and sit in the middle of the card rather than hugging its top edge.
        rowHeight = min(Self.maxRowHeight, max(Self.minRowHeight, usable / CGFloat(shownCount)))
        let top = Self.inset + max(0, (usable - rowHeight * CGFloat(shownCount)) / 2) + rowHeight / 2

        var row = 0
        _ = place(root, depth: 0, row: &row, top: top, parent: nil)
    }

    /// A folder is as recent as its most recent file, and counts every file below it.
    private static func propagate(_ branch: Branch) {
        if branch.file != nil { branch.total = 1 }
        for child in branch.children {
            propagate(child)
            branch.touched = max(branch.touched, child.touched)
            branch.total += child.total
            branch.shown = branch.shown || child.shown
        }
    }

    private static func prune(_ branch: Branch) {
        branch.children.removeAll { !$0.shown }
        branch.children.forEach(prune)
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
                merged.total = only.total
                current = merged
            }
            branch.children[index] = current
        }
    }

    /// How many folder levels hang below this one.
    private static func folderDepth(_ branch: Branch) -> Int {
        branch.children.filter { $0.file == nil }.map { folderDepth($0) + 1 }.max() ?? 0
    }

    /// Depth-first: every file takes the next row in the file column, every folder sits at the
    /// middle of its span in the column for its depth.
    private mutating func place(_ branch: Branch, depth: Int, row: inout Int, top: CGFloat, parent: Int?) -> Int {
        let index = nodes.count
        nodes.append(Node(id: branch.file?.path ?? "\(index)-\(branch.name)", name: branch.name, depth: depth,
                          point: CGPoint(x: columnX(depth), y: 0), file: branch.file, isRoot: depth == 0,
                          total: branch.total))
        if let parent { edges.append(Edge(from: parent, to: index)) }

        if branch.file != nil {
            nodes[index].point = CGPoint(x: leafX, y: top + CGFloat(row) * rowHeight)
            nodes[index].leaves = 1
            row += 1
            return index
        }
        var first: CGFloat?, last: CGFloat = 0, leaves = 0
        for child in branch.children {
            let placed = place(child, depth: depth + 1, row: &row, top: top, parent: index)
            if first == nil { first = nodes[placed].point.y }
            last = nodes[placed].point.y
            leaves += nodes[placed].leaves
        }
        nodes[index].point.y = ((first ?? 0) + last) / 2
        nodes[index].leaves = leaves
        return index
    }
}
