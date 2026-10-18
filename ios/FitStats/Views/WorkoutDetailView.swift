import Charts
import SwiftUI

extension Exercise {
    var displayName: String {
        name ?? (exerciseType ?? "Workout").replacingOccurrences(of: "_", with: " ").capitalized
    }

    var symbol: String {
        switch exerciseType ?? "" {
        case "RUNNING", "TREADMILL", "TRAIL_RUN", "INCLINE_RUN": return "figure.run"
        case "WALKING", "HIKING", "POWER_WALKING", "TREADMILL_WALK", "INCLINE_WALK": return "figure.walk"
        case "BIKING", "OUTDOOR_BIKE", "STATIONARY_BIKE", "SPINNING", "MOUNTAIN_BIKE": return "figure.outdoor.cycle"
        case "SWIMMING", "SWIMMING_POOL", "SWIMMING_OPEN_WATER": return "figure.pool.swim"
        case "STRENGTH_TRAINING", "WEIGHTLIFTING", "WEIGHTS", "FREE_WEIGHTS", "POWERLIFTING": return "dumbbell.fill"
        case "YOGA", "PILATES", "STRETCHING": return "figure.yoga"
        case "HIIT", "CROSSFIT", "CIRCUIT_TRAINING", "TABATA_WORKOUT": return "bolt.heart.fill"
        default: return "figure.mixed.cardio"
        }
    }

    var minutes: Double? { (activeDurationS ?? durationS).map { $0 / 60 } }

