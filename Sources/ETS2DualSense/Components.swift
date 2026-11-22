import DualSenseKit
import EffectKit
import SwiftUI

struct Card<Content: View>: View {
    let title: String
    var icon: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(title).font(.headline) } icon: { if let icon { Image(systemName: icon).foregroundStyle(.secondary) } }
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }
}

struct StatusLine: View {
    let ok: Bool
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal level bar, 0...1.
struct Meter: View {
    let label: String
    let value: Double
    var tint: Color = .accentColor
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(detail ?? "\(Int((value * 100).rounded()))%").monospacedDigit()
            }
            .font(.caption)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint).frame(width: max(0, min(1, value.isFinite ? value : 0)) * geo.size.width)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(detail ?? "\(Int((value * 100).rounded())) percent")
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var format: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    var body: some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: $value, in: range) { Text(title) }.labelsHidden()
            Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Five draggable points; x is the driving signal, y the resulting force.
struct CurveEditor: View {
    @Binding var curve: Curve
    var marker: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let n = curve.points.count
            let point: (Int) -> CGPoint = { i in CGPoint(x: w * Double(i) / Double(n - 1), y: h * (1 - curve.points[i])) }
            ZStack {
                Path { p in
                    for i in 1..<4 {
                        p.move(to: CGPoint(x: w * Double(i) / 4, y: 0)); p.addLine(to: CGPoint(x: w * Double(i) / 4, y: h))
                        p.move(to: CGPoint(x: 0, y: h * Double(i) / 4)); p.addLine(to: CGPoint(x: w, y: h * Double(i) / 4))
                    }
                }.stroke(.quaternary, lineWidth: 1)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: point(0))
                    for i in 1..<n { p.addLine(to: point(i)) }
                    p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath()
                }.fill(Color.accentColor.opacity(0.12))
                Path { p in
                    p.move(to: point(0))
                    for i in 1..<n { p.addLine(to: point(i)) }
                }.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                if let marker {
                    let x = max(0, min(1, marker))
                    Path { p in p.move(to: CGPoint(x: w * x, y: 0)); p.addLine(to: CGPoint(x: w * x, y: h)) }
                        .stroke(.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Circle().fill(.orange).frame(width: 8, height: 8).position(x: w * x, y: h * (1 - curve.value(at: x)))
                }
                ForEach(0..<n, id: \.self) { i in
                    Circle().fill(.background).overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                        .frame(width: 14, height: 14)
                        .contentShape(Circle().inset(by: -8))
                        .position(point(i))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                            curve.points[i] = max(0, min(1, 1 - g.location.y / h))
                        })
                        .accessibilityElement()
                        .accessibilityLabel("Curve point \(i + 1) of \(n)")
                        .accessibilityValue("\(Int(curve.points[i] * 100)) percent")
                        .accessibilityAdjustableAction { direction in
                            let step = direction == .increment ? 0.05 : -0.05
                            curve.points[i] = max(0, min(1, curve.points[i] + step))
                        }
                }
            }
        }
        .frame(height: 130)
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator.opacity(0.5)))
    }
}

struct Tag: View {
    let text: String
    var tint: Color = .secondary
    var body: some View {
        Text(text).font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

extension RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

func colorBinding(_ rgb: Binding<RGB>) -> Binding<Color> {
    Binding(get: { rgb.wrappedValue.color }, set: { new in
        if let c = NSColor(new).usingColorSpace(.sRGB) {
            rgb.wrappedValue = RGB(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        }
    })
}

extension OutputState {
    var lightbarColor: Color { Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
}

extension TriggerEffect {
    /// Short human description of what the trigger is doing.
    var summary: String {
        switch mode {
        case 0x05, 0x00: return "Off"
        case 0x01: return "Resistance \(Int(Double(params[1]) / 255 * 100))%"
        case 0x02: return "Section resistance"
        case 0x21: return "Zoned resistance"
        case 0x25: return "Weapon"
        case 0x26: return "Vibration \(params[8]) Hz"
        default: return String(format: "Mode 0x%02X", mode)
        }
    }
    /// 0...1 strength for meters.
    var level: Double {
        switch mode {
        case 0x01: return Double(params[1]) / 255
        case 0x26: return min(1, Double(params[8]) / 127)
        case 0x05, 0x00: return 0
        default: return 1
        }
    }
}

struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(20)
                .frame(maxWidth: 1100, alignment: .topLeading)
                .frame(maxWidth: .infinity)
        }
    }
}
