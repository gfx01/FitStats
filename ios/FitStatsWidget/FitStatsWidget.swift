import SwiftUI
import WidgetKit

@main
struct FitStatsWidgets: WidgetBundle {
    var body: some Widget {
        ScoresWidget()
        SleepWidget()
        TodayWidget()
        StepsWidget()
        HeartWidget()
        StressWidget()
        WeekWidget()
        CoachWidget()
        TrainingWidget()
    }
}

struct ScoresEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has shared anything (or the app group isn't working).
    let snapshot: WidgetSnapshot?
}

/// Today's numbers: the app's last copy, refreshed from the server every 30 minutes with the
/// app key the app shares, so steps and strain move without opening the app. Every widget uses
/// this one provider.
struct ScoresProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScoresEntry {
        ScoresEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScoresEntry) -> Void) {
        completion(ScoresEntry(date: Date(), snapshot: SharedStore.readSnapshot() ?? (context.isPreview ? .sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScoresEntry>) -> Void) {
        Task {
            let snapshot = await WidgetFetch.refreshed()
            let next = Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: [ScoresEntry(date: Date(), snapshot: snapshot)], policy: .after(next)))
        }
    }
}

enum WidgetFetch {
    private static let lock = NSLock()
    private static var inFlight: Task<WidgetSnapshot?, Never>?

    /// The shared snapshot, refreshed from the server first when it's due. The widgets ask at
    /// about the same time; they share one request.
    static func refreshed() async -> WidgetSnapshot? {
        lock.lock()
        if let running = inFlight {
            lock.unlock()
            return await running.value
        }
        let task = Task { () -> WidgetSnapshot? in
            var snapshot = SharedStore.readSnapshot()
            if let fresh = await today(previous: snapshot) {
                snapshot = fresh
                SharedStore.write(fresh)
            }
            return snapshot
        }
        inFlight = task
        lock.unlock()
        let result = await task.value
        lock.lock()
        inFlight = nil
        lock.unlock()
        return result
    }

    /// Today's row and the week from the `days` route, or nil without a key, offline, or within
    /// 10 minutes of the last update (the app updates the widgets itself whenever it loads).
    static func today(previous: WidgetSnapshot?) async -> WidgetSnapshot? {
        if let previous, Date().timeIntervalSince(previous.updated) < 600 { return nil }
        guard let key = SharedStore.readKey(),
              let base = (Bundle.main.object(forInfoDictionaryKey: "FitStatsServerURL") as? String).flatMap(URL.init(string:)),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        // The account's day can differ from the phone's: ask for a little more than the week.
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let now = Date()
        components.queryItems = [
            URLQueryItem(name: "r", value: "days"),
            URLQueryItem(name: "from", value: f.string(from: now.addingTimeInterval(-8 * 86_400))),
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
        var snapshot = WidgetSnapshot(date: today, updated: now, row: row)
        snapshot.week = WidgetSnapshot.week(rows: rows, today: today)
        snapshot.keepAppFields(from: previous)
        return snapshot
    }
}

/// Where a tap on a widget takes you in the app (AppModel.handleCallback).
enum WidgetLink {
    static func tab(_ name: String) -> URL { URL(string: "fitstats://open?tab=\(name)")! }
}

/// The common frame: the widget's face (or the "open the app" face) on the dark background.
struct WidgetShell<Face: View>: View {
    let entry: ScoresEntry
    var tab = "today"
    var compact = true
    @ViewBuilder let face: (WidgetSnapshot) -> Face

