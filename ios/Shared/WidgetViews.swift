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
    var showsFooter = true

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                ring("Recovery", snapshot.recovery, Theme.recoveryColor(snapshot.recovery), nil, suffix: "%",
                     caption: Theme.recoveryLabel(snapshot.recovery))
                ring("Strain", snapshot.strain, Theme.strain, Theme.strainEnd, target: snapshot.strainTarget,
                     caption: snapshot.strainTarget.map { "Goal \(Int($0[0]))–\(Int($0[1]))" } ?? " ")
                ring("Sleep", snapshot.sleepScore, Theme.sleep, nil, caption: WidgetFormat.duration(snapshot.sleepMin))
            }
            if showsFooter {
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

/// A widget's title row: icon and name in the widget's colour.
struct WidgetHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
            Spacer(minLength: 0)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

/// Small: steps against the goal as a ring, active calories under it.
struct WidgetStepsSmall: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let goal = snapshot.stepGoal ?? 10_000
        let progress = (snapshot.steps ?? 0) / max(goal, 1)
        VStack(spacing: 6) {
            WidgetHeader(title: "Steps", icon: "figure.walk", color: Theme.body)
            WidgetRing(progress: progress, color: Theme.body, endColor: progress >= 1 ? Theme.recoveryGreen : nil, lineWidth: 9) {
                VStack(spacing: 0) {
                    Text(WidgetFormat.number(snapshot.steps))
                        .font(Theme.number(17))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("of \(WidgetFormat.compact(goal))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(10)
            }
            .frame(width: 74, height: 74)
            Text(progress >= 1 ? "Goal reached" : "\(WidgetFormat.number(max(0, goal - (snapshot.steps ?? 0)))) to go")
                .font(.caption2.weight(.medium))
                .foregroundStyle(progress >= 1 ? Theme.recoveryGreen : Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small: resting heart rate and HRV, each against your usual.
struct WidgetHeartSmall: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Heart", icon: "heart.fill", color: Theme.heart)
            Spacer(minLength: 0)
            metric("Resting HR", snapshot.rhr, unit: "bpm", base: snapshot.rhrBaseline, lowerIsBetter: true)
            Spacer(minLength: 0)
            metric("HRV", snapshot.hrv, unit: "ms", base: snapshot.hrvBaseline, lowerIsBetter: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metric(_ title: String, _ value: Double?, unit: String, base: Double?, lowerIsBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(WidgetFormat.number(value)).font(Theme.number(24)).foregroundStyle(.white)
                Text(unit).font(.caption2).foregroundStyle(Theme.tertiary)
                Spacer(minLength: 2)
                if let value, let base {
                    let diff = (value - base).rounded()
                    let good = lowerIsBetter ? diff <= 0 : diff >= 0
                    Text(diff == 0 ? "usual" : "\(diff > 0 ? "▲" : "▼") \(WidgetFormat.number(abs(diff)))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(diff == 0 ? Theme.secondary : good ? Theme.recoveryGreen : Theme.recoveryYellow)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

/// Small: today's stress as a ring with its level.
struct WidgetStressSmall: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let stress = snapshot.stress
        VStack(spacing: 6) {
            WidgetHeader(title: "Stress", icon: "waveform.path.ecg", color: Theme.stressColor(stress))
            WidgetRing(progress: (stress ?? 0) / 100, color: Theme.stressColor(stress), lineWidth: 9) {
                Text(WidgetFormat.number(stress))
                    .font(Theme.number(24))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(10)
            }
            .frame(width: 74, height: 74)
            Text(Theme.stressLabel(stress))
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The last 7 days as recovery bars coloured by zone, with sleep under each.
struct WidgetWeekBars: View {
    let week: [WidgetDay]
    var showsSleep = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(week.enumerated()), id: \.offset) { i, day in
                VStack(spacing: 3) {
                    Text(WidgetFormat.number(day.recovery))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(i == week.count - 1 ? .white : Theme.secondary)
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.recoveryColor(day.recovery).opacity(i == week.count - 1 ? 1 : 0.7))
                                .frame(height: max(3, geo.size.height * min(1, (day.recovery ?? 0) / 100)))
                        }
                    }
                    Text(day.weekdayLetter)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(i == week.count - 1 ? .white : Theme.tertiary)
                    if showsSleep {
                        Text(day.sleepMin.map { String(format: "%.1f", $0 / 60) } ?? "–")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.sleep)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Medium: the week's recovery and sleep.
struct WidgetWeekMedium: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let week = snapshot.week ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                WidgetHeader(title: "Last 7 days", icon: "calendar", color: Theme.recoveryGreen)
                Text(averages(week))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if week.isEmpty {
                Spacer()
                Text("Open FitStats to fill in the week.").font(.caption).foregroundStyle(Theme.secondary)
                Spacer()
            } else {
                WidgetWeekBars(week: week)
                HStack(spacing: 10) {
                    Label("Recovery %", systemImage: "square.fill").foregroundStyle(Theme.secondary)
                    Label("Sleep, hours", systemImage: "square.fill").foregroundStyle(Theme.sleep)
                }
                .font(.system(size: 9))
                .labelStyle(WidgetDotLabel())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "avg 66% · 7h 29m".
    private func averages(_ week: [WidgetDay]) -> String {
        let r = week.compactMap(\.recovery), s = week.compactMap(\.sleepMin)
        guard !r.isEmpty || !s.isEmpty else { return "" }
        let rec = r.isEmpty ? "–" : "\(WidgetFormat.number(r.reduce(0, +) / Double(r.count)))%"
        let sleep = s.isEmpty ? "–" : WidgetFormat.duration(s.reduce(0, +) / Double(s.count))
        return "avg \(rec) · \(sleep)"
    }
}

/// A tiny square before the text, for the week's legend.
struct WidgetDotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

/// Large: the day at a glance.
struct WidgetTodayLarge: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let s = snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetHeader(title: "Today", icon: "circle.circle.fill", color: Theme.recoveryGreen)
                Text(WidgetFormat.updated(s)).font(.caption2).foregroundStyle(Theme.tertiary).lineLimit(1)
            }
            WidgetScoresMedium(snapshot: s, showsFooter: false).frame(height: 96)
            HStack(spacing: 8) {
                tile("Steps", WidgetFormat.number(s.steps), "figure.walk", Theme.body)
                tile("Resting HR", WidgetFormat.number(s.rhr), "heart.fill", Theme.heart)
                tile("HRV", WidgetFormat.number(s.hrv), "waveform.path.ecg.rectangle", Theme.heart)
                tile("Stress", WidgetFormat.number(s.stress), "waveform.path.ecg", Theme.stressColor(s.stress))
            }
            if let bed = s.tonightBedtime {
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill").foregroundStyle(Theme.sleep)
                    Text("In bed by \(WidgetFormat.clock(bed)) tonight")
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
            }
            if let week = s.week, !week.isEmpty {
                WidgetWeekBars(week: week, showsSleep: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tile(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color)
            Text(value).font(Theme.number(15, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.system(size: 9)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}

/// Medium (and large): today's brief from your coach.
struct WidgetCoachFace: View {
    let snapshot: WidgetSnapshot
    var lines = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: snapshot.coachName.map { "Coach \($0)" } ?? "Coach", icon: "sparkles", color: Theme.sleep)
            if let text = snapshot.todaysCoachText {
                Text(Self.plain(text))
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .lineLimit(lines)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("No brief yet today. Tap to open the coach and write today's.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The brief without Markdown marks (**bold**, # headings, - bullets).
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> String in
                var l = line.trimmingCharacters(in: .whitespaces)
                while l.hasPrefix("#") { l.removeFirst() }
                if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
                return l.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: " ")
    }
}

/// Small: workouts this week and the latest one.
struct WidgetTrainingSmall: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(title: "Training", icon: "dumbbell.fill", color: Theme.strain)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.workoutsThisWeek ?? 0)").font(Theme.number(30)).foregroundStyle(.white)
                Text((snapshot.workoutsThisWeek ?? 0) == 1 ? "workout" : "workouts").font(.caption).foregroundStyle(Theme.secondary)
            }
            Text("this week · \(WidgetFormat.duration(snapshot.workoutMinutesThisWeek ?? 0))")
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let name = snapshot.lastWorkoutName {
                Text("Last").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tertiary)
                Text(name).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                if let date = snapshot.lastWorkoutDate {
                    Text(WidgetFormat.day(date, today: snapshot.date)).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
