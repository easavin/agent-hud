import AppKit
import HUDCore
import SwiftUI

/// Design tokens for the terminal / TUI restyle (design_handoff_agent_hud/README.md).
/// Everything is one monospace face at 12/16 on a character grid: no gradients, no glow, no rounded chrome.
enum Term {
    // MARK: Color

    static let bg = Color(hex: 0x0B0D10)
    static let border = Color(hex: 0x2B303A)
    static let borderOuter = Color(hex: 0x23272F)
    static let ink = Color(hex: 0xE8E8E8)
    static let ink2 = Color(hex: 0xC9CCD3)
    static let mute = Color(hex: 0x7A8290)
    static let rowSelected = Color(hex: 0x161B24)
    static let errBg = Color(hex: 0x2A1216)
    static let errBgPulse = Color(hex: 0x3A1A20)

    static let thinking = Color(hex: 0xD18BFF)
    static let reading = Color(hex: 0x5FD7FF)
    static let editing = Color(hex: 0xFFC145)
    static let running = Color(hex: 0x7CFF9E)
    static let error = Color(hex: 0xFF6B6B)
    static let waiting = Color(hex: 0x5C6470)
    static let subagent = Color(hex: 0x4FE3C1)

    static func color(for activity: ActivityKind) -> Color {
        switch activity {
        case .thinking, .responding: thinking
        case .reading: reading
        case .editing: editing
        case .running: running
        case .subagent: subagent
        case .error: error
        case .waiting, .idle: waiting
        }
    }

    /// Agent names in the thought stream are colored by the model that is answering.
    static func modelColor(_ model: String?) -> Color {
        let name = model ?? ""
        if name.contains("fable") || name.contains("mythos") { return ink }
        if name.contains("opus") { return Color(hex: 0x8FB4FF) }
        if name.contains("sonnet") { return Color(hex: 0xFFD98A) }
        return Color(hex: 0x9AA3B2)
    }

    // MARK: Glyphs

    static func glyph(for activity: ActivityKind) -> String {
        switch activity {
        case .thinking: "◐"
        case .responding: "■"
        case .reading: "⌕"
        case .editing: "✎"
        case .running: "▶"
        case .subagent: "◌"
        case .error: "✕"
        case .waiting, .idle: "·"
        }
    }

    // MARK: Type

    /// The handoff asks for JetBrains Mono. Menlo is the fallback rather than SF Mono because SF Mono
    /// has no ◐ ⌕ ✎ ✕ ◌ — they would fall back to a proportional face and break the grid.
    static let fontName: String = {
        for candidate in ["JetBrains Mono", "JetBrainsMono-Regular"] where NSFont(name: candidate, size: 12) != nil {
            return candidate
        }
        return "Menlo"
    }()

    static let size: CGFloat = 12
    /// Every line box is 16px; a few dense panes use 15 or 13 (stats, thoughts, heat rows).
    static let line: CGFloat = 16

    static func font(_ weight: Font.Weight = .regular) -> Font {
        .custom(fontName, fixedSize: size).weight(weight)
    }

    /// Advance of one cell, used wherever pixels have to be turned back into columns (lane hover).
    static let cell: CGFloat = {
        let font = NSFont(name: fontName, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return ("M" as NSString).size(withAttributes: [.font: font]).width
    }()

    static func columns(_ width: CGFloat) -> Int { Int(width / cell) }

    // MARK: Character charts

    static let blocks = Array("▁▂▃▄▅▆▇█")
    static let heatLevels = Array("░▒▓█")

    /// `▇▇▇▇░░░░` — a bar of `width` cells filled by `fraction`.
    static func bar(_ fraction: Double, _ width: Int, fill: Character = "▇", empty: Character = "░") -> String {
        let filled = max(0, min(width, Int((fraction * Double(width)).rounded())))
        return String(repeating: fill, count: filled) + String(repeating: empty, count: width - filled)
    }

    /// `▁▂▃▅▇` — the last `width` samples as block characters, flat while nothing is happening.
    static func spark(_ values: [Int], _ width: Int) -> String {
        var samples = Array(values.suffix(width))
        if samples.count < width { samples = [Int](repeating: 0, count: width - samples.count) + samples }
        let peak = Double(samples.max() ?? 0)
        guard peak > 0 else { return String(repeating: blocks[0], count: width) }
        return String(samples.map { value in
            blocks[max(0, min(blocks.count - 1, Int((Double(value) / peak * Double(blocks.count - 1)).rounded())))]
        })
    }

    static func heat(_ level: Double) -> Character {
        heatLevels[max(0, min(3, Int(level * 3.999)))]
    }

    // MARK: Column padding

    /// Pads (or truncates) to exactly `width` cells so columns stay aligned.
    static func pad(_ text: String, _ width: Int) -> String {
        let clipped = text.count > width ? String(text.prefix(max(0, width - 1))) + "…" : text
        return clipped + String(repeating: " ", count: width - clipped.count)
    }

    /// Right-aligned version of `pad`.
    static func padStart(_ text: String, _ width: Int) -> String {
        let clipped = text.count > width ? String(text.suffix(width)) : text
        return String(repeating: " ", count: width - clipped.count) + clipped
    }
}

// MARK: - Lines

/// One line of the grid, built run by run. Backing store is an `AttributedString` so a whole line
/// renders as a single `Text`: spaces are preserved exactly and the monospace face does the aligning.
struct TermRow {
    private(set) var text = AttributedString()
    /// How many cells have been written, for callers that pad to a fixed column.
    private(set) var cols = 0

