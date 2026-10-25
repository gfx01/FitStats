import Charts
import SwiftUI

/// Sleep: the last 14 nights as bars from falling asleep to waking up, so irregular nights stand
/// out, with the usual times (the middle night of the 14) as dashed lines, the wake-up times set
/// by hand as marks, and how much bedtimes and wake times varied.
struct BedtimeConsistencyCard: View {
    let endDate: String
    @EnvironmentObject private var model: AppModel

    private struct Night: Identifiable {
        let date: String
        /// Minutes from the wake-up day's midnight (negative = the evening before).
        let bed: Double
        let wake: Double
        let setWake: Double?
        var id: String { date }
    }

    private static let count = 14

    var body: some View {
        let nights = recentNights()
        if nights.count >= 3 {
            let beds = nights.map(\.bed).sorted(), wakes = nights.map(\.wake).sorted()
            let usualBed = Self.median(beds), usualWake = Self.median(wakes)
            Card {
                SectionHeader(title: "Bedtime consistency", subtitle: "Last \(Self.count) nights, asleep to awake")
                Chart {
                    ForEach(nights) { n in
                        BarMark(xStart: .value("Asleep", n.bed), xEnd: .value("Awake", n.wake), y: .value("Night", Format.shortDay(n.date)), height: .fixed(9))
                            .foregroundStyle(Theme.sleep.gradient)
                            .cornerRadius(4.5)
                        if let set = n.setWake {
                            PointMark(x: .value("Set wake-up", set), y: .value("Night", Format.shortDay(n.date)))
                                .symbol(.diamond)
                                .symbolSize(28)
                                .foregroundStyle(Theme.recoveryYellow)
                        }
                    }
                    RuleMark(x: .value("Usual bedtime", usualBed))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Theme.secondary)
                    RuleMark(x: .value("Usual wake time", usualWake))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Theme.secondary)
                }
                .chartXScale(domain: (beds.first! - 30)...(wakes.last! + 30))
                .chartXAxis {
                    AxisMarks(values: .stride(by: 120)) { value in
                        AxisGridLine().foregroundStyle(Theme.track)
                        AxisValueLabel { if let m = value.as(Double.self) { Text(Format.clock(m)).font(.caption2) } }
                    }
                }
                // Day labels left of the plot, so they never sit on the bars.
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in AxisValueLabel(horizontalSpacing: 6).font(.caption2) }
                }
                .frame(height: CGFloat(nights.count) * 18 + 30)
                Text(summary(beds: beds, wakes: wakes, usualBed: usualBed, usualWake: usualWake))
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    legend(Capsule().fill(Theme.sleep), "Asleep")
                    legend(Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Theme.secondary), "Usual times")
                    if nights.contains(where: { $0.setWake != nil }) {
                        legend(Image(systemName: "diamond.fill").font(.system(size: 7)).foregroundStyle(Theme.recoveryYellow), "Wake-up you set")
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bedtime-consistency")
        }
    }

    private func legend(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 4) {
            mark.frame(width: 10, height: 6)
            Text(text).font(.caption2).foregroundStyle(Theme.tertiary)
        }
    }

    /// The nights ending on the 14 days up to `endDate` that have both times.
    private func recentNights() -> [Night] {
        let times = model.wakeTimes
        return (0..<Self.count).reversed().compactMap { offset -> Night? in
            let date = Format.addDays(endDate, -offset)
            guard let day = model.daysByDate[date], let bed = day.double("sleep_bedtime_min"), let wake = day.double("sleep_waketime_min"), wake > bed else { return nil }
            let set = times.flatMap { $0[SleepPlan.weekdayIndex(date)] }.map(Double.init)
            return Night(date: date, bed: bed, wake: wake, setWake: set)
        }
    }

    /// "Usually asleep by 23:20 and up at 7:05. Bedtimes varied by about 35 min, wake times by 20 min."
    private func summary(beds: [Double], wakes: [Double], usualBed: Double, usualWake: Double) -> String {
        let bedSpread = Self.median(beds.map { abs($0 - usualBed) }).rounded()
        let wakeSpread = Self.median(wakes.map { abs($0 - usualWake) }).rounded()
        let verdict = max(bedSpread, wakeSpread) <= 30 ? "That's regular." : max(bedSpread, wakeSpread) <= 60 ? "Fairly regular." : "Quite irregular: a steadier bedtime tends to help."
        return "Usually asleep by \(Format.clock(usualBed)) and up at \(Format.clock(usualWake)). On a typical night, bedtime is \(Format.duration(bedSpread)) "
            + "from that and wake-up \(Format.duration(wakeSpread)). \(verdict)"
    }

    private static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
