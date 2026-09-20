import HUDCore
import SwiftUI

/// ─ brain ─ : what the agent is holding in context, one indented list per layer.
struct BrainPane: View {
    let agent: AgentSnapshot

    private static let layerNames: [BrainItem.Layer: String] = [
        .prompt: "prompt", .files: "files", .tools: "tools", .reasoning: "reasoning", .output: "output",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TermText(contextLine)
            TermList(rows: rows)
        }
    }

    private var rows: [TermRow] {
        guard !agent.brain.isEmpty else { return [TermRow("nothing in context yet", Term.mute)] }
        let peak = max(1, agent.brain.map(\.tokens).max() ?? 1)
        return BrainItem.Layer.allCases.flatMap { layer -> [TermRow] in
            let items = agent.brain.filter { $0.layer == layer }.sorted { $0.tokens > $1.tokens }
            guard !items.isEmpty else { return [] }
            var header = TermRow("ctx \(Self.layerNames[layer] ?? "")  ", Term.mute)
            header.add(items.reduce(0) { $0 + $1.tokens }.compact, Term.ink)
            return [header] + items.prefix(4).map { line($0, peak: peak) }
        }
    }

    /// `context  128.4k / 200k  ████████████░░░░░░░░  64%`
    private var contextLine: TermRow {
        let fill = agent.contextFill
        var row = TermRow("context  ", Term.mute)
        row.add("\(agent.contextTokens.compact) / \(agent.contextMax.compact)", Term.ink)
        row.add("  ")
        row.add(Term.bar(fill, 20, fill: "█"), fill >= 0.75 ? Term.error : fill >= 0.6 ? Term.editing : Term.reading)
        row.add("  \(Int((fill * 100).rounded()))%", Term.ink)
        return row
    }

    private func line(_ item: BrainItem, peak: Int) -> TermRow {
        // Bright while the item was touched this turn, muted once it is only still resident.
        let fresh = item.lastTurn >= agent.turnIndex
        var row = TermRow("  " + Term.pad(item.name, 30), fresh ? Term.ink : Term.ink2)
        row.add(Term.padStart(item.tokens.compact, 7), Term.mute)
        row.add("  ")
        row.add(Term.bar(Double(item.tokens) / Double(peak), 10, fill: "█"),
                fresh ? Term.color(for: item.activity) : Term.waiting)
        return row
    }
}

/// ─ loops ─ : every retry loop of the turn as an iteration table.
struct LoopsPane: View {
    let agent: AgentSnapshot

    var body: some View { TermList(rows: rows) }

    private var rows: [TermRow] {
        guard !agent.loops.isEmpty else { return [TermRow("no loops this session", Term.mute)] }
        return agent.loops.suffix(4).flatMap { loop -> [TermRow] in
            [headline(loop),
             TermRow("  " + Term.pad("ITER", 8) + Term.padStart("DUR", 7) + Term.padStart("TOK", 8) + "   RESULT", Term.mute)]
                + loop.iterations.enumerated().map { line(index: $0.offset, iteration: $0.element, loop: loop) }
                + [TermRow("")]
        }
    }

    private func headline(_ loop: LoopInfo) -> TermRow {
        var row = TermRow("loop · ", Term.mute)
        row.add(loop.label, Term.editing)
        row.add(" · ", Term.mute)
        row.add("×\(loop.count)", loop.resolved ? Term.mute : Term.error, weight: .bold)
        row.add(loop.resolved ? " · resolved" : " · same error ×\(loop.sameErrorCount)",
                loop.resolved ? Term.running : Term.error)
        return row
    }

    private func line(index: Int, iteration: LoopInfo.Iteration, loop: LoopInfo) -> TermRow {
        let last = index == loop.count - 1
        var row = TermRow("  " + Term.pad("iter \(index + 1)", 8), Term.ink)
        row.add(Term.padStart(iteration.duration.secondsText, 7), Term.mute)
        row.add(Term.padStart(iteration.tokens.compact, 8), Term.mute)
        row.add("   ")
        let resolved = last && loop.resolved
        row.add(resolved ? "✓ passed" : "✕ " + String(iteration.errorText.prefix(70)),
                resolved ? Term.running : Term.error, bg: last && !loop.resolved ? Term.errBg : nil)
        return row
    }
}

/// ─ files ─ : the files this session has touched, grouped by folder.
struct FilesPane: View {
    let agent: AgentSnapshot

    var body: some View { TermList(rows: rows) }

    private var rows: [TermRow] {
        guard !agent.files.isEmpty else { return [TermRow("no files touched yet", Term.mute)] }
        let root = agent.cwd
        let byFolder = Dictionary(grouping: agent.files.prefix(40)) { file -> String in
            var folder = URL(fileURLWithPath: file.path).deletingLastPathComponent().path
            if folder.hasPrefix(root) { folder = String(folder.dropFirst(root.count)) }
            let trimmed = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return trimmed.isEmpty ? "." : trimmed
        }
        var rows = [TermRow(URL(fileURLWithPath: root).lastPathComponent + "/", Term.ink)]
        for folder in byFolder.keys.sorted() {
            let files = byFolder[folder]!.sorted { $0.lastTouched > $1.lastTouched }
            if folder != "." { rows.append(TermRow("  " + folder + "/", Term.mute)) }
            rows += files.enumerated().map {
                line($0.element, last: $0.offset == files.count - 1, nested: folder != ".")
            }
        }
        return rows
    }

    private func line(_ file: FileChange, last: Bool, nested: Bool) -> TermRow {
        let activity: ActivityKind = file.kind == .read ? .reading : .editing
        let color = Term.color(for: activity)
        var row = TermRow(String(repeating: " ", count: nested ? 4 : 2), Term.mute)
        // Changes made by a shell command rather than an Edit call are drawn dashed.
        row.add(last ? "└" : "├", Term.mute)
        row.add(file.viaShell ? "╌ " : "─ ", Term.mute)
        row.add(Term.glyph(for: activity) + " ", color)
        row.add(Term.pad(URL(fileURLWithPath: file.path).lastPathComponent, 30), Term.ink)
        if file.linesAdded > 0 { row.add(Term.padStart("+\(file.linesAdded)", 6), Term.running) } else { row.space(6) }
        if file.linesRemoved > 0 { row.add(Term.padStart("−\(file.linesRemoved)", 6), Term.error) } else { row.space(6) }
        row.add("   " + Term.pad(counts(file), 9), Term.mute)
        row.add(file.lastTouched.shortClockText, Term.mute)
        return row
    }

    /// Edits and reads come from the transcript; a file only seen on disk just reports what happened to it.
    private func counts(_ file: FileChange) -> String {
        if file.edits > 0 { return "\(file.edits) edit\(file.edits == 1 ? "" : "s")" }
        if file.reads > 0 { return "\(file.reads) read\(file.reads == 1 ? "" : "s")" }
        return file.viaShell ? "shell" : file.kind.rawValue
    }
}
