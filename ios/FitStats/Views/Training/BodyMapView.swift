import SwiftUI

/// A front and a back figure with each muscle shaded by how much it was worked: `levels` from
/// 0 (not at all) to 1 (most). The shapes are simple, mannequin-like regions in a 100 × 210 box
/// per figure, drawn in a Canvas; muscles with no level are drawn in the body's base colour.
struct BodyMapView: View {
    let levels: [String: Double]
    var color: Color = Theme.muscle
    var height: CGFloat = 230
    var showsLabels = true

    var body: some View {
        HStack(spacing: height * 0.09) {
            figure(front: true)
            figure(front: false)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("body-map")
    }

    private func figure(front: Bool) -> some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let scale = size.height / 210
                let dx = (size.width - 100 * scale) / 2
                ctx.translateBy(x: dx, y: 0)
                ctx.scaleBy(x: scale, y: scale)
                let base = Color.white.opacity(0.09)
                let skin = Color.white.opacity(0.05)
                for part in BodyShapes.neutral(front: front) {
                    ctx.fill(part, with: .color(skin))
                }
                for (muscle, path) in BodyShapes.muscles(front: front) {
                    ctx.fill(path, with: .color(base))
                    let level = levels[muscle] ?? 0
                    if level > 0 { ctx.fill(path, with: .color(color.opacity(0.25 + 0.75 * min(1, level)))) }
                }
                // The lines between the abs, so they read as abs.
                if front {
                    var lines = Path()
                    for y in [CGFloat(58.5), 66, 73.5] {
                        lines.move(to: CGPoint(x: 43, y: y))
                        lines.addLine(to: CGPoint(x: 57, y: y))
                    }
                    lines.move(to: CGPoint(x: 50, y: 51))
                    lines.addLine(to: CGPoint(x: 50, y: 80))
                    ctx.stroke(lines, with: .color(Theme.background.opacity(0.9)), lineWidth: 1.1)
                }
            }
            .frame(width: height * 100 / 210, height: height)
            if showsLabels {
                Text(front ? "Front" : "Back").font(.caption2).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private var accessibilityText: String {
        let worked = levels.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { $0.key.replacingOccurrences(of: "_", with: " ") }
        return worked.isEmpty ? "Body map: no muscles worked" : "Body map, most worked first: \(worked.joined(separator: ", "))"
    }
}

extension Theme {
    /// Muscles on the body map.
    static let muscle = Color(red: 1.0, green: 0.47, blue: 0.32)
}

/// The figure's regions, in a 100 × 210 box.
enum BodyShapes {
    private static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private static func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    /// A shape and its mirror image across the middle (x = 50).
    private static func pair(_ make: (Bool) -> Path) -> Path {
        var p = make(false)
        p.addPath(make(true))
        return p
    }

    private static func mx(_ x: CGFloat, _ mirrored: Bool) -> CGFloat { mirrored ? 100 - x : x }

    /// Head, neck, hands, pelvis, knees and feet: not muscles.
    static func neutral(front: Bool) -> [Path] {
        var out = [
            ellipse(50, 12.5, 9.5, 10.5),
            box(45, 21, 10, 8, 3),
            pair { m in ellipse(mx(16.5, m), 95, 4, 5) },
            pair { m in ellipse(mx(40.5, m), 140, 5, 4.5) },
            pair { m in box(m ? 53 : 34, 188, 13, 7, 3.5) },
        ]
        if front { out.append(polygon([(35, 80), (65, 80), (60, 92), (40, 92)])) }
        return out
    }

    /// Muscle id → its region on this side, in drawing order.
    static func muscles(front: Bool) -> [(String, Path)] {
        let forearms = pair { m in ellipse(mx(19, m), 77, 4.6, 12) }
        if front {
            return [
                ("chest", pair { m in box(m ? 50.5 : 35, 32, 14.5, 17, 6) }),
                ("shoulders", pair { m in ellipse(mx(29, m), 37, 8.5, 8) }),
                ("biceps", pair { m in ellipse(mx(23.5, m), 54, 5.5, 11) }),
                ("forearms", forearms),
                ("abs", box(42.5, 51, 15, 29, 4)),
                ("obliques", pair { m in box(m ? 58 : 35, 52, 7, 26, 3.5) }),
                ("quads", pair { m in box(m ? 51.5 : 33, 92, 15.5, 44, 8) }),
                ("adductors", pair { m in box(m ? 50 : 45.5, 94, 4.5, 28, 2.2) }),
                ("calves", pair { m in box(m ? 53.5 : 34.5, 146, 12, 40, 6) }),
            ]
        }
        return [
            ("upper_back", polygon([(43, 24), (57, 24), (68, 33), (62, 52), (38, 52), (32, 33)])),
            ("lats", pair { m in polygon([(mx(35, m), 47), (mx(44, m), 52), (mx(45, m), 72), (mx(38, m), 70), (mx(33, m), 58)]) }),
            ("lower_back", box(43, 63, 14, 16, 4)),
            ("shoulders", pair { m in ellipse(mx(29, m), 37, 8.5, 8) }),
            ("triceps", pair { m in ellipse(mx(23.5, m), 54, 5.5, 11) }),
            ("forearms", forearms),
            ("glutes", pair { m in ellipse(mx(42.5, m), 88, 8.5, 9) }),
            ("hamstrings", pair { m in box(m ? 51.5 : 33, 98, 15.5, 38, 8) }),
            ("calves", pair { m in ellipse(mx(40.5, m), 158, 7, 16) }),
        ]
    }
}

/// Muscles as chips: the main ones filled, the helpers outlined.
struct MuscleChips: View {
    let primary: [String]
    let secondary: [String]
    let library: ExerciseLibrary

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(primary, id: \.self) { chip(library.label($0), main: true) }
            ForEach(secondary, id: \.self) { chip(library.label($0), main: false) }
        }
    }

    private func chip(_ label: String, main: Bool) -> some View {
        Text(label)
            .font(.caption.weight(main ? .semibold : .regular))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(main ? Theme.muscle.opacity(0.22) : Color.clear))
            .overlay(Capsule().stroke(Theme.muscle.opacity(main ? 0 : 0.5), lineWidth: 1))
            .foregroundStyle(main ? Theme.muscle : Theme.secondary)
    }
}
