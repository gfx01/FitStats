import SwiftUI

// The Home Screen widgets' faces. Plain views, so the app's Settings → Widgets can show the
// same thing as a preview; the widget extension adds its background and families around them.

/// A score ring, like the app's RingGauge but without its glow (widgets draw no shadows well).
struct WidgetRing<Center: View>: View {
    let progress: Double
    let color: Color
    var endColor: Color? = nil
    var lineWidth: CGFloat = 8
    var target: [Double]? = nil
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            if let target, target.count == 2 {
                Circle()
                    .trim(from: max(0, min(1, target[0] / 100)), to: max(0, min(1, target[1] / 100)))
                    .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(AngularGradient(gradient: Gradient(colors: [color.opacity(0.85), endColor ?? color]), center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * max(0.05, min(1, progress)))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            center()
        }
    }
}

/// Shown until the app has shared any numbers with the widget.
struct WidgetEmptyFace: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("FitStats", systemImage: "bolt.heart.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.recoveryGreen)
            Spacer(minLength: 0)
            Text("Open FitStats once to show your scores here.")
                .font(compact ? .caption : .footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Small: recovery as a big ring, strain and sleep under it.
struct WidgetScoresSmall: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let recovery = snapshot.recovery
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.heart.fill")
                Text("Recovery")
                Spacer(minLength: 0)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.recoveryColor(recovery))
            WidgetRing(progress: (recovery ?? 0) / 100, color: Theme.recoveryColor(recovery), lineWidth: 9) {
                Text(recovery.map { "\(WidgetFormat.number($0))%" } ?? "–")
                    .font(Theme.number(22))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(9)
            }
            .frame(width: 74, height: 74)
            HStack {
                stat("flame.fill", WidgetFormat.number(snapshot.strain, decimals: 0), Theme.strain)
                Spacer(minLength: 2)
                stat("moon.fill", WidgetFormat.duration(snapshot.sleepMin), Theme.sleep)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color)
            Text(value).font(Theme.number(13, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// Medium: recovery, strain and sleep rings, then steps and when it was updated.
struct WidgetScoresMedium: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                ring("Recovery", snapshot.recovery, Theme.recoveryColor(snapshot.recovery), nil, suffix: "%",
                     caption: Theme.recoveryLabel(snapshot.recovery))
                ring("Strain", snapshot.strain, Theme.strain, Theme.strainEnd, target: snapshot.strainTarget,
                     caption: snapshot.strainTarget.map { "Goal \(Int($0[0]))–\(Int($0[1]))" } ?? " ")
                ring("Sleep", snapshot.sleepScore, Theme.sleep, nil, caption: WidgetFormat.duration(snapshot.sleepMin))
            }
            HStack(spacing: 4) {
                Image(systemName: "figure.walk").foregroundStyle(Theme.body)
                Text("\(WidgetFormat.number(snapshot.steps)) steps")
                Spacer(minLength: 4)
                Text(WidgetFormat.updated(snapshot)).foregroundStyle(Theme.tertiary)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ring(_ title: String, _ value: Double?, _ color: Color, _ end: Color?, target: [Double]? = nil,
                      suffix: String = "", caption: String) -> some View {
        VStack(spacing: 3) {
            WidgetRing(progress: (value ?? 0) / 100, color: color, endColor: end, lineWidth: 7, target: target) {
                Text(value.map { WidgetFormat.number($0) + suffix } ?? "–")
                    .font(Theme.number(16))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(7)
            }
            .frame(width: 60, height: 60)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
            Text(caption).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Small: last night's sleep and tonight's bedtime.
struct WidgetSleepSmall: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Sleep", systemImage: "moon.stars.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.sleep)
            Text(WidgetFormat.duration(snapshot.sleepMin))
                .font(Theme.number(26))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(snapshot.sleepScore.map { "Score \(WidgetFormat.number($0))" } ?? "No score yet")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 4)
            if let bed = snapshot.tonightBedtime {
                Text("In bed by")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.tertiary)
                Text(WidgetFormat.clock(bed))
                    .font(Theme.number(20, weight: .semibold))
                    .foregroundStyle(Theme.sleep)
                    .lineLimit(1)
            } else {
                Text(WidgetFormat.updated(snapshot))
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The widgets' background, a darker take on the app's cards.
struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.09, green: 0.09, blue: 0.13), Theme.background], startPoint: .top, endPoint: .bottom)
    }
}
