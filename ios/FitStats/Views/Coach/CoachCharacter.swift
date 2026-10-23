import SwiftUI

/// The coach's animated character, drawn in a Canvas from the time (no image assets):
/// - Nova, a glossy little robot: a glass visor with glowing eyes that look around, a springy
///   antenna and a chest light; a scan line sweeps the visor while it thinks.
/// - Ace, a flame in a sweatband: three flickering layers, rising sparks, determined brows; it
///   hops while it thinks.
/// - Kai, a glowing orb with a sprout: it floats and breathes, fireflies circle it, its eyes stay
///   calmly closed and open now and then.
/// All three blink, glance around and talk (the mouth moves) while an answer streams in. Still with
/// Reduce Motion, or when `animated` is false (the small avatars in a long conversation).
struct CoachCharacter: View {
    let persona: CoachPersona
    var size: CGFloat = 44
    /// Working on an answer, before any text arrives.
    var thinking = false
    /// The answer is streaming in.
    var talking = false
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = !animated || reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            // A fixed moment when still: eyes open, looking ahead.
            let t = still ? 0.9 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
            let mood = Mood(thinking: thinking && !still, talking: talking && !still)
            Canvas { ctx, canvas in
                let w = min(canvas.width, canvas.height)
                ctx.translateBy(x: (canvas.width - w) / 2, y: (canvas.height - w) / 2)
                switch persona {
                case .nova: Self.drawNova(&ctx, w: w, t: t, mood: mood)
                case .ace: Self.drawAce(&ctx, w: w, t: t, mood: mood)
                case .kai: Self.drawKai(&ctx, w: w, t: t, mood: mood)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(persona.name), your coach")
    }

    struct Mood: Sendable {
        let thinking: Bool
        let talking: Bool
    }

    // MARK: motion

    nonisolated private static func wave(_ t: Double, _ speed: Double, _ phase: Double = 0) -> CGFloat {
        CGFloat(sin(t * speed + phase))
    }

    /// A repeatable pseudo-random number in 0..<1 for an integer.
    nonisolated private static func noise(_ n: Int) -> Double {
        let x = sin(Double(n) * 12.9898 + 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    nonisolated private static func smooth(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }

    /// 1 with the eyes open. A quick blink at a random moment every few seconds, sometimes two.
    nonisolated static func blink(_ t: Double, every period: Double = 3.8, seed: Int = 0) -> CGFloat {
        let k = Int((t / period).rounded(.down))
        let p = t - Double(k) * period
        let start = 0.4 + noise(k + seed) * (period - 1.2)
        func closed(_ at: Double) -> CGFloat {
            let d = abs(p - at - 0.075)
            return d < 0.075 ? CGFloat(d / 0.075) : 1
        }
        var open = closed(start)
        if noise(k * 7 + seed + 3) > 0.75 { open = min(open, closed(start + 0.24)) }
        return max(0.08, open)
    }

    /// Where the eyes look, from −1 to 1 on each axis: a new spot every couple of seconds,
    /// often straight ahead; up and to the side while thinking.
    nonisolated private static func gaze(_ t: Double, seed: Int, thinking: Bool) -> CGPoint {
        if thinking {
            return CGPoint(x: 0.55 * sin(t * 1.7), y: -0.75)
        }
        let period = 2.4
        let k = Int((t / period).rounded(.down))
        func spot(_ n: Int) -> CGPoint {
            noise(n * 3 + seed) < 0.4 ? .zero : CGPoint(x: noise(n * 5 + seed) * 2 - 1, y: (noise(n * 11 + seed) * 2 - 1) * 0.6)
        }
        let a = spot(k - 1), b = spot(k)
        let f = CGFloat(smooth((t - Double(k) * period) / 0.22))
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// How open the mouth is while talking, 0–1: syllable-like bursts with short pauses.
    nonisolated private static func speech(_ t: Double) -> CGFloat {
        let syllable = abs(sin(t * 13))
        let phrase = sin(t * 2.1) > -0.55 ? 1.0 : 0.15
        return CGFloat(syllable * phrase)
    }

    nonisolated private static func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    /// A soft glow behind the character and its shadow on the ground.
    nonisolated private static func stage(_ ctx: inout GraphicsContext, w: CGFloat, color: Color, glow: Double, lift: CGFloat) {
        let c = CGPoint(x: w * 0.5, y: w * 0.5)
        ctx.fill(ellipse(c, w * 0.5, w * 0.5),
                 with: .radialGradient(Gradient(colors: [color.opacity(0.32 * glow), color.opacity(0)]), center: c, startRadius: 0, endRadius: w * 0.5))
        let spread = 1 - lift / w * 2.5
        ctx.fill(ellipse(CGPoint(x: w * 0.5, y: w * 0.955), w * 0.24 * spread, w * 0.03 * spread), with: .color(.black.opacity(0.35 * Double(spread))))
    }

    /// Three dots over the head, rising one after the other, while thinking.
    nonisolated private static func thoughtDots(_ ctx: inout GraphicsContext, w: CGFloat, t: Double, at origin: CGPoint, color: Color) {
        for i in 0..<3 {
            let up = max(0, sin(t * 6 - Double(i) * 0.9))
            let c = CGPoint(x: origin.x + CGFloat(i) * w * 0.065, y: origin.y - CGFloat(up) * w * 0.035)
            ctx.fill(ellipse(c, w * 0.022, w * 0.022), with: .color(color.opacity(0.5 + 0.5 * up)))
        }
    }

    // MARK: Nova

    nonisolated private static func drawNova(_ ctx: inout GraphicsContext, w: CGFloat, t: Double, mood: Mood) {
        let speed = mood.thinking ? 3.6 : 1.8
        let bob = wave(t, speed) * w * 0.022
        let lift = (wave(t, speed) + 1) * w * 0.012
        let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)
        let violet = Color(red: 0.42, green: 0.44, blue: 1.0)
        stage(&ctx, w: w, color: violet, glow: 0.8 + 0.2 * Double(wave(t, 1.3)), lift: lift)

        // Body and neck, a little behind the head's bob.
        let lag = wave(t, speed, -0.6) * w * 0.016
        let torso = CGRect(x: w * 0.31, y: w * 0.7 + lag, width: w * 0.38, height: w * 0.2)
        ctx.fill(Path(roundedRect: torso, cornerRadius: w * 0.09, style: .continuous),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.95), Color(red: 0.2, green: 0.22, blue: 0.62)]),
                                       startPoint: CGPoint(x: 0, y: torso.minY), endPoint: CGPoint(x: 0, y: torso.maxY)))
        let pulse = 0.55 + 0.45 * Double(wave(t, mood.thinking ? 8 : 2.6))
        let chest = CGPoint(x: w * 0.5, y: torso.midY + w * 0.01)
        ctx.fill(ellipse(chest, w * 0.06, w * 0.06), with: .color(cyan.opacity(0.25 * pulse)))
        ctx.fill(ellipse(chest, w * 0.032, w * 0.032), with: .color(cyan.opacity(0.5 + 0.5 * pulse)))
        ctx.fill(Path(roundedRect: CGRect(x: w * 0.45, y: w * 0.64 + bob, width: w * 0.1, height: torso.minY - w * 0.62 - bob), cornerRadius: w * 0.02),
                 with: .color(Color(red: 0.25, green: 0.27, blue: 0.6)))