    init() {}

    init(_ string: String, _ color: Color = Term.ink, weight: Font.Weight = .regular, bg: Color? = nil) {
        add(string, color, weight: weight, bg: bg)
    }

    mutating func add(_ string: String, _ color: Color = Term.ink, weight: Font.Weight = .regular, bg: Color? = nil) {
        guard !string.isEmpty else { return }
        var run = AttributedString(string)
        run.foregroundColor = color
        if weight != .regular { run.font = Term.font(weight) }
        if let bg { run.backgroundColor = bg }
        text += run
        cols += string.count
    }

    /// Writes spaces until the cursor sits on `column`.
    mutating func space(to column: Int) { add(String(repeating: " ", count: max(0, column - cols)), Term.mute) }

    mutating func space(_ count: Int = 1) { add(String(repeating: " ", count: count), Term.mute) }

    var isEmpty: Bool { cols == 0 }

    static func + (a: TermRow, b: TermRow) -> TermRow {
        var row = a
        row.text += b.text
        row.cols += b.cols
        return row
    }
}

/// Draws a `TermRow` in one 16px line box.
struct TermText: View {
    let row: TermRow
    var height: CGFloat = Term.line
    /// Panes clip by default (the design's `overflow: hidden`); the thought stream ellipsizes instead.
    var ellipsize = false

    init(_ row: TermRow, height: CGFloat = Term.line, ellipsize: Bool = false) {
        self.row = row
        self.height = height
        self.ellipsize = ellipsize
    }

    var body: some View {
        Text(row.text)
            .font(Term.font())
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: !ellipsize, vertical: false)
            .frame(height: height, alignment: .leading)
    }
}

// MARK: - Panes

/// A pane: 1px border, title sitting on the top-left of the border, optional right-aligned hint.
struct TermPane<Content: View>: View {
    let title: String
    var hint: TermRow?
    var titleColor: Color = Term.mute
    /// 20 at the top clears the title; the thought stream packs a little tighter.
    var insets = EdgeInsets(top: 20, leading: 10, bottom: 8, trailing: 10)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(insets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .overlay(alignment: .topLeading) {
                TermText(TermRow("─ \(title) ─", titleColor, weight: .semibold))
                    .padding(.horizontal, 4).padding(.leading, 8)
            }
            .overlay(alignment: .topTrailing) {
                if let hint { TermText(hint).padding(.horizontal, 4).padding(.trailing, 8) }
            }
            .overlay { Rectangle().strokeBorder(Term.border, lineWidth: 1) }
    }
}

/// As many of `rows` as fit the space offered, with `⋯ +N more` on the last line when they do not.
/// Keeps a pane's ideal height from growing past the grid the dashboard lays out.
struct TermList: View {
    let rows: [TermRow]
    var lineHeight: CGFloat = Term.line

    var body: some View {
        GeometryReader { proxy in
            let fit = max(1, Int(proxy.size.height / lineHeight))
            let shown = rows.count > fit ? fit - 1 : rows.count
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.prefix(shown).enumerated()), id: \.offset) { _, row in
                    TermText(row, height: lineHeight)
                }
                if rows.count > fit {
                    TermText(TermRow("⋯ +\(rows.count - shown) more", Term.mute), height: lineHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// A 1px horizontal rule inside a pane, drawn the same weight as the pane border.
struct TermRule: View {
    var body: some View { Rectangle().fill(Term.border).frame(height: 1) }
}

// MARK: - Shared helpers

private struct StaticRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering offscreen with ImageRenderer; animations render at their resting frame.
    var staticRendering: Bool {
        get { self[StaticRenderingKey.self] }
        set { self[StaticRenderingKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension ActivityKind {
    var word: String { self == .idle ? "waiting" : rawValue }
}

extension Int {
    /// 1234 → "1.2k", 5_400_000 → "5.40M".
    var compact: String {
        switch self {
        case 1_000_000...: String(format: "%.2fM", Double(self) / 1_000_000)
        case 1_000...: String(format: "%.1fk", Double(self) / 1_000)
        default: "\(self)"
        }
    }
}

extension Date {
    /// 24-hour wall clock, fixed width: "14:32:07".
    var clockText: String {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: self)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// "14:32" — the thought stream's time column.
    var shortClockText: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

extension TimeInterval {
    /// 2520 → "42m", 9060 → "2h31m".
    var elapsedText: String {
        let minutes = Int(self / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m"
    }

    /// "4.2s" for tool durations.
    var secondsText: String { self < 10 ? String(format: "%.1fs", self) : "\(Int(self.rounded()))s" }
}
