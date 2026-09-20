import HUDCore
import SwiftUI

enum HeroTab: String, CaseIterable {
    case flow, brain, loops, files

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// Keyboard shortcut, kept from the previous build.
    var key: Character { self == .files ? "s" : rawValue.first! }
}

/// Frame 3b — the 1280×800 light product-analytics dashboard, laid out at design size and scaled to the window.
struct DashboardView: View {
    static let designSize = CGSize(width: 1280, height: 800)
    static let railWidth: CGFloat = 264
    static let statsWidth: CGFloat = 280
    static let bodyHeight: CGFloat = 592

    let monitor: AgentMonitor
    @State private var heroTab: HeroTab
    @State private var burnRange: BurnRange = .day
    @State private var laneRange: LaneRange = .hour
    @State private var activeOnly = false
    @AppStorage("blurThoughts") private var blurThoughts = false
    @FocusState private var focused: Bool

    init(monitor: AgentMonitor, initialTab: HeroTab = .flow) {
        self.monitor = monitor
        _heroTab = State(initialValue: initialTab)
    }

    /// Live sessions first, then the ones that ended recently.
    private var rows: [AgentSnapshot] {
        let all = monitor.agents + monitor.recent
        return activeOnly ? all.filter { $0.activity.isActive } : all
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.designSize.width, proxy.size.height / Self.designSize.height)
            content
                .frame(width: Self.designSize.width, height: Self.designSize.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.canvas)
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress { press in handle(press) }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            metrics
            body(width: Self.designSize.width)
            ThoughtStream(agents: rows, blur: $blurThoughts)
                .frame(height: 96)
                .padding(.horizontal, 16).padding(.bottom, 10)
        }
        .background(Theme.canvas)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.window).strokeBorder(Theme.border, lineWidth: 1))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            // The window's traffic lights own the first 76px of the bar.
            RoundedRectangle(cornerRadius: 5).fill(Theme.ink).frame(width: 20, height: 20)
                .overlay(Text("A").font(Theme.ui(11, .bold)).foregroundStyle(Theme.onInk))
                .padding(.leading, 76)
            Text("Agents").font(Theme.ui(17, .semibold)).foregroundStyle(Theme.ink)
            Text("\(monitor.agents.count) sessions · \(monitor.activeCount) active")
                .font(Theme.ui(12)).foregroundStyle(Theme.mute)
            Spacer(minLength: 12)
            ToolbarButton(title: laneRange.title.capitalizedFirst, symbol: "chevron.down") { cycleRange() }
            ToolbarButton(title: activeOnly ? "Active only" : "+ Filter",
                          symbol: activeOnly ? "xmark" : nil) { activeOnly.toggle() }
            RefreshButton(monitor: monitor)
        }
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(Theme.header)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func cycleRange() {
        let all = LaneRange.allCases
        laneRange = all[(all.firstIndex(of: laneRange).map { $0 + 1 } ?? 0) % all.count]
    }

    // MARK: Metrics strip

    private var metrics: some View {
        HStack(spacing: 24) {
            metric(monitor.tokensPerMinute.compact, "tok/min")
            metric(monitor.stats.tokensToday.compact, "today")
            metric(String(format: "$%.2f", monitor.stats.costToday), "est. cost")
            metric("\(monitor.agents.reduce(0) { $0 + $1.loops.count })", "loops", color: Theme.editing)
            metric("\(monitor.stats.errorsToday)", "errors", color: Theme.error)
            Spacer(minLength: 8)
            Text(monitor.lastRefreshedText).font(Theme.ui(13)).foregroundStyle(Theme.mute)
        }
        .padding(.horizontal, 16).padding(.top, 10)
        .frame(height: 34, alignment: .top)
    }

    private func metric(_ value: String, _ unit: String, color: Color = Theme.ink) -> some View {
        HStack(spacing: 5) {
            Text(value).font(Theme.ui(13, .semibold)).foregroundStyle(color).contentTransition(.numericText())
            Text(unit).font(Theme.ui(13)).foregroundStyle(Theme.mute)
        }
    }

    // MARK: Body

    private func body(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                ForEach(rows.prefix(5)) { agent in
                    AgentCard(agent: agent, selected: agent.id == monitor.selected?.id)
                        .contentShape(Rectangle())
                        .onTapGesture { monitor.selectedId = agent.id }
                }
                if rows.isEmpty {
                    Card {
                        Text("No sessions — start one with `claude`")
                            .font(Theme.ui(12)).foregroundStyle(Theme.mute)
                    }
                    .frame(height: 112)
                }
                Spacer(minLength: 0)
            }
            .frame(width: Self.railWidth)

            VStack(spacing: 12) {
                heroCard.frame(height: 356)
                LanesPanel(agents: rows, range: $laneRange).frame(height: 224)
            }
            .frame(maxWidth: .infinity)

            StatsRail(monitor: monitor, burnRange: $burnRange).frame(width: Self.statsWidth)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(height: Self.bodyHeight, alignment: .top)
    }

    private var heroCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                CardHeader(title: heroTitle, suffix: monitor.selected.map { "turn \($0.turnIndex)" }) {
                    Segmented(options: HeroTab.allCases.map { ($0.title, $0) }, selection: $heroTab)
                }
                Group {
                    if let agent = monitor.selected {
                        switch heroTab {
                        case .flow: FlowGraphView(agent: agent).id(agent.id)
                        case .brain: BrainView(agent: agent)
                        case .loops: LoopsView(agent: agent)
                        case .files: FilesView(agent: agent)
                        }
                    } else {
                        Text("No session selected").font(Theme.ui(13)).foregroundStyle(Theme.mute)
                            .frame(width: FlowLayout.canvas.width, height: FlowLayout.canvas.height)
                    }
                }
                // The 688pt canvas is drawn at 96%, exactly as the prototype scales it into the card.
                .scaleEffect(0.96, anchor: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 8)
                .clipped()
            }
        }
    }

    private var heroTitle: String {
        guard let agent = monitor.selected else { return "Thinking flow" }
        let name = heroTab == .flow ? "Thinking flow" : heroTab.title
        return "\(name) · \(agent.repo)" + (agent.isEnded ? " · ended" : "")
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

/// `↻ Refresh` — spins 360° once per refresh.
struct RefreshButton: View {
    let monitor: AgentMonitor
    @State private var turns = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            monitor.refreshNow()
            if !reduceMotion { withAnimation(.linear(duration: 0.6)) { turns += 360 } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                    .rotationEffect(.degrees(turns))
                Text("Refresh").font(Theme.ui(13, .medium))
            }
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.ink))
        }
        .buttonStyle(.plain)
    }
}