        // Antenna on a spring: its tip lags behind the head and sways.
        let head = CGRect(x: w * 0.15, y: w * 0.17 + bob, width: w * 0.7, height: w * 0.5)
        let tip = CGPoint(x: w * 0.5 + wave(t, speed, -1.2) * w * 0.035, y: w * 0.045 + bob + wave(t, speed, -1.4) * w * 0.012)
        var stem = Path()
        stem.move(to: CGPoint(x: w * 0.5, y: head.minY + w * 0.01))
        stem.addQuadCurve(to: tip, control: CGPoint(x: w * 0.5, y: (head.minY + tip.y) / 2))
        ctx.stroke(stem, with: .color(Color(red: 0.6, green: 0.64, blue: 1.0)), style: StrokeStyle(lineWidth: w * 0.03, lineCap: .round))
        var glow = ctx
        glow.addFilter(.blur(radius: w * 0.03))
        glow.fill(ellipse(tip, w * 0.06, w * 0.06), with: .color(cyan.opacity(0.7 * pulse)))
        ctx.fill(ellipse(tip, w * 0.042, w * 0.042), with: .radialGradient(Gradient(colors: [.white, cyan]), center: CGPoint(x: tip.x - w * 0.01, y: tip.y - w * 0.012), startRadius: 0, endRadius: w * 0.05))

