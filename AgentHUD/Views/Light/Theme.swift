import AppKit
import HUDCore
import SwiftUI

/// Design tokens for the light product-analytics restyle (design_handoff_agent_hud_light/README.md).
/// Warm off-white canvas, flat white cards with 1px warm-grey borders, dark-ink controls,
/// saturated-but-muted semantic colors that clear 4.5:1 on white. No gradients, no glow, no shadows
/// except the popover's hard shadow.
enum Theme {
    // MARK: Surfaces

    static let canvas = Color(hex: 0xF4F3EE)
    static let header = Color(hex: 0xFBFAF7)
    static let card = Color.white
    static let cardSelected = Color(hex: 0xFFF8EC)
    static let track = Color(hex: 0xF1EFE9)
    static let chipAmber = Color(hex: 0xFFF3DD)
    static let border = Color(hex: 0xD8D4CB)
    static let borderStrong = Color(hex: 0xC9C5BB)
    static let divider = Color(hex: 0xE7E4DC)

    // MARK: Text

    static let ink = Color(hex: 0x151618)
    static let mute = Color(hex: 0x6B7079)
    static let onInk = Color.white

    // MARK: Semantic activity

    static let thinking = Color(hex: 0x6D3BD9)
    static let reading = Color(hex: 0x1F5FD0)
    static let editing = Color(hex: 0xB8690A)
    static let running = Color(hex: 0x1E8A4C)
    static let error = Color(hex: 0xD2384A)
    static let waiting = Color(hex: 0x8B919B)
    static let subagent = Color(hex: 0x0F8B78)
    /// Middle ring of the loop radar, between amber and red.
    static let loopMid = Color(hex: 0xC4531F)
    /// The error node's ring alternates with this while a loop is live.
    static let errorPale = Color(hex: 0xF0A3AD)

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

    /// Model badge border + text, and the repo leaderboard bars.
    static func modelColor(_ model: String?) -> Color {
        let name = model ?? ""
        if name.contains("fable") || name.contains("mythos") { return ink }
        if name.contains("opus") { return reading }
        if name.contains("sonnet") { return editing }
        return mute
    }

    /// SF Symbols stand in for the prototype's Unicode activity glyphs.
    static func symbol(for activity: ActivityKind) -> String {
        switch activity {
        case .thinking: "brain"
        case .responding: "text.bubble"
        case .reading: "magnifyingglass"
        case .editing: "pencil"
        case .running: "play.fill"
        case .subagent: "circle.dotted"
        case .error: "xmark"
        case .waiting, .idle: "ellipsis"
        }
    }

    // MARK: Type

    /// IBM Plex Sans when it is installed, the system face otherwise — both are allowed by the spec.
    private static let plex: String? = ["IBM Plex Sans", "IBMPlexSans"].first { NSFont(name: $0, size: 13) != nil }
    private static let jetbrains: String? = ["JetBrains Mono", "JetBrainsMono-Regular"].first { NSFont(name: $0, size: 11) != nil }

    /// UI text. Every metric is tabular so numbers do not jitter as they tick.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let font: Font = plex.map { .custom($0, fixedSize: size).weight(weight) }
            ?? .system(size: size, weight: weight)
        return font.monospacedDigit()
    }

    /// Code, commands and the thought stream.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let font: Font = jetbrains.map { .custom($0, fixedSize: size).weight(weight) }
            ?? .system(size: size, weight: weight, design: .monospaced)
        return font.monospacedDigit()
    }

    // MARK: Radius, stroke

    enum Radius {
        static let window: CGFloat = 8
        /// Cards, buttons, segmented controls, popovers.
        static let card: CGFloat = 6
        static let badge: CGFloat = 4
        static let chip: CGFloat = 3
        static let bar: CGFloat = 1
        static let laneTrack: CGFloat = 2
    }
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
    /// "14:32:07".
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
    /// 2520 → "42m", 9060 → "2h 31m". Clamped: a clock skew between two log lines should not
    /// produce "-49m" on a card.
    var elapsedText: String {
        let minutes = max(0, Int(self / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    /// "4.2s" for tool durations.
    var secondsText: String { self < 10 ? String(format: "%.1fs", self) : "\(Int(self.rounded()))s" }
}
