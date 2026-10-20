import SwiftUI

/// The coach's animated character: Nova, a little robot whose antenna pulses and whose eyes scan
/// while it thinks; Ace, a flame that flickers and bounces; Kai, a breathing orb with ripples.
/// Drawn in a Canvas from the time, so there are no image assets. Still with Reduce Motion, or
/// when `animated` is false (the small avatars in a long conversation).
struct CoachCharacter: View {
    let persona: CoachPersona
    var size: CGFloat = 44
    var thinking = false
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = !animated || reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            // A fixed moment when still, with the eyes open.
            let t = still ? 0.5 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, canvas in
                let w = min(canvas.width, canvas.height)
                switch persona {
                case .nova: Self.drawNova(&ctx, w: w, t: t, thinking: thinking)
                case .ace: Self.drawAce(&ctx, w: w, t: t, thinking: thinking)
                case .kai: Self.drawKai(&ctx, w: w, t: t, thinking: thinking)
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: persona.color.opacity(0.35), radius: size * 0.12)
        .accessibilityElement()
        .accessibilityLabel("\(persona.name), your coach")
    }

    /// 1 with the eyes open; a quick blink every few seconds.
    nonisolated static func blink(_ t: Double, every period: Double = 4.2) -> CGFloat {
        let p = t.truncatingRemainder(dividingBy: period)
        guard p < 0.16 else { return 1 }
        return max(0.1, CGFloat(abs(p - 0.08) / 0.08))
    }

    nonisolated private static func wave(_ t: Double, _ speed: Double) -> CGFloat {
        CGFloat(sin(t * speed))
    }

    // MARK: Nova

    nonisolated private static func drawNova(_ ctx: inout GraphicsContext, w: CGFloat, t: Double, thinking: Bool) {
        let bob = wave(t, thinking ? 4 : 2) * w * 0.022
        let metal = Color(red: 0.62, green: 0.66, blue: 1.0)
        let light = Color(red: 0.55, green: 0.95, blue: 1.0)

        // Antenna, its light pulsing (faster while thinking).
        var stem = Path()
        stem.move(to: CGPoint(x: w * 0.5, y: w * 0.22 + bob))
        stem.addLine(to: CGPoint(x: w * 0.5, y: w * 0.09 + bob))
        ctx.stroke(stem, with: .color(metal), style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round))
        let glow = 0.55 + 0.45 * Double(wave(t, thinking ? 9 : 3))
        let bulb = CGRect(x: w * 0.44, y: w * 0.03 + bob, width: w * 0.12, height: w * 0.12)
        ctx.fill(Path(ellipseIn: bulb.insetBy(dx: -w * 0.03, dy: -w * 0.03)), with: .color(light.opacity(glow * 0.3)))
        ctx.fill(Path(ellipseIn: bulb), with: .color(light.opacity(0.4 + 0.6 * glow)))

        // Ears, head and face screen.
        let head = CGRect(x: w * 0.13, y: w * 0.22 + bob, width: w * 0.74, height: w * 0.66)
        for x in [head.minX - w * 0.04, head.maxX - w * 0.03] {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: head.midY - w * 0.08, width: w * 0.07, height: w * 0.16), cornerRadius: w * 0.03), with: .color(metal))
        }
        ctx.fill(Path(roundedRect: head, cornerRadius: w * 0.22, style: .continuous),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.45, green: 0.38, blue: 0.95), Color(red: 0.28, green: 0.56, blue: 1.0)]),
                                       startPoint: CGPoint(x: head.minX, y: head.minY), endPoint: CGPoint(x: head.maxX, y: head.maxY)))
        let screen = head.insetBy(dx: w * 0.085, dy: w * 0.1)
        ctx.fill(Path(roundedRect: screen, cornerRadius: w * 0.14, style: .continuous), with: .color(Color(red: 0.06, green: 0.07, blue: 0.2).opacity(0.9)))
        // A highlight on the glass.
        var glint = Path()
        glint.addArc(center: CGPoint(x: screen.minX + w * 0.12, y: screen.minY + w * 0.11), radius: w * 0.06,
                     startAngle: .degrees(190), endAngle: .degrees(260), clockwise: false)
        ctx.stroke(glint, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: w * 0.02, lineCap: .round))

        // Eyes: blink; while thinking they look from side to side.
        let open = blink(t)
        let look = thinking ? wave(t, 3.2) * w * 0.06 : 0
        for x in [CGFloat(0.37), 0.63] {
            let height = max(w * 0.015, w * 0.15 * open)
            let eye = CGRect(x: w * x - w * 0.055 + look, y: screen.midY - w * 0.035 - height / 2, width: w * 0.11, height: height)
            ctx.fill(Path(roundedRect: eye, cornerRadius: w * 0.04), with: .color(light))
        }
        // Mouth: a small smile, a flat line while thinking.
        var mouth = Path()
        let y = screen.midY + w * 0.1
        if thinking {
            mouth.move(to: CGPoint(x: w * 0.44, y: y))
            mouth.addLine(to: CGPoint(x: w * 0.56, y: y))
        } else {
            mouth.move(to: CGPoint(x: w * 0.42, y: y - w * 0.01))
            mouth.addQuadCurve(to: CGPoint(x: w * 0.58, y: y - w * 0.01), control: CGPoint(x: w * 0.5, y: y + w * 0.055))
        }
        ctx.stroke(mouth, with: .color(light), style: StrokeStyle(lineWidth: w * 0.03, lineCap: .round))
    }

    // MARK: Ace

    nonisolated private static func drawAce(_ ctx: inout GraphicsContext, w: CGFloat, t: Double, thinking: Bool) {
        // Bounces while thinking; otherwise bobs a little. The tip sways like a flame.
        let hop = thinking ? -abs(wave(t, 5)) * w * 0.07 : wave(t, 2.4) * w * 0.015
        let sway = wave(t, 6.5) * w * 0.05
        let flicker = 1 + wave(t, 11) * 0.015

        func flame(scale s: CGFloat, top: CGFloat) -> Path {
            let cx = w * 0.5, base = w * 0.93 + hop
            let half = w * 0.38 * s * flicker
            let tip = CGPoint(x: cx + sway * s, y: top + hop)
            var p = Path()
            p.move(to: tip)
            p.addCurve(to: CGPoint(x: cx + half, y: w * 0.62 + hop),
                       control1: CGPoint(x: cx + sway * 0.5 * s + half * 0.3, y: top + w * 0.18 + hop),
                       control2: CGPoint(x: cx + half * 1.05, y: w * 0.4 + hop))
            p.addCurve(to: CGPoint(x: cx, y: base),
                       control1: CGPoint(x: cx + half, y: w * 0.82 + hop), control2: CGPoint(x: cx + half * 0.55, y: base))
            p.addCurve(to: CGPoint(x: cx - half, y: w * 0.62 + hop),
                       control1: CGPoint(x: cx - half * 0.55, y: base), control2: CGPoint(x: cx - half, y: w * 0.82 + hop))
            p.addCurve(to: tip,
                       control1: CGPoint(x: cx - half * 1.05, y: w * 0.4 + hop),
                       control2: CGPoint(x: cx + sway * 0.5 * s - half * 0.3, y: top + w * 0.18 + hop))
            p.closeSubpath()
            return p
        }

        ctx.fill(flame(scale: 1, top: w * 0.03),
                 with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.82, blue: 0.32), Color(red: 1.0, green: 0.48, blue: 0.2), Color(red: 0.94, green: 0.24, blue: 0.36)]),
                                       startPoint: CGPoint(x: w * 0.5, y: 0), endPoint: CGPoint(x: w * 0.5, y: w)))
        ctx.fill(flame(scale: 0.55, top: w * 0.36), with: .color(Color(red: 1.0, green: 0.86, blue: 0.45).opacity(0.55)))

        // Eyes with pupils, and brows slanting in: determined.
        let open = blink(t + 1.3, every: 3.6)
        let dark = Color(red: 0.22, green: 0.06, blue: 0.1)
        for x in [CGFloat(0.39), 0.61] {
            let r = w * 0.075
            let c = CGPoint(x: w * x, y: w * 0.6 + hop)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * open, width: r * 2, height: r * 2 * open)), with: .color(.white))
            let pr = r * 0.48
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - pr + w * 0.012, y: c.y - pr * open, width: pr * 2, height: pr * 2 * open)), with: .color(dark))
        }
        for (outer, inner) in [(CGFloat(0.3), CGFloat(0.45)), (0.7, 0.55)] {
            var brow = Path()
            brow.move(to: CGPoint(x: w * outer, y: w * 0.47 + hop))
            brow.addLine(to: CGPoint(x: w * inner, y: w * 0.51 + hop))
            ctx.stroke(brow, with: .color(dark), style: StrokeStyle(lineWidth: w * 0.04, lineCap: .round))
        }
        // A confident grin; an "o" while thinking.
        if thinking {
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.46, y: w * 0.71 + hop, width: w * 0.08, height: w * 0.08)), with: .color(dark))
        } else {
            var grin = Path()
            grin.move(to: CGPoint(x: w * 0.41, y: w * 0.72 + hop))
            grin.addQuadCurve(to: CGPoint(x: w * 0.6, y: w * 0.7 + hop), control: CGPoint(x: w * 0.52, y: w * 0.81 + hop))
            ctx.stroke(grin, with: .color(dark), style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round))
        }
    }

    // MARK: Kai

    nonisolated private static func drawKai(_ ctx: inout GraphicsContext, w: CGFloat, t: Double, thinking: Bool) {
        let speed = thinking ? 2.4 : 1.0
        let teal = Color(red: 0.25, green: 0.9, blue: 0.78)

        // Two ripples moving out from the orb.
        for k in 0..<2 {
            let phase = (t * 0.33 * speed + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
            let r = w * (0.35 + 0.14 * CGFloat(phase))
            ctx.stroke(Path(ellipseIn: CGRect(x: w / 2 - r, y: w * 0.52 - r, width: r * 2, height: r * 2)),
                       with: .color(teal.opacity(0.5 * (1 - phase))), lineWidth: w * 0.018)
        }
        // The orb breathes.
        let r = w * 0.33 * (1 + 0.035 * wave(t, 1.3 * speed))
        let center = CGPoint(x: w * 0.5, y: w * 0.52)
        let orb = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: orb),
                 with: .radialGradient(Gradient(colors: [Color(red: 0.62, green: 1.0, blue: 0.88), Color(red: 0.12, green: 0.72, blue: 0.6)]),
                                       center: CGPoint(x: center.x - r * 0.3, y: center.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))

        // A leaf on top, swaying.
        let stem = CGPoint(x: center.x + r * 0.15, y: orb.minY + w * 0.01)
        let tip = CGPoint(x: stem.x + w * 0.13 + wave(t, 1.6) * w * 0.02, y: stem.y - w * 0.15)
        var leaf = Path()
        leaf.move(to: stem)
        leaf.addQuadCurve(to: tip, control: CGPoint(x: stem.x - w * 0.02, y: tip.y + w * 0.02))
        leaf.addQuadCurve(to: stem, control: CGPoint(x: tip.x + w * 0.02, y: stem.y - w * 0.03))
        ctx.fill(leaf, with: .color(Color(red: 0.42, green: 0.85, blue: 0.4)))

        // Closed, content eyes and a small smile.
        let dark = Color(red: 0.04, green: 0.3, blue: 0.27)
        for x in [CGFloat(0.4), 0.6] {
            var eye = Path()
            eye.move(to: CGPoint(x: w * x - w * 0.055, y: center.y - w * 0.03))
            eye.addQuadCurve(to: CGPoint(x: w * x + w * 0.055, y: center.y - w * 0.03), control: CGPoint(x: w * x, y: center.y + w * 0.035))
            ctx.stroke(eye, with: .color(dark), style: StrokeStyle(lineWidth: w * 0.032, lineCap: .round))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: w * 0.45, y: center.y + w * 0.09))
        smile.addQuadCurve(to: CGPoint(x: w * 0.55, y: center.y + w * 0.09), control: CGPoint(x: w * 0.5, y: center.y + w * 0.135))
        ctx.stroke(smile, with: .color(dark), style: StrokeStyle(lineWidth: w * 0.028, lineCap: .round))
        // Rosy cheeks.
        for x in [CGFloat(0.31), 0.69] {
            ctx.fill(Path(ellipseIn: CGRect(x: w * x - w * 0.045, y: center.y + w * 0.03, width: w * 0.09, height: w * 0.05)),
                     with: .color(Color(red: 1.0, green: 0.55, blue: 0.6).opacity(0.35)))
        }
    }
}