        // Headphone ears.
        for x in [head.minX + w * 0.005, head.maxX - w * 0.005] {
            let c = CGPoint(x: x, y: head.midY + w * 0.02)
            ctx.fill(ellipse(c, w * 0.07, w * 0.085), with: .color(Color(red: 0.22, green: 0.24, blue: 0.62)))
            ctx.stroke(ellipse(c, w * 0.04, w * 0.05), with: .color(cyan.opacity(0.4 + 0.4 * pulse)), lineWidth: w * 0.016)
        }

        // Head: a glossy shell with a rim light and a highlight on top.
        let shell = Path(roundedRect: head, cornerRadius: w * 0.2, style: .continuous)
        ctx.fill(shell, with: .linearGradient(Gradient(colors: [Color(red: 0.64, green: 0.6, blue: 1.0), Color(red: 0.36, green: 0.4, blue: 0.98), Color(red: 0.24, green: 0.3, blue: 0.86)]),
                                              startPoint: CGPoint(x: 0, y: head.minY), endPoint: CGPoint(x: 0, y: head.maxY)))
        ctx.stroke(shell, with: .color(.white.opacity(0.18)), lineWidth: w * 0.012)
        ctx.fill(ellipse(CGPoint(x: head.minX + w * 0.2, y: head.minY + w * 0.05), w * 0.12, w * 0.028), with: .color(.white.opacity(0.35)))