/// Bottom card: the newest lines across every session, monospace, newest last.
struct ThoughtStream: View {
    let agents: [AgentSnapshot]
    @Binding var blur: Bool
    static let rows = 4

    private struct Line: Identifiable {
        let id: String
        let agent: AgentSnapshot
        let item: TickerItem
    }

    private var lines: [Line] {
        agents.flatMap { agent in agent.ticker.suffix(Self.rows).map { Line(id: agent.id + $0.id, agent: agent, item: $0) } }
            .sorted { $0.item.date > $1.item.date }
            .prefix(Self.rows)
            .reversed()
    }

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Thought stream").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("Blur thoughts").font(Theme.ui(11)).foregroundStyle(Theme.mute)
                    BlurToggle(isOn: $blur)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in row(line) }
                    if lines.isEmpty {
                        Text("Nothing said yet").font(Theme.mono(11)).foregroundStyle(Theme.mute)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: lines.last?.id)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
        }
    }

    private func row(_ line: Line) -> some View {
        let color = Theme.color(for: line.item.kind)
        return HStack(spacing: 10) {
            Text(line.item.date.shortClockText).foregroundStyle(Theme.mute).frame(width: 60, alignment: .leading)
            Text(line.agent.repo).fontWeight(.semibold).foregroundStyle(Theme.modelColor(line.agent.model))
                .lineLimit(1).truncationMode(.middle).frame(width: 88, alignment: .leading)
            HStack(spacing: 4) {
                Image(systemName: Theme.symbol(for: line.item.kind)).font(.system(size: 9, weight: .semibold))
                Text(line.item.kind.word)
            }
            .foregroundStyle(color).frame(width: 80, alignment: .leading)
            Text(line.item.text).foregroundStyle(Theme.ink).lineLimit(1)
                .blur(radius: blur ? 4 : 0).opacity(blur ? 0.7 : 1)
            Spacer(minLength: 0)
        }
        .font(Theme.mono(11))
        .frame(height: 13)
        .transition(.opacity)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