    var body: some View {
        Group {
            if let s = entry.snapshot { face(s) } else { WidgetEmptyFace(compact: compact) }
        }
        .widgetURL(WidgetLink.tab(tab))
        .containerBackground(for: .widget) { WidgetBackground() }
    }
}

// MARK: - Scores and Sleep

struct ScoresWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsScores", provider: ScoresProvider()) { entry in
            ScoresWidgetView(entry: entry)
        }
        .configurationDisplayName("Scores")
        .description("Recovery, strain and sleep for today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsSleep", provider: ScoresProvider()) { entry in
            SleepWidgetView(entry: entry)
        }
        .configurationDisplayName("Sleep")
        .description("Last night's sleep, its stages, the week and when to be in bed tonight.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ScoresWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryCircular:
            Gauge(value: min(1, max(0, (s?.recovery ?? 0) / 100))) {
                Image(systemName: "bolt.heart.fill")
            } currentValueLabel: {
                Text(WidgetFormat.number(s?.recovery))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessory(entry)
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
            .accessory(entry)
        case .accessoryInline:
            Text("\(s?.recovery.map { WidgetFormat.number($0) + "%" } ?? "–") recovery · \(WidgetFormat.duration(s?.sleepMin)) sleep")
                .accessory(entry)
        case .systemMedium:
            WidgetShell(entry: entry, compact: false) { WidgetScoresMedium(snapshot: $0) }
        case .systemLarge:
            WidgetShell(entry: entry, compact: false) { WidgetScoresLarge(snapshot: $0) }
        default:
            WidgetShell(entry: entry) { WidgetScoresSmall(snapshot: $0) }
        }
    }
}

struct SleepWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
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
            .accessory(entry)
        case .accessoryCircular:
            Gauge(value: min(1, max(0, (s?.sleepScore ?? 0) / 100))) {
                Image(systemName: "moon.fill")
            } currentValueLabel: {
                Text(WidgetFormat.number(s?.sleepScore))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessory(entry)
        case .accessoryInline:
            Text("\(WidgetFormat.duration(s?.sleepMin)) sleep\(s?.tonightBedtime.map { " · bed \(WidgetFormat.clock($0))" } ?? "")")
                .accessory(entry)
        case .systemMedium:
            WidgetShell(entry: entry, compact: false) { WidgetSleepMedium(snapshot: $0) }
        case .systemLarge:
            WidgetShell(entry: entry, compact: false) { WidgetSleepLarge(snapshot: $0) }
        default:
            WidgetShell(entry: entry) { WidgetSleepSmall(snapshot: $0) }
        }
    }
}

// MARK: - The rest

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsToday", provider: ScoresProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Your scores, steps, heart, stress, tonight's bedtime and the week, all in one.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemMedium {
            WidgetShell(entry: entry, compact: false) { WidgetTodayMedium(snapshot: $0) }
        } else {
            WidgetShell(entry: entry, compact: false) { WidgetTodayLarge(snapshot: $0) }
        }
    }
}

struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsSteps", provider: ScoresProvider()) { entry in
            StepsWidgetView(entry: entry)
        }
        .configurationDisplayName("Steps")
        .description("Today's steps against your goal, and the week's.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StepsWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        let goal = s?.stepGoal ?? 10_000
        switch family {
        case .accessoryCircular:
            Gauge(value: min(1, max(0, (s?.steps ?? 0) / max(goal, 1)))) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(WidgetFormat.compact(s?.steps ?? 0))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessory(entry)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(WidgetFormat.number(s?.steps)) steps").font(.headline).widgetAccentable()
                Gauge(value: min(1, max(0, (s?.steps ?? 0) / max(goal, 1)))) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                Text("Goal \(WidgetFormat.number(goal))").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessory(entry)
        case .accessoryInline:
            Text("\(WidgetFormat.number(s?.steps)) of \(WidgetFormat.compact(goal)) steps").accessory(entry)
        case .systemMedium:
            WidgetShell(entry: entry, compact: false) { WidgetStepsMedium(snapshot: $0) }
        default:
            WidgetShell(entry: entry) { WidgetStepsSmall(snapshot: $0) }
        }
    }
}

