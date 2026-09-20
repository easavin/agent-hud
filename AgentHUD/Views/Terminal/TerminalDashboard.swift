import HUDCore
import SwiftUI

enum HeroTab: String, CaseIterable {
    case flow, brain, loops, files

    /// The key that switches to this pane; shown in brackets inside the word.
    var key: Character {
        switch self {
        case .flow: "f"
        case .brain: "b"
        case .loops: "l"
        case .files: "s"
        }
    }

    /// `[f]low`, `file[s]` — the bracket marks the shortcut wherever it falls in the word.
    var hint: String {
        guard let index = rawValue.firstIndex(of: key) else { return rawValue }
        return rawValue.replacingCharacters(in: index...index, with: "[\(key)]")
    }
}

/// Frame 3a — the 1280×800 terminal dashboard. Laid out at its design size and scaled to the window.
struct DashboardView: View {
    static let designSize = CGSize(width: 1280, height: 800)
    /// Window padding 8×12, header 16, thoughts 100, gap 8 — what is left for the body grid.
    static let bodyHeight: CGFloat = 652
    static let statsWidth: CGFloat = 296
    /// 652 of body minus the agents table, the lanes and the two gaps.
    static let heroHeight: CGFloat = 368

    let monitor: AgentMonitor
    @State private var heroTab: HeroTab
    @State private var burnRange: BurnRange = .day
    @State private var laneHover: String?
    @AppStorage("blurThoughts") private var blurThoughts = false
    @FocusState private var focused: Bool

    init(monitor: AgentMonitor, initialTab: HeroTab = .flow) {
        self.monitor = monitor
        _heroTab = State(initialValue: initialTab)
    }

    /// Live sessions first, then the last few that ended — the table is the app's whole session list.
    private var rows: [AgentSnapshot] { monitor.agents + monitor.recent }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.designSize.width, proxy.size.height / Self.designSize.height)
            content
                .frame(width: Self.designSize.width, height: Self.designSize.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Term.bg)
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress { press in handle(press) }
    }

    private var content: some View {
        VStack(spacing: 8) {
            HeaderLine(monitor: monitor)
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    AgentsPane(rows: rows, selectedId: monitor.selected?.id, select: { monitor.selectedId = $0 })
                        .frame(height: 118)
                    HeroPane(agent: monitor.selected, tab: $heroTab)
                        .frame(height: Self.heroHeight)
                    LanesPane(agents: rows, hover: $laneHover).frame(height: 150)
                }
                .frame(maxWidth: .infinity)
                StatsPane(monitor: monitor, range: $burnRange)
                    .frame(width: Self.statsWidth, height: Self.bodyHeight)
            }
            .frame(height: Self.bodyHeight)
            ThoughtsPane(agents: rows, blur: $blurThoughts).frame(height: 100)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .background(Term.bg)
        .overlay { Rectangle().strokeBorder(Term.borderOuter, lineWidth: 1) }
    }

    // MARK: Keyboard

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow: move(-1)
        case .downArrow: move(1)
        default:
            guard let character = press.characters.first else { return .ignored }
            if let tab = HeroTab.allCases.first(where: { $0.key == character }) {
                heroTab = tab
            } else if character == "p" {
                blurThoughts.toggle()
            } else if let range = BurnRange.allCases.first(where: { $0.rawValue.first == character }) {
                burnRange = range
            } else {
                return .ignored
            }
        }
        return .handled
    }

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == monitor.selected?.id } ?? 0
        monitor.selectedId = rows[max(0, min(rows.count - 1, current + delta))].id
    }
}

/// `agent-hud v0.4 ── 5 sessions ── 46.5k tok/min ── … ── loops 7 errors 12` · `14:32:07 ● live`.
struct HeaderLine: View {
    let monitor: AgentMonitor
    @Environment(\.staticRendering) private var staticRendering

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"

    var body: some View {
        HStack(spacing: 0) {
            TermText(left)
                // The window's traffic lights own the first 76px of the line.
                .padding(.leading, 76)
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                TermText(right(now: timeline.date))
            }
        }
        .frame(height: Term.line)
    }

    private var left: TermRow {
        let loops = monitor.agents.reduce(0) { $0 + $1.loops.count }
        var row = TermRow("agent-hud", Term.ink, weight: .bold)
        row.add(" v\(Self.version) ", Term.mute)
        func field(_ value: String, _ unit: String, _ color: Color = Term.ink) {
            row.add("── ", Term.mute)
            row.add(value, color)
            row.add(" \(unit) ", Term.mute)
        }
        field("\(monitor.agents.count)", "sessions")
        field(monitor.tokensPerMinute.compact, "tok/min")
        field(monitor.stats.tokensToday.compact, "today")
        field(String(format: "$%.2f", monitor.stats.costToday), "")
        row.add("── loops ", Term.mute)
        row.add("\(loops)", loops > 0 ? Term.editing : Term.mute)
        row.add(" errors ", Term.mute)
        row.add("\(monitor.stats.errorsToday)", monitor.stats.errorsToday > 0 ? Term.error : Term.mute)
        return row
    }

    private func right(now: Date) -> TermRow {
        var row = TermRow(now.clockText, Term.mute)
        row.add("  ")
        // The live dot steps between green and the border color once a second.
        let lit = staticRendering || Int(now.timeIntervalSinceReferenceDate) % 2 == 0
        let live = monitor.activeCount > 0
        row.add("●", live ? (lit ? Term.running : Term.border) : Term.waiting)
        row.add(live ? " live" : " idle", Term.mute)
        return row
    }
}
