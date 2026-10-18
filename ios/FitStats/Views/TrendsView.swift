import SwiftUI

struct TrendsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let stats = model.stats {
                        Text("\(stats.dayCount) days of data since \(Format.shortDay(stats.firstDate))")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
                    ForEach(MetricCategory.allCases) { category in
                        let defs = MetricCatalog.all.filter { $0.category == category && hasData($0) }
                        if !defs.isEmpty {
                            Card(padding: 8) {
                                SectionHeader(title: category.title).padding([.top, .horizontal], 8)
                                ForEach(defs) { def in
                                    NavigationLink(value: DetailRoute.metric(def.key)) {
                                        MetricRow(def: def)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("metric-\(def.key)")
                                }
                            }
                        }
                    }
                    if model.days.isEmpty {
                        Card {
                            EmptyStateView(icon: "chart.xyaxis.line", title: "No data yet",
                                           message: "Trends appear after the first sync finishes.")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .refreshable { await model.refreshAll(force: true) }
            .screenBackground()
            .navigationTitle("Trends")
            .navigationDestination(for: DetailRoute.self) { DetailDestination(route: $0) }
        }
    }

    private func hasData(_ def: MetricDef) -> Bool {
        if let n = model.stats?.metrics[def.key]?.ranges["all"]?.n { return n > 0 }
        return model.days.contains { def.value($0) != nil }
    }
}

private struct MetricRow: View {
    let def: MetricDef
    @EnvironmentObject var model: AppModel

    var body: some View {
        let stats = model.stats?.metrics[def.key]
        let recent = model.series(def, from: Format.addDays(model.today, -29), through: model.today).map(\.value)
        HStack(spacing: 12) {
            Image(systemName: def.icon)
                .font(.subheadline)
                .frame(width: 32, height: 32)
                .background(Circle().fill(def.category.color.opacity(0.16)))
                .foregroundStyle(def.category.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(def.label).font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(def.formatted(stats?.ranges["30"]?.mean))
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                    Text("30d avg").font(.caption2).foregroundStyle(Theme.tertiary)
                }
            }
            Spacer(minLength: 8)
            if recent.count >= 3 {
                SparklineView(values: recent, color: def.category.color).frame(width: 70, height: 26)
            }
            DeltaBadge(change: stats?.ranges["30"]?.changePct, better: def.better)
                .frame(minWidth: 44, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

struct MetricDetailView: View {
    let def: MetricDef
    @EnvironmentObject var model: AppModel
    @State var range = "30"

    private struct RangeOption: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    private let ranges = [
        RangeOption(key: "7", label: "7D"), RangeOption(key: "30", label: "30D"), RangeOption(key: "90", label: "90D"),
        RangeOption(key: "365", label: "1Y"), RangeOption(key: "all", label: "All"),
    ]

    var body: some View {
        let stats = model.stats?.metrics[def.key]
        let rs = stats?.ranges[range]
        let from: String = {
            if let days = Int(range) { return Format.addDays(model.today, -(days - 1)) }
            return model.days.first?.date ?? Format.addDays(model.today, -365)
        }()
        let points = model.series(def, from: from, through: model.today)
        ScrollView {
            VStack(spacing: 14) {
                Picker("Range", selection: $range) {
                    ForEach(ranges) { Text($0.label).tag($0.key) }
                }
                .pickerStyle(.segmented)

                Card {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Average").font(.caption).foregroundStyle(Theme.secondary)
                            Text(def.formatted(rs?.mean)).font(Theme.number(30))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            DeltaBadge(change: rs?.changePct, better: def.better)
                            if let prev = rs?.prevMean {
                                Text("prev. \(def.formatted(prev))").font(.caption2).foregroundStyle(Theme.tertiary)
                            }
                        }
                    }
                    if points.count >= 2 {
                        DailyMetricChart(points: points, def: def, average: rs?.mean, color: def.category.color, height: 220)
                    } else {
                        Text("Not enough data in this range yet.").font(.footnote).foregroundStyle(Theme.tertiary)
                    }
                }

                if let rs { statsCard(rs) }

                if let weekday = stats?.weekday, weekday.contains(where: { $0 != nil }) {
                    Card {
                        SectionHeader(title: "By weekday", subtitle: "Last 90 days")
                        WeekdayChart(values: weekday, def: def, color: def.category.color)
                    }
                }

                if stats?.best != nil || stats?.worst != nil {
                    Card {
                        SectionHeader(title: "Records")
                        if let best = stats?.best {
                            KeyValueRow(key: "Best · \(Format.shortDay(best.date))", value: def.formatted(best.value), color: Theme.recoveryGreen)
                        }
                        if let worst = stats?.worst {
                            KeyValueRow(key: "Worst · \(Format.shortDay(worst.date))", value: def.formatted(worst.value), color: Theme.recoveryRed)
                        }
                    }
                }

                if def.isDayTotal {
                    Text("Today is excluded from these numbers until the day is over.")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(def.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statsCard(_ rs: RangeStats) -> some View {
        Card {
            SectionHeader(title: "Statistics", subtitle: "\(rs.n) days with data")
            KeyValueRow(key: "Median", value: def.formatted(rs.median))
            KeyValueRow(key: "Lowest · \(Format.shortDay(rs.minDate))", value: def.formatted(rs.min))
            KeyValueRow(key: "Highest · \(Format.shortDay(rs.maxDate))", value: def.formatted(rs.max))
            if let sd = rs.sd {
                KeyValueRow(key: "Variability (SD)", value: def.format == .clock ? Format.duration(sd) : def.formatted(sd))
            }
            if let sum = rs.sum {
                KeyValueRow(key: "Total", value: def.formatted(sum))
            }
            if let slope = rs.slopePerWeek {
                KeyValueRow(key: "Trend per week", value: trendText(slope))
            }
        }
    }

    private func trendText(_ slope: Double) -> String {
        switch def.format {
        case .duration, .clock:
            return (slope >= 0 ? "+" : "−") + Format.duration(abs(slope))
        case .percent:
            return Format.signed(slope, decimals: 1) + " pts"
        case .number:
            let unit = def.unit.isEmpty ? "" : " \(def.unit)"
            return Format.signed(slope, decimals: max(def.decimals, 1)) + unit
        }
    }
}
