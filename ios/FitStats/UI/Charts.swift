import Charts
import SwiftUI

struct DayPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Daily values for one metric: bars for day totals, line for averages.
struct DailyMetricChart: View {
    let points: [DayPoint]
    let def: MetricDef
    var average: Double? = nil
    var color: Color
    var height: CGFloat = 200

    var body: some View {
        Chart {
            ForEach(points) { p in
                if def.isDayTotal {
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value(def.label, p.value))
                        .foregroundStyle(color.gradient)
                        .cornerRadius(3)
                } else {
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value(def.label, p.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                    if points.count <= 45 {
                        PointMark(x: .value("Day", p.date, unit: .day), y: .value(def.label, p.value))
                            .foregroundStyle(color)
                            .symbolSize(18)
                    }
                }
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(def.formatted(v, withUnit: false)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: def.isDayTotal))
        .frame(height: height)
    }
}

struct SparklineView: View {
    let values: [Double]
    var color: Color

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                LineMark(x: .value("i", item.offset), y: .value("v", item.element))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

struct MinuteValue: Identifiable {
    let minute: Int
    let value: Double
    var id: Int { minute }
}

/// Heart rate across one local day, averaged into 5-minute buckets.
struct HeartRateDayChart: View {
    let hr: [Int?]
    var rhr: Double? = nil
    var color: Color = Theme.heart
    var height: CGFloat = 170

    private var buckets: [MinuteValue] {
        var out: [MinuteValue] = []
        var m = 0
        while m < hr.count {
            let slice = hr[m..<min(m + 5, hr.count)].compactMap { $0 }
            if !slice.isEmpty {
                out.append(MinuteValue(minute: m, value: Double(slice.reduce(0, +)) / Double(slice.count)))
            }
            m += 5
        }
        return out
    }

    var body: some View {
        let data = buckets
        Chart {
            ForEach(data) { p in
                LineMark(x: .value("Time", p.minute), y: .value("BPM", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let rhr {
                RuleMark(y: .value("Resting", rhr))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: 0...1440)
        .chartXAxis {
            AxisMarks(values: [0, 360, 720, 1080, 1440]) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(String(format: "%02d:00", (m / 60) % 24)).foregroundStyle(Theme.tertiary)
                    }
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
        .frame(height: height)
    }
}

struct StageSegment: Identifiable {
    let id: Int
    let code: Int
    let start: Date
    let end: Date
    let level: Double
}

/// Sleep stages over the night (awake at the top, deep at the bottom).
struct HypnogramChart: View {
    let stages: [[Double]]
    var zone: TimeZone?

    private static func level(_ code: Int) -> Double {
        switch code {
        case 0: return 3
        case 3: return 2
        case 2: return 0
        default: return 1
        }
    }

    private var segments: [StageSegment] {
        stages.enumerated().compactMap { index, s in
            guard s.count >= 3 else { return nil }
            let code = Int(s[0])
            return StageSegment(
                id: index,
                code: code,
                start: Date(timeIntervalSince1970: s[1]),
                end: Date(timeIntervalSince1970: s[2]),
                level: Self.level(code)
            )
        }
    }

    var body: some View {
        let data = segments
        Chart {
            ForEach(data) { s in
                RectangleMark(
                    xStart: .value("Start", s.start),
                    xEnd: .value("End", s.end),
                    yStart: .value("Low", s.level + 0.1),
                    yEnd: .value("High", s.level + 0.9)
                )
                .foregroundStyle(Theme.stageColor(s.code))
                .cornerRadius(2)
            }
        }
        .chartYScale(domain: 0...4)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.5, 1.5, 2.5, 3.5]) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v < 1 ? "Deep" : v < 2 ? "Light" : v < 3 ? "REM" : "Awake")
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(Format.time(d, zone: zone)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .frame(height: 170)
    }
}

struct HourValue: Identifiable {
    let hour: Double
    let value: Double
    var id: Double { hour }
}

struct HourlyBarsChart: View {
    let values: [Double?]
    var colorFor: (Double) -> Color

    var body: some View {
        let data = values.enumerated().compactMap { i, v -> HourValue? in
            guard let v else { return nil }
            return HourValue(hour: Double(i), value: v)
        }
        Chart {
            ForEach(data) { h in
                BarMark(x: .value("Hour", h.hour), y: .value("Value", h.value), width: .fixed(9))
                    .foregroundStyle(colorFor(h.value))
                    .cornerRadius(2)
            }
        }
        .chartXScale(domain: -0.5...23.5)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: [0.0, 6.0, 12.0, 18.0, 23.0]) { value in
                AxisValueLabel {
                    if let h = value.as(Double.self) {
                        Text(String(format: "%02d", Int(h))).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel().foregroundStyle(Theme.tertiary)
            }
        }
        .frame(height: 150)
    }
}

struct WeekdayValue: Identifiable {
    let name: String
    let value: Double
    var id: String { name }
}

struct WeekdayChart: View {
    let values: [Double?]
    let def: MetricDef
    var color: Color

    var body: some View {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let data = values.enumerated().compactMap { i, v -> WeekdayValue? in
            guard let v, i < names.count else { return nil }
            return WeekdayValue(name: names[i], value: v)
        }
        Chart {
            ForEach(data) { d in
                BarMark(x: .value("Day", d.name), y: .value(def.label, d.value))
                    .foregroundStyle(color.gradient)
                    .cornerRadius(3)
            }
        }
        .chartXScale(domain: names)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(def.formatted(v, withUnit: false)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: def.isDayTotal))
        .frame(height: 140)
    }
}

struct TimedValue: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Overnight samples such as HRV or SpO₂ ([epochSeconds, value] pairs).
struct SamplesChart: View {
    let samples: [[Double]]
    var color: Color
    var zone: TimeZone?

    var body: some View {
        let data = samples.compactMap { s -> TimedValue? in
            guard s.count >= 2 else { return nil }
            return TimedValue(date: Date(timeIntervalSince1970: s[0]), value: s[1])
        }
        Chart {
            ForEach(data) { p in
                LineMark(x: .value("Time", p.date), y: .value("Value", p.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(Format.time(d, zone: zone)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel().foregroundStyle(Theme.tertiary)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 130)
    }
}

struct ScatterPoint: Identifiable {
    let id: Int
    let x: Double
    let y: Double
}

struct ScatterChart: View {
    let points: [ScatterPoint]
    let xDef: MetricDef
    let yDef: MetricDef
    var color: Color = Theme.stress

    var body: some View {
        Chart {
            ForEach(points) { p in
                PointMark(x: .value(xDef.label, p.x), y: .value(yDef.label, p.y))
                    .foregroundStyle(color.opacity(0.75))
                    .symbolSize(28)
            }
        }
        .chartXScale(domain: .automatic(includesZero: false))
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(xDef.formatted(v, withUnit: false)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(yDef.formatted(v, withUnit: false)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .frame(height: 240)
    }
}