    /// Running and walking pace, "5:24" per km.
    var pace: String? {
        guard ["figure.run", "figure.walk"].contains(symbol), let m = distanceM, m > 100, let mins = minutes, mins > 0 else { return nil }
        let seconds = Int((mins / (m / 1000) * 60).rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct StatTile: Identifiable {
    let title: String
    let value: String
    let icon: String
    var id: String { title }
}

private struct ZoneTime: Identifiable {
    let name: String
    let seconds: Double?
    var id: String { name }
}

struct WorkoutDetailView: View {
    let date: String
    let exerciseId: String
    @EnvironmentObject var model: AppModel

    private let grid = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let detail = model.dayDetails[date]
        let exercise = detail?.exercises.first { $0.id == exerciseId }
        ScrollView {
            VStack(spacing: 14) {
                if let exercise {
                    header(exercise)
                    statsGrid(exercise)
                    heartRateCard(exercise, hr: detail?.intraday?.hr)
                    zonesCard(exercise)
                    loadCard(exercise)
                } else if detail == nil {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    Card { EmptyStateView(icon: "questionmark", title: "Workout not found", message: "It may have been deleted in the Google Health app.") }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(exercise?.displayName ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadDay(date) }
    }

    private func header(_ x: Exercise) -> some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: x.symbol)
                    .font(.title2)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.strain.opacity(0.18)))
                    .foregroundStyle(Theme.strain)
                VStack(alignment: .leading, spacing: 4) {
                    Text(x.displayName).font(.title3.weight(.semibold))
                    Text("\(Format.longDay(date)) · \(timeRange(x))").font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func timeRange(_ x: Exercise) -> String {
        guard let start = Format.timestamp(x.startTime), let end = Format.timestamp(x.endTime) else { return "" }
        return "\(Format.time(start, zone: model.zone))–\(Format.time(end, zone: model.zone))"
    }

    private func statsGrid(_ x: Exercise) -> some View {
        var tiles = [StatTile(title: "Duration", value: Format.duration(x.minutes), icon: "clock")]
        if let s = x.strain { tiles.append(StatTile(title: "Strain", value: Format.number(s, decimals: 1), icon: "flame.fill")) }
        if let hr = x.avgHr { tiles.append(StatTile(title: "Average HR", value: "\(Int(hr)) bpm", icon: "heart")) }
        if let hr = x.hrMax { tiles.append(StatTile(title: "Max HR", value: "\(Int(hr)) bpm", icon: "arrow.up.heart")) }
        if let kcal = x.calories { tiles.append(StatTile(title: "Calories", value: "\(Format.number(kcal)) kcal", icon: "flame")) }
        if let m = x.distanceM, m > 0 { tiles.append(StatTile(title: "Distance", value: "\(Format.number(m / 1000, decimals: 2)) km", icon: "map")) }
        if let pace = x.pace { tiles.append(StatTile(title: "Pace", value: "\(pace) /km", icon: "speedometer")) }
        if let azm = x.azm, azm > 0 { tiles.append(StatTile(title: "Zone Minutes", value: Format.number(azm), icon: "heart.circle")) }
        if let steps = x.steps, steps > 0 { tiles.append(StatTile(title: "Steps", value: Format.number(steps), icon: "figure.walk")) }
        return LazyVGrid(columns: grid, spacing: 10) {
            ForEach(tiles) { t in
                MetricTile(title: t.title, value: t.value, icon: t.icon, color: Theme.strain)
            }
        }
    }

    /// The workout's minutes from the day's minute heart rate (local minutes in the server's time zone).
    private func minutes(_ x: Exercise, hr: [Int?]?) -> [MinuteValue] {
        guard let hr, let start = Format.timestamp(x.startTime), let end = Format.timestamp(x.endTime) else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = model.zone ?? .current
        let c = cal.dateComponents([.hour, .minute], from: start)
        let first = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let count = Int(end.timeIntervalSince(start) / 60)
        return (0..<max(0, count)).compactMap { i in
            let m = first + i
            guard m < hr.count, let bpm = hr[m] else { return nil }
            return MinuteValue(minute: i, value: Double(bpm))
        }
    }

    @ViewBuilder private func heartRateCard(_ x: Exercise, hr: [Int?]?) -> some View {
        let points = minutes(x, hr: hr)
        Card {
            SectionHeader(title: "Heart rate", subtitle: "Minute by minute, with your average")
            if points.count >= 2 {
                let avg = points.map(\.value).reduce(0, +) / Double(points.count)
                let lowest = points.map(\.value).min() ?? 0
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Minute", p.minute), yStart: .value("Base", lowest), yEnd: .value("BPM", p.value))
                            .foregroundStyle(LinearGradient(colors: [Theme.heart.opacity(0.35), Theme.heart.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Minute", p.minute), y: .value("BPM", p.value))
                            .foregroundStyle(Theme.heart)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(Theme.track)
                        AxisValueLabel {
                            if let m = value.as(Int.self) { Text("\(m) min").foregroundStyle(Theme.tertiary) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Theme.track)
                        AxisValueLabel().foregroundStyle(Theme.tertiary)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
            } else {
                Text("No minute heart rate for this workout.").font(.footnote).foregroundStyle(Theme.tertiary)
            }
        }
    }

    @ViewBuilder private func zonesCard(_ x: Exercise) -> some View {
        let hrr = (x.hrrZoneMin ?? []).map { $0 ?? 0 }
        let fitbit = [
            ZoneTime(name: "Light", seconds: x.zoneLightS), ZoneTime(name: "Moderate", seconds: x.zoneModerateS),
            ZoneTime(name: "Vigorous", seconds: x.zoneVigorousS), ZoneTime(name: "Peak", seconds: x.zonePeakS),
        ]
        if hrr.count == 5 || fitbit.contains(where: { $0.seconds != nil }) {
            Card {
                if hrr.count == 5 {
                    SectionHeader(title: "Heart-rate reserve zones", subtitle: "Minutes at 50–60, 60–70, 70–80, 80–90 and 90%+ of your reserve")
                    ZoneBars(minutes: hrr)
                }
                if fitbit.contains(where: { $0.seconds != nil }) {
                    if hrr.count == 5 { Divider().overlay(Theme.track) }
                    SectionHeader(title: "Fitbit zones")
                    ForEach(fitbit) { zone in
                        KeyValueRow(key: zone.name, value: Format.duration(zone.seconds.map { $0 / 60 }))
                    }
                }
            }
        }
    }

    @ViewBuilder private func loadCard(_ x: Exercise) -> some View {
        if let strain = x.strain, let trimp = x.trimp {
            let dayTrimp = model.daysByDate[date]?.double("trimp")
            Card {
                SectionHeader(title: "Training load")
                KeyValueRow(key: "Workout strain", value: Format.number(strain, decimals: 1))
                KeyValueRow(key: "TRIMP", value: Format.number(trimp))
                if let dayTrimp, dayTrimp > 0 {
                    KeyValueRow(key: "Share of the day's load", value: "\(Int((min(1, trimp / dayTrimp) * 100).rounded()))%")
                }
                Text("Workout strain is what this workout alone scores on the 0–100 day scale. Strain does not add up, so the day's strain is computed from the whole day's TRIMP.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }
}