struct HeartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsHeart", provider: ScoresProvider()) { entry in
            HeartWidgetView(entry: entry)
        }
        .configurationDisplayName("Heart")
        .description("Resting heart rate and HRV against your usual.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct HeartWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryCircular:
            // Resting heart rate on a 40–100 bpm scale.
            Gauge(value: min(1, max(0, ((s?.rhr ?? 40) - 40) / 60))) {
                Image(systemName: "heart.fill")
            } currentValueLabel: {
                Text(WidgetFormat.number(s?.rhr))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessory(entry)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Resting \(WidgetFormat.number(s?.rhr)) bpm").font(.headline).widgetAccentable()
                Text("HRV \(WidgetFormat.number(s?.hrv)) ms").font(.caption)
                if let base = s?.rhrBaseline {
                    Text("Usual \(WidgetFormat.number(base)) bpm").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessory(entry)
        case .systemMedium:
            WidgetShell(entry: entry, compact: false) { WidgetHeartMedium(snapshot: $0) }
        default:
            WidgetShell(entry: entry) { WidgetHeartSmall(snapshot: $0) }
        }
    }
}

struct StressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsStress", provider: ScoresProvider()) { entry in
            StressWidgetView(entry: entry)
        }
        .configurationDisplayName("Stress")
        .description("Today's stress score, and the week's.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct StressWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let stress = entry.snapshot?.stress
        switch family {
        case .accessoryCircular:
            Gauge(value: min(1, max(0, (stress ?? 0) / 100))) {
                Image(systemName: "waveform.path.ecg")
            } currentValueLabel: {
                Text(WidgetFormat.number(stress))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessory(entry)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Stress \(WidgetFormat.number(stress))").font(.headline).widgetAccentable()
                Text(Theme.stressLabel(stress)).font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessory(entry)
        case .systemMedium:
            WidgetShell(entry: entry, compact: false) { WidgetStressMedium(snapshot: $0) }
        default:
            WidgetShell(entry: entry) { WidgetStressSmall(snapshot: $0) }
        }
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsWeek", provider: ScoresProvider()) { entry in
            WeekWidgetView(entry: entry)
        }
        .configurationDisplayName("Week")
        .description("Recovery and sleep over the last 7 days; strain and steps too in the large size.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct WeekWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemLarge {
            WidgetShell(entry: entry, tab: "trends", compact: false) { WidgetWeekLarge(snapshot: $0) }
        } else {
            WidgetShell(entry: entry, tab: "trends", compact: false) { WidgetWeekMedium(snapshot: $0) }
        }
    }
}

struct CoachWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsCoach", provider: ScoresProvider()) { entry in
            CoachWidgetView(entry: entry)
        }
        .configurationDisplayName("Coach")
        .description("Today's brief from your coach. Tap to open the chat.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CoachWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            WidgetShell(entry: entry, tab: "coach") { WidgetCoachFace(snapshot: $0, lines: 6, font: .caption) }
        case .systemLarge:
            WidgetShell(entry: entry, tab: "coach", compact: false) { WidgetCoachFace(snapshot: $0, lines: 16) }
        default:
            WidgetShell(entry: entry, tab: "coach", compact: false) { WidgetCoachFace(snapshot: $0, lines: 5) }
        }
    }
}

struct TrainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FitStatsTraining", provider: ScoresProvider()) { entry in
            TrainingWidgetView(entry: entry)
        }
        .configurationDisplayName("Training")
        .description("Workouts this week and your latest one.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TrainingWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(s?.workoutsThisWeek ?? 0) workouts this week").font(.headline).widgetAccentable()
                if let name = s?.lastWorkoutName {
                    Text("Last: \(name)").font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(WidgetLink.tab("training"))
            .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            WidgetShell(entry: entry, tab: "training", compact: false) { WidgetTrainingMedium(snapshot: $0) }
        default:
            WidgetShell(entry: entry, tab: "training") { WidgetTrainingSmall(snapshot: $0) }
        }
    }
}

private extension View {
    /// Lock Screen widgets: no background of their own, and a tap opens Today.
    func accessory(_ entry: ScoresEntry) -> some View {
        widgetURL(WidgetLink.tab("today")).containerBackground(for: .widget) { Color.clear }
    }
}