        // Visor: dark glass with a reflection.
        let visor = head.insetBy(dx: w * 0.075, dy: w * 0.085).offsetBy(dx: 0, dy: w * 0.015)
        let glass = Path(roundedRect: visor, cornerRadius: w * 0.13, style: .continuous)
        ctx.fill(glass, with: .linearGradient(Gradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.2), Color(red: 0.1, green: 0.13, blue: 0.34)]),
                                              startPoint: CGPoint(x: 0, y: visor.minY), endPoint: CGPoint(x: 0, y: visor.maxY)))
        var reflection = ctx
        reflection.clip(to: glass)
        var band = Path()
        band.move(to: CGPoint(x: visor.minX + w * 0.05, y: visor.maxY))
        band.addLine(to: CGPoint(x: visor.minX + w * 0.16, y: visor.maxY))
        band.addLine(to: CGPoint(x: visor.minX + w * 0.3, y: visor.minY))
        band.addLine(to: CGPoint(x: visor.minX + w * 0.19, y: visor.minY))
        band.closeSubpath()
        reflection.fill(band, with: .color(.white.opacity(0.06)))
        if mood.thinking {
            // A scan line sweeping across the glass.
            let x = visor.minX + visor.width * CGFloat((t * 0.9).truncatingRemainder(dividingBy: 1))
            reflection.fill(Path(CGRect(x: x - w * 0.012, y: visor.minY, width: w * 0.024, height: visor.height)), with: .color(cyan.opacity(0.35)))
        }

        // Eyes: glowing pills that blink and look around; happy arcs now and then while idle.
        let look = gaze(t, seed: 11, thinking: mood.thinking)
        let open = blink(t, seed: 5)
        let happy = !mood.thinking && !mood.talking && sin(t * 0.37) > 0.93
        var eyeGlow = ctx
        eyeGlow.addFilter(.blur(radius: w * 0.025))
        for x in [CGFloat(0.385), 0.615] {
            let c = CGPoint(x: w * x + look.x * w * 0.035, y: visor.midY - w * 0.02 + look.y * w * 0.02)
            if happy {
                var arc = Path()
                arc.move(to: CGPoint(x: c.x - w * 0.045, y: c.y + w * 0.015))
                arc.addQuadCurve(to: CGPoint(x: c.x + w * 0.045, y: c.y + w * 0.015), control: CGPoint(x: c.x, y: c.y - w * 0.05))
                ctx.stroke(arc, with: .color(cyan), style: StrokeStyle(lineWidth: w * 0.03, lineCap: .round))
            } else {
                let h = max(w * 0.014, w * 0.13 * open)
                let eye = Path(roundedRect: CGRect(x: c.x - w * 0.045, y: c.y - h / 2, width: w * 0.09, height: h), cornerRadius: w * 0.045)
                eyeGlow.fill(eye, with: .color(cyan.opacity(0.8)))
                ctx.fill(eye, with: .color(cyan))
                if open > 0.6 {
                    ctx.fill(ellipse(CGPoint(x: c.x - w * 0.015, y: c.y - h * 0.22), w * 0.012, w * 0.016), with: .color(.white.opacity(0.85)))
                }
            }
        }
        // Mouth: talks while the answer streams, a small smile otherwise.
        let my = visor.midY + w * 0.085
        if mood.talking {
            let h = w * (0.014 + 0.05 * speech(t))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.455, y: my - h / 2, width: w * 0.09, height: h), cornerRadius: min(h / 2, w * 0.03)), with: .color(cyan))
        } else if mood.thinking {
            var m = Path()
            m.move(to: CGPoint(x: w * 0.46, y: my))
            m.addLine(to: CGPoint(x: w * 0.54, y: my))
            ctx.stroke(m, with: .color(cyan.opacity(0.8)), style: StrokeStyle(lineWidth: w * 0.024, lineCap: .round))
        } else {
            var m = Path()
            m.move(to: CGPoint(x: w * 0.43, y: my - w * 0.012))
            m.addQuadCurve(to: CGPoint(x: w * 0.57, y: my - w * 0.012), control: CGPoint(x: w * 0.5, y: my + w * 0.045))
            ctx.stroke(m, with: .color(cyan), style: StrokeStyle(lineWidth: w * 0.026, lineCap: .round))
        }
        if mood.thinking { thoughtDots(&ctx, w: w, t: t, at: CGPoint(x: w * 0.74, y: w * 0.1), color: cyan) }
    }

    // MARK: Ace

    nonisolated private static func drawAce(_ ctx: inout GraphicsContext, w: CGFloat, t: Double, mood: Mood) {
        let hop = mood.thinking ? -abs(wave(t, 5.2)) * w * 0.06 : wave(t, 2.3) * w * 0.012
        let orange = Color(red: 1.0, green: 0.5, blue: 0.22)
        stage(&ctx, w: w, color: orange, glow: 0.85 + 0.15 * Double(wave(t, 9)), lift: max(0, -hop))
        /// Flicker: a few sines on top of each other, so it never repeats visibly.
        func flick(_ a: Double, _ p: Double) -> CGFloat {
            CGFloat(sin(t * a + p) + 0.5 * sin(t * a * 2.3 + p + 1) + 0.25 * sin(t * a * 4.1 + p + 2)) / 1.75
        }
        func flame(scale s: CGFloat, top: CGFloat, seed: Double) -> Path {
            let cx = w * 0.5, base = w * 0.92 + hop
            let half = w * 0.37 * s * (1 + flick(9, seed) * 0.02)
            let tip = CGPoint(x: cx + flick(5.5, seed) * w * 0.07 * s, y: top + hop - (mood.thinking ? w * 0.03 : 0) + flick(7, seed + 2) * w * 0.015)
            let shoulder = w * 0.6 + hop
            var p = Path()
            p.move(to: tip)
            p.addCurve(to: CGPoint(x: cx + half, y: shoulder),
                       control1: CGPoint(x: tip.x + half * 0.25, y: tip.y + w * 0.16 * s),
                       control2: CGPoint(x: cx + half * 1.02, y: shoulder - w * 0.2 * s))
            p.addCurve(to: CGPoint(x: cx, y: base),
                       control1: CGPoint(x: cx + half, y: shoulder + w * 0.2 * s), control2: CGPoint(x: cx + half * 0.6, y: base))
            p.addCurve(to: CGPoint(x: cx - half, y: shoulder),
                       control1: CGPoint(x: cx - half * 0.6, y: base), control2: CGPoint(x: cx - half, y: shoulder + w * 0.2 * s))
            p.addCurve(to: tip,
                       control1: CGPoint(x: cx - half * 1.02, y: shoulder - w * 0.2 * s),
                       control2: CGPoint(x: tip.x - half * 0.25, y: tip.y + w * 0.16 * s))
            p.closeSubpath()
            return p
        }

        // Sparks rising and fading.
        for i in 0..<6 {
            let phase = (t * 0.5 + noise(i + 40)).truncatingRemainder(dividingBy: 1)
            let x = w * (0.5 + CGFloat(noise(i + 50) - 0.5) * 0.62) + wave(t, 3, Double(i)) * w * 0.02
            let y = w * (0.75 - 0.75 * CGFloat(phase)) + hop
            ctx.fill(ellipse(CGPoint(x: x, y: y), w * 0.016 * CGFloat(1 - phase), w * 0.016 * CGFloat(1 - phase)),
                     with: .color(Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.9 * (1 - phase))))
        }

        let outer = flame(scale: 1, top: w * 0.02, seed: 0)
        ctx.fill(outer, with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.2), Color(red: 0.98, green: 0.36, blue: 0.2), Color(red: 0.9, green: 0.2, blue: 0.32)]),
                                              startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: w)))
        ctx.fill(flame(scale: 0.78, top: w * 0.17, seed: 1.7),
                 with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.8, blue: 0.3), Color(red: 1.0, green: 0.55, blue: 0.22)]),
                                       startPoint: CGPoint(x: 0, y: w * 0.2), endPoint: CGPoint(x: 0, y: w)))
        ctx.fill(flame(scale: 0.5, top: w * 0.42, seed: 3.1), with: .color(Color(red: 1.0, green: 0.93, blue: 0.62).opacity(0.75)))

        // A sweatband across the forehead.
        var band = ctx
        band.clip(to: outer)
        let by = w * 0.455 + hop
        band.fill(Path(CGRect(x: 0, y: by, width: w, height: w * 0.075)), with: .color(.white.opacity(0.95)))
        band.fill(Path(CGRect(x: 0, y: by + w * 0.03, width: w, height: w * 0.018)), with: .color(Color(red: 0.92, green: 0.22, blue: 0.3)))

        // Eyes with pupils that look around, and brows: furrowed while thinking, raised while talking.
        let dark = Color(red: 0.24, green: 0.06, blue: 0.1)
        let look = gaze(t, seed: 23, thinking: mood.thinking)
        let open = blink(t + 1.3, every: 3.4, seed: 9)
        let browLift = mood.talking ? speech(t + 0.2) * w * 0.012 : 0
        for (i, x) in [CGFloat(0.395), 0.605].enumerated() {
            let c = CGPoint(x: w * x, y: w * 0.615 + hop)
            let r = w * 0.068
            ctx.fill(ellipse(c, r, r * open), with: .color(.white))
            if open > 0.3 {
                let pc = CGPoint(x: c.x + look.x * r * 0.38, y: c.y + look.y * r * 0.3 * open)
                ctx.fill(ellipse(pc, r * 0.5, r * 0.5 * open), with: .color(dark))
                ctx.fill(ellipse(CGPoint(x: pc.x - r * 0.18, y: pc.y - r * 0.2), r * 0.15, r * 0.15), with: .color(.white.opacity(0.9)))
            }
            let outerX = i == 0 ? w * 0.315 : w * 0.685, innerX = i == 0 ? w * 0.45 : w * 0.55
            let tilt = mood.thinking ? w * 0.045 : w * 0.03
            var brow = Path()
            brow.move(to: CGPoint(x: outerX, y: w * 0.535 + hop - browLift))
            brow.addLine(to: CGPoint(x: innerX, y: w * 0.535 + hop + tilt - browLift))
            ctx.stroke(brow, with: .color(dark), style: StrokeStyle(lineWidth: w * 0.036, lineCap: .round))
        }
        // Mouth: a toothy grin, talking, or a small "o" while thinking.
        let my = w * 0.745 + hop
        if mood.thinking {
            ctx.fill(ellipse(CGPoint(x: w * 0.5, y: my), w * 0.032, w * 0.036), with: .color(dark))
        } else {
            let openBy = mood.talking ? w * (0.012 + 0.05 * speech(t)) : w * 0.035
            var m = Path()
            m.move(to: CGPoint(x: w * 0.415, y: my - w * 0.012))
            m.addQuadCurve(to: CGPoint(x: w * 0.585, y: my - w * 0.012), control: CGPoint(x: w * 0.5, y: my - w * 0.03))
            m.addQuadCurve(to: CGPoint(x: w * 0.415, y: my - w * 0.012), control: CGPoint(x: w * 0.5, y: my + openBy * 1.6))
            m.closeSubpath()
            ctx.fill(m, with: .color(dark))
            var teeth = ctx
            teeth.clip(to: m)
            teeth.fill(Path(CGRect(x: w * 0.4, y: my - w * 0.04, width: w * 0.2, height: w * 0.035)), with: .color(.white.opacity(0.95)))
        }
        if mood.thinking { thoughtDots(&ctx, w: w, t: t, at: CGPoint(x: w * 0.76, y: w * 0.12), color: Color(red: 1.0, green: 0.8, blue: 0.4)) }
    }

    // MARK: Kai

    nonisolated private static func drawKai(_ ctx: inout GraphicsContext, w: CGFloat, t: Double, mood: Mood) {
        let speed = mood.thinking ? 2.2 : 1.0
        let float = wave(t, 1.1 * speed) * w * 0.028
        let teal = Color(red: 0.3, green: 0.92, blue: 0.8)
        stage(&ctx, w: w, color: teal, glow: 0.75 + 0.25 * Double(wave(t, 0.9)), lift: (float + w * 0.028) * 0.6)

        let center = CGPoint(x: w * 0.5, y: w * 0.55 + float)
        let r = w * 0.3 * (1 + 0.03 * wave(t, 1.3 * speed))

        // Ripples moving out from the orb.
        for k in 0..<2 {
            let phase = (t * 0.3 * speed + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
            let rr = r * (1.1 + 0.45 * CGFloat(phase))
            ctx.stroke(ellipse(center, rr, rr), with: .color(teal.opacity(0.35 * (1 - phase))), lineWidth: w * 0.012)
        }
        // Fireflies circling, some behind the orb (drawn first) and some in front.
        func fireflies(front: Bool) {
            for i in 0..<4 {
                let a = t * 0.45 * speed + Double(i) * .pi / 2
                let inFront = sin(a) > 0
                guard inFront == front else { continue }
                let p = CGPoint(x: center.x + CGFloat(cos(a)) * w * 0.42, y: center.y + CGFloat(sin(a)) * w * 0.12 - w * 0.05)
                let lit = 0.5 + 0.5 * Double(wave(t, 3 + Double(i), Double(i)))
                var g = ctx
                g.addFilter(.blur(radius: w * 0.02))
                g.fill(ellipse(p, w * 0.03, w * 0.03), with: .color(Color(red: 0.85, green: 1.0, blue: 0.6).opacity(0.7 * lit)))
                ctx.fill(ellipse(p, w * 0.011, w * 0.011), with: .color(Color(red: 0.95, green: 1.0, blue: 0.8).opacity(0.6 + 0.4 * lit)))
            }
        }
        fireflies(front: false)

        // The orb: a soft gradient, an inner glow low down and a highlight on top.
        let orb = ellipse(center, r, r)
        ctx.fill(orb, with: .radialGradient(Gradient(colors: [Color(red: 0.7, green: 1.0, blue: 0.9), Color(red: 0.26, green: 0.84, blue: 0.72), Color(red: 0.08, green: 0.52, blue: 0.5)]),
                                            center: CGPoint(x: center.x - r * 0.3, y: center.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
        var inner = ctx
        inner.clip(to: orb)
        inner.fill(ellipse(CGPoint(x: center.x + r * 0.15, y: center.y + r * 0.75), r * 0.8, r * 0.5), with: .color(Color(red: 0.7, green: 1.0, blue: 0.9).opacity(0.25)))
        ctx.stroke(orb, with: .color(.white.opacity(0.22)), lineWidth: w * 0.01)
        ctx.fill(ellipse(CGPoint(x: center.x - r * 0.38, y: center.y - r * 0.55), r * 0.24, r * 0.13), with: .color(.white.opacity(0.5)))

        // A sprout with two leaves, swaying a little behind the orb's float.
        let rustle = mood.thinking ? 3.2 : 1.5
        let base = CGPoint(x: center.x + r * 0.05, y: center.y - r * 0.97)
        let top = CGPoint(x: base.x + wave(t, rustle, -0.7) * w * 0.02, y: base.y - w * 0.09)
        var stem = Path()
        stem.move(to: base)
        stem.addQuadCurve(to: top, control: CGPoint(x: base.x - w * 0.02, y: (base.y + top.y) / 2))
        ctx.stroke(stem, with: .color(Color(red: 0.3, green: 0.7, blue: 0.35)), style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round))
        for (dir, len) in [(CGFloat(1), CGFloat(0.15)), (-1, 0.1)] {
            let sway = wave(t, rustle, dir > 0 ? -1.1 : -0.4) * w * 0.02
            let tip = CGPoint(x: top.x + dir * w * len, y: top.y - w * len * 0.45 + sway)
            var leaf = Path()
            leaf.move(to: top)
            leaf.addQuadCurve(to: tip, control: CGPoint(x: top.x + dir * w * len * 0.2, y: tip.y - w * 0.035))
            leaf.addQuadCurve(to: top, control: CGPoint(x: tip.x - dir * w * len * 0.1, y: top.y + w * 0.03))
            ctx.fill(leaf, with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.92, blue: 0.45), Color(red: 0.25, green: 0.68, blue: 0.32)]),
                                                 startPoint: top, endPoint: tip))
            var vein = Path()
            vein.move(to: top)
            vein.addLine(to: CGPoint(x: top.x + (tip.x - top.x) * 0.75, y: top.y + (tip.y - top.y) * 0.75))
            ctx.stroke(vein, with: .color(.white.opacity(0.3)), lineWidth: w * 0.006)
        }

        // Eyes: calmly closed, opening for a moment every few seconds (and while talking).
        let dark = Color(red: 0.03, green: 0.28, blue: 0.26)
        let cycle = (t / 6.5).truncatingRemainder(dividingBy: 1)
        var awake = cycle > 0.62 && cycle < 0.9 ? CGFloat(smooth((cycle - 0.62) / 0.05) * smooth((0.9 - cycle) / 0.05)) : 0
        if mood.talking || mood.thinking { awake = max(awake, 0.85) }
        awake = min(awake, blink(t + 2.1, every: 4.4, seed: 17))
        let look = gaze(t, seed: 31, thinking: mood.thinking)
        let ey = center.y - w * 0.015
        for x in [CGFloat(-0.1), 0.1] {
            let c = CGPoint(x: center.x + w * x, y: ey)
            if awake > 0.25 {
                ctx.fill(ellipse(CGPoint(x: c.x + look.x * w * 0.012, y: c.y + look.y * w * 0.008), w * 0.035, w * 0.045 * awake), with: .color(dark))
                ctx.fill(ellipse(CGPoint(x: c.x - w * 0.01, y: c.y - w * 0.016 * awake), w * 0.01, w * 0.012 * awake), with: .color(.white.opacity(0.9)))
            } else {
                var lid = Path()
                lid.move(to: CGPoint(x: c.x - w * 0.045, y: c.y - w * 0.01))
                lid.addQuadCurve(to: CGPoint(x: c.x + w * 0.045, y: c.y - w * 0.01), control: CGPoint(x: c.x, y: c.y + w * 0.035))
                ctx.stroke(lid, with: .color(dark), style: StrokeStyle(lineWidth: w * 0.026, lineCap: .round))
            }
        }
        // Rosy cheeks and a small smile that talks softly.
        for x in [CGFloat(-0.19), 0.19] {
            ctx.fill(ellipse(CGPoint(x: center.x + w * x, y: ey + w * 0.06), w * 0.045, w * 0.026), with: .color(Color(red: 1.0, green: 0.55, blue: 0.6).opacity(0.4)))
        }
        let my = ey + w * 0.085
        if mood.talking {
            let h = w * (0.012 + 0.03 * speech(t))
            ctx.fill(ellipse(CGPoint(x: center.x, y: my), w * 0.03, h), with: .color(dark))
        } else {
            var smile = Path()
            smile.move(to: CGPoint(x: center.x - w * 0.045, y: my - w * 0.008))
            smile.addQuadCurve(to: CGPoint(x: center.x + w * 0.045, y: my - w * 0.008), control: CGPoint(x: center.x, y: my + w * 0.035))
            ctx.stroke(smile, with: .color(dark), style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round))
        }
        fireflies(front: true)
        if mood.thinking { thoughtDots(&ctx, w: w, t: t, at: CGPoint(x: w * 0.74, y: w * 0.1), color: teal) }
    }
}
