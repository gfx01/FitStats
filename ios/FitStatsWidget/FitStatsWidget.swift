import SwiftUI
import WidgetKit

@main
struct FitStatsWidgets: WidgetBundle {
    var body: some Widget {
        ScoresWidget()
        SleepWidget()
    }
}

struct ScoresEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has shared anything (or the app group isn't working).
    let snapshot: WidgetSnapshot?
}

/// Today's numbers: the app's last copy, refreshed from the server every 30 minutes with the
/// app key the app shares, so steps and strain move without opening the app.
struct ScoresProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScoresEntry {
        ScoresEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScoresEntry) -> Void) {
        completion(ScoresEntry(date: Date(), snapshot: SharedStore.readSnapshot() ?? (context.isPreview ? .sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScoresEntry>) -> Void) {
        Task {
            var snapshot = SharedStore.readSnapshot()
            if let fresh = await WidgetFetch.today(previous: snapshot) {
                snapshot = fresh
                SharedStore.write(fresh)
            }
            let next = Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: [ScoresEntry(date: Date(), snapshot: snapshot)], policy: .after(next)))
        }
    }
}

enum WidgetFetch {
    /// Today's row from the `days` route, or nil without a key, offline, or within 10 minutes
    /// of the last update (the app updates the widget itself whenever it loads).
    static func today(previous: WidgetSnapshot?) async -> WidgetSnapshot? {
        if let previous, Date().timeIntervalSince(previous.updated) < 600 { return nil }
        guard let key = SharedStore.readKey(),
              let base = (Bundle.main.object(forInfoDictionaryKey: "FitStatsServerURL") as? String).flatMap(URL.init(string:)),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        // The account's day can differ from the phone's: ask for the days around it.
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let now = Date()
        components.queryItems = [
            URLQueryItem(name: "r", value: "days"),
            URLQueryItem(name: "from", value: f.string(from: now.addingTimeInterval(-86_400))),
            URLQueryItem(name: "to", value: f.string(from: now.addingTimeInterval(86_400))),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "x-app-key")
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let today = object["today"] as? String,
              let rows = object["days"] as? [[String: Any]],
              let row = rows.first(where: { $0["date"] as? String == today }) else { return nil }
        // Tonight's bedtime comes from the app's planner; keep it while it's for today.
        let bedtime = previous?.bedtimeFor == today ? previous?.bedtimeMin : nil
        return WidgetSnapshot(date: today, updated: now, row: row, bedtimeMin: bedtime, bedtimeFor: bedtime == nil ? nil : today)
    }
}

struct ScoresWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsScores", provider: ScoresProvider()) { entry in
            ScoresWidgetView(entry: entry)
        }
        .configurationDisplayName("Scores")
        .description("Recovery, strain and sleep for today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsSleep", provider: ScoresProvider()) { entry in
            SleepWidgetView(entry: entry)
        }
        .configurationDisplayName("Sleep")
        .description("Last night's sleep and when to be in bed tonight.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct ScoresWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.containerBackground(for: .widget) { WidgetBackground() }
    }

    @ViewBuilder private var content: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryCircular:
            Gauge(value: min(1, max(0, (s?.recovery ?? 0) / 100))) {
                Image(systemName: "bolt.heart.fill")
            } currentValueLabel: {
                Text(WidgetFormat.number(s?.recovery))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Recovery \(s?.recovery.map { WidgetFormat.number($0) + "%" } ?? "–")")
                    .font(.headline)
                    .widgetAccentable()
                Text("Strain \(WidgetFormat.number(s?.strain)) · Sleep \(WidgetFormat.duration(s?.sleepMin))")
                    .font(.caption)
                Text("\(WidgetFormat.number(s?.steps)) steps").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text("\(s?.recovery.map { WidgetFormat.number($0) + "%" } ?? "–") recovery · \(WidgetFormat.duration(s?.sleepMin)) sleep")
        case .systemMedium:
            if let s { WidgetScoresMedium(snapshot: s) } else { WidgetEmptyFace() }
        default:
            if let s { WidgetScoresSmall(snapshot: s) } else { WidgetEmptyFace(compact: true) }
        }
    }
}

struct SleepWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.containerBackground(for: .widget) { WidgetBackground() }
    }

    @ViewBuilder private var content: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Slept \(WidgetFormat.duration(s?.sleepMin))").font(.headline).widgetAccentable()
                Text(s?.sleepScore.map { "Score \(WidgetFormat.number($0))" } ?? "No score yet").font(.caption)
                if let bed = s?.tonightBedtime {
                    Text("In bed by \(WidgetFormat.clock(bed))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            if let s { WidgetSleepSmall(snapshot: s) } else { WidgetEmptyFace(compact: true) }
        }
    }
}
