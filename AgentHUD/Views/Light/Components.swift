import HUDCore
import SwiftUI

// MARK: - Cards

/// White card, 6px radius, 1px warm-grey border. No shadow, no material.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    var fill: Color = Theme.card
    var border: Color = Theme.border
    /// The selected agent card doubles its border as an inset ring.
    var ring = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(border, lineWidth: 1))
            .overlay(ring ? RoundedRectangle(cornerRadius: Theme.Radius.card - 1).strokeBorder(border, lineWidth: 1).padding(1) : nil)
    }
}

/// 40px card header: title, muted suffix, trailing control, divider underneath.
struct CardHeader<Trailing: View>: View {
    let title: String
    var suffix: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(Theme.ui(15, .semibold)).foregroundStyle(Theme.ink)
            if let suffix { Text(suffix).font(Theme.ui(15)).foregroundStyle(Theme.mute) }
            Spacer(minLength: 8)
            trailing
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

// MARK: - Controls

/// Custom segmented control: ink fill on the selected segment, 1px border-strong outline, no system tint.
struct Segmented<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    /// The header control is 12/500 at 4×10; in-panel ones are 11/500 at 2×7.
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = option.value == selection
                Text(option.label)
                    .font(Theme.ui(compact ? 11 : 12, .medium))
                    .foregroundStyle(selected ? Theme.onInk : Theme.ink)
                    .padding(.horizontal, compact ? 7 : 10)
                    .padding(.vertical, compact ? 2 : 4)
                    .background(selected ? Theme.ink : .clear)
                    .overlay(alignment: .leading) {
                        if index > 0 { Rectangle().fill(Theme.borderStrong).frame(width: 1) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option.value }
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: compact ? Theme.Radius.badge : Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: compact ? Theme.Radius.badge : Theme.Radius.card)
            .strokeBorder(Theme.borderStrong, lineWidth: 1))
    }
}

/// 30px header button: white with a strong border, or filled ink.
struct ToolbarButton: View {
    let title: String
    var symbol: String?
    var filled = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
                Text(title).font(Theme.ui(13, .medium))
            }
            .foregroundStyle(filled ? Theme.onInk : Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(filled ? Theme.ink : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(filled ? Theme.ink : Theme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// `opus-5` — 11/500 in the model color, 1px border of the same color.
struct ModelBadge: View {
    let model: String?

    var body: some View {
        let color = Theme.modelColor(model)
        Text(model.map(CostEstimator.shortName) ?? "—")
            .font(Theme.ui(11, .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.badge).strokeBorder(color, lineWidth: 1))
            .lineLimit(1).fixedSize()
    }
}

/// 26×14 pill with an 8px ink knob.
struct BlurToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule().fill(isOn ? Theme.ink : Theme.track)
            .overlay(Capsule().strokeBorder(isOn ? Theme.ink : Theme.borderStrong, lineWidth: 1))
            .frame(width: 26, height: 14)
            .overlay(alignment: .leading) {
                Circle().fill(isOn ? Theme.onInk : Theme.ink).frame(width: 8, height: 8).offset(x: isOn ? 16 : 2)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
            .contentShape(Rectangle())
            .onTapGesture { isOn.toggle() }
    }
}

// MARK: - Small charts

/// Square-cornered progress bar: `track` behind, a semantic fill in front.
struct BarTrack: View {
    let fraction: Double
    let color: Color
    var width: CGFloat?
    var height: CGFloat = 6
    var trackColor: Color = Theme.divider
    var radius: CGFloat = Theme.Radius.bar

    var body: some View {
        GeometryReader { proxy in
            let full = width ?? proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius).fill(trackColor).frame(width: full)
                RoundedRectangle(cornerRadius: radius).fill(color)
                    .frame(width: max(0, full * max(0, min(1, fraction))))
            }
        }
        .frame(width: width, height: height)
    }
}

/// Heartbeat: the last 24 samples as a 1.5px polyline, flat while the agent waits.
struct Sparkline: View {
    let values: [Int]
    let color: Color
    var active = true

    var body: some View {
        Canvas { context, size in
            let samples = Array(values.suffix(24))
            guard samples.count > 1 else { return }
            let peak = CGFloat(max(samples.max() ?? 1, 1))
            let amplitude: CGFloat = active ? 0.8 : 0.06
            let step = size.width / CGFloat(samples.count - 1)
            var path = Path()
            for (index, value) in samples.enumerated() {
                let lift = CGFloat(value) / peak * (size.height - 3) * amplitude
                let point = CGPoint(x: CGFloat(index) * step, y: size.height - 1.5 - lift)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

/// 28×28 plan progress: a `divider` track with an arc in the model color, `3/7` in the middle.
struct ProgressRing: View {
    let done: Int
    let total: Int
    let color: Color
    var side: CGFloat = 28

    var body: some View {
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        ZStack {
            Circle().strokeBorder(Theme.divider, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
            Text("\(done)/\(total)").font(Theme.ui(8, .semibold)).foregroundStyle(Theme.ink)
        }
        .frame(width: side, height: side)
    }
}

// MARK: - Geometry

enum Geometry {
    /// Point on a circle; 0° is 12 o'clock, clockwise.
    static func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = (degrees - 90) * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    /// Arc from `start` to `end` degrees, 0° at 12 o'clock, clockwise.
    static func arc(_ center: CGPoint, _ radius: CGFloat, _ start: Double, _ end: Double) -> Path {
        Path { $0.addArc(center: center, radius: radius, startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false) }
    }

    /// Horizontal S-curve between two points, control points at the midpoint x.
    static func link(_ from: CGPoint, _ to: CGPoint) -> Path {
        let mid = (from.x + to.x) / 2
        return Path {
            $0.move(to: from)
            $0.addCurve(to: to, control1: CGPoint(x: mid, y: from.y), control2: CGPoint(x: mid, y: to.y))
        }
    }

    /// Point at `t` along a cubic Bézier, for walking particles down an edge.
    static func onCurve(_ from: CGPoint, _ to: CGPoint, _ t: Double) -> CGPoint {
        let mid = (from.x + to.x) / 2
        let c1 = CGPoint(x: mid, y: from.y), c2 = CGPoint(x: mid, y: to.y)
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * from.x + b * c1.x + c * c2.x + d * to.x,
                       y: a * from.y + b * c1.y + c * c2.y + d * to.y)
    }
}

extension GraphicsContext {
    func label(_ string: String, at point: CGPoint, size: CGFloat, weight: Font.Weight = .regular,
               color: Color, anchor: UnitPoint = .center) {
        draw(Text(string).font(Theme.ui(size, weight)).foregroundStyle(color), at: point, anchor: anchor)
    }

    func symbol(_ name: String, at point: CGPoint, size: CGFloat, color: Color) {
        draw(Text(Image(systemName: name)).font(.system(size: size, weight: .semibold)).foregroundStyle(color), at: point)
    }
}
