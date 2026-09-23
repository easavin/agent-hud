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
    /// The window opens at the handoff's size; every pane is resizable from there.
    static let designSize = CGSize(width: 1280, height: 800)

    let monitor: AgentMonitor
    @Environment(\.staticRendering) private var staticRendering
    @State private var heroTab: HeroTab
    @State private var burnRange: BurnRange = .day
    @State private var laneRange: LaneRange = .hour
    @State private var activeOnly = false
    @AppStorage("blurThoughts") private var blurThoughts = false
    // Pane sizes are draggable and persist. The defaults are the handoff's grid at 1280×800.
    // They are @State, not @AppStorage: writing UserDefaults on every drag frame makes the whole
    // dashboard re-render through the defaults system and the drag stutters.
    @State private var railWidth = DashboardView.stored("railWidth", 264)
    @State private var statsWidth = DashboardView.stored("statsWidth", 280)
    @State private var heroHeight = DashboardView.stored("heroHeight", 356)
    @State private var streamHeight = DashboardView.stored("streamHeight", 96)

    static func stored(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }

    private func persist(_ key: String, _ value: Double) { UserDefaults.standard.set(value, forKey: key) }
    @FocusState private var focused: Bool
    /// First row shown in the session rail, and how many rows fit (kept for the key and wheel handlers).
    @State private var railStart = 0
    @State private var railVisible = 1
    @State private var railHovered = false
    @State private var wheelMonitor: Any?
    @State private var wheelAccumulator: CGFloat = 0

    init(monitor: AgentMonitor, initialTab: HeroTab = .flow) {
        self.monitor = monitor
        _heroTab = State(initialValue: initialTab)
    }

    /// Live sessions first, then the ones that ended recently. Built once per render, not per read.
    private var rows: [AgentSnapshot] {
        let all = monitor.agents + monitor.recent
        return activeOnly ? all.filter { $0.activity.isActive } : all
    }

    var body: some View {
        GeometryReader { proxy in content(in: proxy.size) }
            .background(Theme.canvas)
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true; installWheelMonitor() }
        .onDisappear {
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
            wheelMonitor = nil
        }
        .onKeyPress { press in handle(press) }
    }

    private func content(in size: CGSize) -> some View {
        // What is left for the body once the chrome, the stream and its splitter are taken out.
        let chrome = 52 + 34 + Splitter.thickness + 10.0
        let stream = min(max(streamHeight, 60), max(60, size.height - chrome - 220))
        return VStack(spacing: 0) {
            header
            metrics
            body(in: CGSize(width: size.width, height: max(220, size.height - chrome - stream)))
            Splitter(axis: .horizontal, value: $streamHeight,
                     range: 60...max(60, size.height - chrome - 220), sign: -1,
                     onCommit: { persist("streamHeight", streamHeight) })
                .padding(.horizontal, 16)
            ThoughtStream(agents: rows, blur: $blurThoughts)
                .frame(height: stream)
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
        // ImageRenderer paints an AppKit view as a yellow "unsupported" slab, so snapshots go without.
        .background { if !staticRendering { WindowDragArea() } }
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

    private func body(in size: CGSize) -> some View {
        let rows = rows
        // Each column keeps at least enough width to stay legible; the centre takes the remainder.
        let inner = size.width - 32 - Splitter.thickness * 2
        let railSide = min(max(railWidth, 190), max(190, inner - 360 - 250))
        let stats = min(max(statsWidth, 250), max(250, inner - railSide - 360))
        let bodyHeight = size.height - 16
        let hero = min(max(heroHeight, 200), max(200, bodyHeight - Splitter.thickness - 150))
        return HStack(alignment: .top, spacing: 0) {
            rail(rows, height: bodyHeight).frame(width: railSide)

            Splitter(axis: .vertical, value: $railWidth, range: 190...max(190, inner - 360 - 250),
                     onCommit: { persist("railWidth", railWidth) })

            VStack(spacing: 0) {
                heroCard.frame(height: hero)
                Splitter(axis: .horizontal, value: $heroHeight,
                         range: 200...max(200, bodyHeight - Splitter.thickness - 150),
                         onCommit: { persist("heroHeight", heroHeight) })
                LanesPanel(agents: rows, range: $laneRange).frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)

            Splitter(axis: .vertical, value: $statsWidth,
                     range: 250...max(250, inner - railSide - 360), sign: -1,
                     onCommit: { persist("statsWidth", statsWidth) })

            StatsRail(monitor: monitor, burnRange: $burnRange, width: stats)
                .frame(width: stats, height: bodyHeight, alignment: .top)
                .clipped()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(height: size.height, alignment: .top)
        .clipped()
    }

    // MARK: Session rail

    /// How many cards fit in the rail; the footer line lives in the gap under the last one.
    private static func railCapacity(_ height: CGFloat) -> Int {
        max(1, Int((height + 8) / (AgentCard.height + 8)))
    }

    /// A window of cards rather than a scroll view: ImageRenderer cannot draw a ScrollView, so
    /// snapshots would come back blank. The footer, the wheel and ↑/↓ move the window instead.
    private func rail(_ rows: [AgentSnapshot], height: CGFloat) -> some View {
        let visible = Self.railCapacity(height)
        let start = max(0, min(railStart, rows.count - visible))
        let below = max(0, rows.count - start - visible)
        return VStack(spacing: 8) {
            ForEach(Array(rows.dropFirst(start).prefix(visible))) { agent in
                AgentCard(agent: agent, selected: agent.id == monitor.selected?.id)
                    .contentShape(Rectangle())
                    .onTapGesture { monitor.selectedId = agent.id }
            }
            if rows.isEmpty {
                Card {
                    Text("No sessions — start one with `claude`")
                        .font(Theme.ui(12)).foregroundStyle(Theme.mute)
                }
                .frame(height: AgentCard.height)
            }
            if rows.count > visible {
                HStack(spacing: 4) {
                    Text([start > 0 ? "\(start) above" : nil, below > 0 ? "+\(below) more" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.ui(11)).foregroundStyle(Theme.mute)
                    Spacer(minLength: 4)
                    RailPageButton(symbol: "chevron.up", enabled: start > 0) { scrollRail(by: -visible, rows.count) }
                    RailPageButton(symbol: "chevron.down", enabled: below > 0) { scrollRail(by: visible, rows.count) }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase { railHovered = true } else { railHovered = false }
        }
        .onChange(of: height, initial: true) { railVisible = visible }
        .onChange(of: monitor.agents.map(\.id)) { old, new in
            // A session that just started should be on screen, not hidden above or below the window.
            guard let fresh = new.last(where: { !old.contains($0) }),
                  let index = self.rows.firstIndex(where: { $0.id == fresh }) else { return }
            revealInRail(index)
        }
    }

    private func scrollRail(by delta: Int, _ count: Int) {
        railStart = max(0, min(max(0, count - railVisible), railStart + delta))
    }

    /// Moves the window the least needed to show `index`.
    private func revealInRail(_ index: Int) {
        if index < railStart { railStart = index }
        else if index >= railStart + railVisible { railStart = index - railVisible + 1 }
    }

    /// The rail has no scroll view to receive the wheel, so the window listens for it while the pointer is over it.
    private func installWheelMonitor() {
        guard wheelMonitor == nil, !staticRendering else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard railHovered else { return event }
            wheelAccumulator += event.scrollingDeltaY
            // One card per notch on a mouse; trackpads send many small deltas, so step once per card height.
            let step = event.hasPreciseScrollingDeltas ? AgentCard.height / 2 : 1
            while abs(wheelAccumulator) >= step {
                scrollRail(by: wheelAccumulator > 0 ? -1 : 1, rows.count)
                wheelAccumulator -= wheelAccumulator > 0 ? step : -step
            }
            if event.phase == .ended || event.momentumPhase == .ended { wheelAccumulator = 0 }
            return nil
        }
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
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 4)
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
        let next = max(0, min(rows.count - 1, current + delta))
        monitor.selectedId = rows[next].id
        revealInRail(next)
    }
}

/// The rail footer's page up / page down chevrons.
private struct RailPageButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? Theme.ink : Theme.mute.opacity(0.5))
                .frame(width: 22, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
    static let rowHeight: CGFloat = 15

    private struct Line: Identifiable {
        let id: String
        let agent: AgentSnapshot
        let item: TickerItem
    }

    /// As many of the newest lines as the pane has room for, oldest first.
    private func lines(_ count: Int) -> [Line] {
        agents.flatMap { agent in agent.ticker.suffix(count).map { Line(id: agent.id + $0.id, agent: agent, item: $0) } }
            .sorted { $0.item.date > $1.item.date }
            .prefix(count)
            .reversed()
    }

    var body: some View {
        Card(padding: 0) {
            GeometryReader { proxy in
                // Header and padding first; the rest is 15pt lines.
                let count = max(1, Int((proxy.size.height - 32) / Self.rowHeight))
                let lines = lines(count)
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
