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
    var font: Font = .footnote
    /// The large size: today's scores under the brief.
    var showsScores = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: snapshot.coachName.map { "Coach \($0)" } ?? "Coach", icon: "sparkles", color: Theme.sleep)
            if let text = snapshot.todaysCoachText {
                Text(Self.styled(text))
                    .font(font)
                    .foregroundStyle(.white)
                    .lineLimit(lines)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if showsScores {
                    WidgetScoresMedium(snapshot: snapshot, showsFooter: false).frame(height: 100)
                }
            } else {
                Spacer(minLength: 0)
                Text("No brief yet today. Tap to open the coach and write today's.")
                    .font(font)
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The brief a line per label, the bold labels ("**Today**") in the coach's colour, and
    /// headings and bullets made plain.
    static func styled(_ text: String) -> AttributedString {
        let cleaned = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> String in
                var l = line.trimmingCharacters(in: .whitespaces)
                while l.hasPrefix("#") { l.removeFirst() }
                if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
                return l.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
        var styled = (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(cleaned)
        let bold = styled.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }.map(\.range)
        for range in bold { styled[range].foregroundColor = Theme.sleep }
        return styled
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


// MARK: - More sizes

/// Bars for the last 7 days of one measure, today brightest, with a value over each and the
/// weekday under it.
struct WidgetBars: View {
    let days: [WidgetDay]
    let value: (WidgetDay) -> Double?
    let maxValue: Double
    let color: (Double?) -> Color
    var label: (Double) -> String = { WidgetFormat.number($0) }
    var showsDays = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                let v = value(day)
                let last = i == days.count - 1
                VStack(spacing: 2) {
                    Text(v.map(label) ?? "–")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(last ? .white : Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(v).opacity(last ? 1 : 0.65))
                                .frame(height: max(3, geo.size.height * min(1, (v ?? 0) / max(maxValue, 1))))
                        }
                    }
                    if showsDays {
                        Text(day.weekdayLetter)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(last ? .white : Theme.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Last night's stages as bars with their minutes.
struct WidgetStages: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let stages: [(String, Double?, Color)] = [
            ("Awake", snapshot.awakeMin, Theme.stageAwake), ("REM", snapshot.remMin, Theme.stageRem),
            ("Light", snapshot.lightMin, Theme.stageLight), ("Deep", snapshot.deepMin, Theme.stageDeep),
        ]
        let most = max(1, stages.compactMap { $0.1 }.max() ?? 1)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(stages.indices, id: \.self) { i in
                let stage = stages[i]
                HStack(spacing: 6) {
                    Text(stage.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(stage.2).frame(width: 36, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(Theme.track)
                            .overlay(alignment: .leading) {
                                Capsule().fill(stage.2).frame(width: max(4, geo.size.width * (stage.1 ?? 0) / most))
                            }
                    }
                    .frame(height: 6)
                    Text(WidgetFormat.duration(stage.1)).font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.secondary).frame(width: 46, alignment: .trailing)
                }
            }
        }
    }
}

/// Large: the three scores as big rings, then the week's recovery.
struct WidgetScoresLarge: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let s = snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetHeader(title: "Scores", icon: "circle.circle.fill", color: Theme.recoveryGreen)
                Text(WidgetFormat.updated(s)).font(.caption2).foregroundStyle(Theme.tertiary).lineLimit(1)
            }
            WidgetScoresMedium(snapshot: s, showsFooter: false).frame(height: 104)
            HStack(spacing: 12) {
                Label("\(WidgetFormat.number(s.steps)) steps", systemImage: "figure.walk").foregroundStyle(Theme.body)
                Label("Stress \(WidgetFormat.number(s.stress))", systemImage: "waveform.path.ecg").foregroundStyle(Theme.stressColor(s.stress))
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.medium))
            .lineLimit(1)
            Text("Recovery, last 7 days").font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
            WidgetBars(days: s.week ?? [], value: \.recovery, maxValue: 100, color: Theme.recoveryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Medium: last night's sleep, tonight's bedtime and the stages.
struct WidgetSleepMedium: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 14) {
            WidgetSleepSmall(snapshot: snapshot).frame(width: 118)
            VStack(alignment: .leading, spacing: 6) {
                Text("Stages").font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
                WidgetStages(snapshot: snapshot)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Large: the medium sleep view and the week's sleep in hours.
struct WidgetSleepLarge: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetSleepMedium(snapshot: snapshot).frame(height: 140)
            Text("Sleep, last 7 days (hours)").font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
            WidgetBars(days: snapshot.week ?? [], value: \.sleepMin, maxValue: 600, color: { _ in Theme.sleep },
                       label: { String(format: "%.1f", $0 / 60) })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Medium: recovery as a big ring beside strain, sleep, steps and stress.
struct WidgetTodayMedium: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let s = snapshot
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                WidgetRing(progress: (s.recovery ?? 0) / 100, color: Theme.recoveryColor(s.recovery), lineWidth: 10) {
                    Text(s.recovery.map { "\(WidgetFormat.number($0))%" } ?? "–")
                        .font(Theme.number(22)).foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1).padding(10)
                }
                .frame(width: 92, height: 92)
                Text(Theme.recoveryLabel(s.recovery)).font(.caption2.weight(.medium)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            .frame(width: 110)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    tile("Strain", WidgetFormat.number(s.strain), "flame.fill", Theme.strain)
                    tile("Sleep", WidgetFormat.duration(s.sleepMin), "moon.fill", Theme.sleep)
                }
                HStack(spacing: 8) {
                    tile("Steps", WidgetFormat.number(s.steps), "figure.walk", Theme.body)
                    tile("Stress", WidgetFormat.number(s.stress), "waveform.path.ecg", Theme.stressColor(s.stress))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).foregroundStyle(Theme.secondary)
            }
            .font(.system(size: 10, weight: .semibold))
            Text(value).font(Theme.number(17, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}

/// Medium: steps, the bar to the goal, active calories and the week's steps.
struct WidgetStepsMedium: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let goal = snapshot.stepGoal ?? 10_000
        let progress = min(1, (snapshot.steps ?? 0) / max(goal, 1))
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: "Steps", icon: "figure.walk", color: Theme.body)
                Text(WidgetFormat.number(snapshot.steps)).font(Theme.number(30)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                GeometryReader { geo in
                    Capsule().fill(Theme.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(progress >= 1 ? Theme.recoveryGreen : Theme.body).frame(width: max(6, geo.size.width * progress))
                        }
                }
                .frame(height: 7)
                Text("Goal \(WidgetFormat.number(goal))").font(.caption2).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").foregroundStyle(Theme.body)
                    Text("\(WidgetFormat.number(snapshot.activeCalories)) active kcal").foregroundStyle(Theme.secondary)
                }
                .font(.caption2.weight(.medium))
                .lineLimit(1)
            }
            .frame(width: 130)
            WidgetBars(days: snapshot.week ?? [], value: \.steps, maxValue: max(goal, (snapshot.week ?? []).compactMap(\.steps).max() ?? 0),
                       color: { ($0 ?? 0) >= goal ? Theme.recoveryGreen : Theme.body }, label: WidgetFormat.compact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Medium: resting heart rate and HRV side by side, with your usual and recovery.
struct WidgetHeartMedium: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WidgetHeader(title: "Heart", icon: "heart.fill", color: Theme.heart)
                Text("Recovery \(snapshot.recovery.map { WidgetFormat.number($0) + "%" } ?? "–")")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.recoveryColor(snapshot.recovery))
            }
            HStack(spacing: 10) {
                column("Resting HR", snapshot.rhr, unit: "bpm", base: snapshot.rhrBaseline, lowerIsBetter: true)
                column("HRV", snapshot.hrv, unit: "ms", base: snapshot.hrvBaseline, lowerIsBetter: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func column(_ title: String, _ value: Double?, unit: String, base: Double?, lowerIsBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(WidgetFormat.number(value)).font(Theme.number(30)).foregroundStyle(.white)
                Text(unit).font(.caption).foregroundStyle(Theme.tertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if let base {
                let diff = ((value ?? base) - base).rounded()
                let good = lowerIsBetter ? diff <= 0 : diff >= 0
                Text(value == nil ? "Usual \(WidgetFormat.number(base))"
                     : diff == 0 ? "Same as usual (\(WidgetFormat.number(base)))"
                     : "\(diff > 0 ? "▲" : "▼") \(WidgetFormat.number(abs(diff))) vs usual \(WidgetFormat.number(base))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(value == nil || diff == 0 ? Theme.secondary : good ? Theme.recoveryGreen : Theme.recoveryYellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Usual: needs a few more days").font(.caption2).foregroundStyle(Theme.tertiary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }
}

/// Medium: today's stress beside the week's.
struct WidgetStressMedium: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 14) {
            WidgetStressSmall(snapshot: snapshot).frame(width: 110)
            // Scaled to the week's highest, as stress mostly stays low.
            WidgetBars(days: snapshot.week ?? [], value: \.stress,
                       maxValue: max(25, ((snapshot.week ?? []).compactMap(\.stress).max() ?? 0) * 1.2), color: Theme.stressColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Large: the week's recovery, sleep, strain and steps.
struct WidgetWeekLarge: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let week = snapshot.week ?? []
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Last 7 days", icon: "calendar", color: Theme.recoveryGreen)
            row("Recovery %") { WidgetBars(days: week, value: \.recovery, maxValue: 100, color: Theme.recoveryColor, showsDays: false) }
            row("Sleep, hours") {
                WidgetBars(days: week, value: \.sleepMin, maxValue: 600, color: { _ in Theme.sleep },
                           label: { String(format: "%.1f", $0 / 60) }, showsDays: false)
            }
            row("Strain") { WidgetBars(days: week, value: \.strain, maxValue: 100, color: { _ in Theme.strain }, showsDays: false) }
            row("Steps") {
                WidgetBars(days: week, value: \.steps, maxValue: max(snapshot.stepGoal ?? 10_000, week.compactMap(\.steps).max() ?? 0),
                           color: { _ in Theme.body }, label: WidgetFormat.compact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ title: String, @ViewBuilder _ bars: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
            bars()
        }
        .frame(maxHeight: .infinity)
    }
}

/// Medium: this week's workouts, a dot for each day, and the latest one.
struct WidgetTrainingMedium: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 14) {
            WidgetTrainingSmall(snapshot: snapshot).frame(width: 130)
            VStack(alignment: .leading, spacing: 8) {
                Text("This week").font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
                HStack(spacing: 6) {
                    ForEach(weekDates, id: \.self) { date in
                        let done = snapshot.workoutDays?.contains(date) ?? false
                        let future = date > snapshot.date
                        VStack(spacing: 4) {
                            Circle()
                                .fill(done ? Theme.strain : Theme.track)
                                .overlay(Circle().stroke(date == snapshot.date ? Color.white.opacity(0.7) : .clear, lineWidth: 1.5))
                                .frame(width: 18, height: 18)
                                .opacity(future ? 0.4 : 1)
                            Text(WidgetDay(date: date, recovery: nil, sleepMin: nil, strain: nil, steps: nil, stress: nil).weekdayLetter)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Theme.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Monday to Sunday of the snapshot's week.
    private var weekDates: [String] {
        guard let d = WidgetDay.dayFormatter.date(from: snapshot.date) else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let fromMonday = (cal.component(.weekday, from: d) + 5) % 7
        return (0..<7).map { WidgetDay.addDays(snapshot.date, $0 - fromMonday) }
    }
}
