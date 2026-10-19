import SwiftUI

enum TrainingRoute: Hashable {
    case routine(String)
    case log(String)
}

/// The Training tab: start a workout from a routine (or an empty one), the routines you keep
/// (yours and the coach's), and the history of what you logged here and what the band recorded.
struct TrainingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workout: ActiveWorkout
    @State private var editingRoutine: Routine?
    @State private var showAllHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let error = model.trainingError {
                        Banner(icon: "exclamationmark.triangle.fill", text: error, color: Theme.recoveryYellow, actionTitle: "OK") {
                            model.trainingError = nil
                        }
                    }
                    if let active = workout.log, !workout.presented { resumeCard(active) }
                    weekCard
                    AskCoachRow(prompts: [
                        ("sparkles", "Make me a routine", "Make me a routine for "),
                        ("checklist", "Review my last workout", "Review my last workout and tell me what to change next time."),
                        ("arrow.up.right", "How can I progress?", "How can I improve my training from here?"),
                    ])
                    routinesSection
                    historySection
                    if let stats = model.stats {
                        TrainingLoadCard(load: stats.load, today: stats.today)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .refreshable { await model.refreshTraining() }
            .screenBackground()
            .navigationTitle("Training")
            .swipeBackFromAnywhere()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editingRoutine = Routine.new() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New routine")
                        .accessibilityIdentifier("training-new-routine")
                }
            }
            .navigationDestination(for: TrainingRoute.self) { route in
                switch route {
                case .routine(let id): RoutineDetailView(routineID: id)
                case .log(let id): WorkoutLogDetailView(logID: id)
                }
            }
            .navigationDestination(for: DetailRoute.self) { DetailDestination(route: $0) }
            .sheet(item: $editingRoutine) { routine in
                RoutineEditorView(draft: routine).environmentObject(model)
            }
            .fullScreenCover(isPresented: $workout.presented) {
                WorkoutLoggerView().environmentObject(model).environmentObject(workout)
            }
        }
    }

    // MARK: sections

    private func resumeCard(_ active: WorkoutLog) -> some View {
        Button {
            workout.presented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "timer").font(.title3).foregroundStyle(Theme.strain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.editing ? "Editing \(active.name)" : "\(active.name) in progress")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("\(active.doneSetCount) sets done · tap to go back to it")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.strain.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("training-resume")
    }

    /// This week (Monday on): sessions logged, sets, and the band's workouts.
    private var weekCard: some View {
        let monday = Self.monday(of: model.today)
        let logs = model.workoutLogs.filter { $0.date >= monday }
        let band = model.bandWorkouts.filter { $0.date >= monday }
        let strain = model.days.filter { $0.date >= monday }.compactMap { $0.double("strain") }
        return Card {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "This week")
                Spacer()
                Button {
                    workout.start(WorkoutLog.start(from: nil, date: model.today, previous: model.workoutLogs))
                } label: {
                    Label("Empty workout", systemImage: "plus.circle.fill").font(.caption.weight(.semibold))
                }
                .disabled(workout.log != nil)
                .accessibilityIdentifier("training-start-empty")
            }
            HStack(alignment: .top) {
                stat("Logged", "\(logs.count)", logs.count == 1 ? "workout" : "workouts")
                Spacer()
                stat("Sets", "\(logs.reduce(0) { $0 + $1.doneSetCount })", "done")
                Spacer()
                stat("Band", "\(band.count)", band.count == 1 ? "workout" : "workouts")
                Spacer()
                stat("Avg strain", strain.isEmpty ? "–" : Format.number(strain.reduce(0, +) / Double(strain.count)), "a day")
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.number(22))
            Text(unit).font(.caption2).foregroundStyle(Theme.tertiary)
        }
    }

    @ViewBuilder private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Routines", subtitle: model.routines.isEmpty ? nil : "Tap one to see it or start it")
            if model.routines.isEmpty {
                Card {
                    EmptyStateView(icon: "list.bullet.clipboard", title: "No routines yet",
                                   message: "Make one with the + button, or ask the coach to make one for you.")
                }
            }
            ForEach(model.routines) { routine in
                NavigationLink(value: TrainingRoute.routine(routine.id)) {
                    RoutineCard(routine: routine, lastDone: model.workoutLogs.first { $0.routineId == routine.id }?.date)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("routine-\(routine.name)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What you logged here and what the band recorded, newest first.
    @ViewBuilder private var historySection: some View {
        let entries = HistoryEntry.merged(logs: model.workoutLogs, band: model.bandWorkouts)
        let shown = showAllHistory ? entries : Array(entries.prefix(8))
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "History", subtitle: "Logged here, and recorded by your band")
            if entries.isEmpty {
                Card {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: "No workouts yet",
                                   message: "Workouts you log here and the ones your band records show up here.")
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { item in
                            if item.offset > 0 { Divider().overlay(Theme.track).padding(.leading, 56) }
                            historyRow(item.element)
                        }
                    }
                }
                if entries.count > shown.count || showAllHistory {
                    Button(showAllHistory ? "Show fewer" : "Show all \(entries.count)") { showAllHistory.toggle() }
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func historyRow(_ entry: HistoryEntry) -> some View {
        switch entry {
        case .log(let log):
            NavigationLink(value: TrainingRoute.log(log.id)) {
                HistoryRow(icon: "dumbbell.fill", tint: Theme.strain, title: log.name, date: log.date,
                           detail: [log.minutes.map { Format.duration($0) }, "\(log.doneSetCount) sets",
                                    log.volumeKg.map { "\(Format.number($0)) kg" }].compactMap { $0 }.joined(separator: " · "),
                           badge: "Logged")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("history-log")
        case .band(let x):
            NavigationLink(value: DetailRoute.workout(x.date, x.id)) {
                HistoryRow(icon: "applewatch", tint: Theme.heart, title: x.displayName, date: x.date,
                           detail: [x.durationS.map { Format.duration($0 / 60) }, x.avgHr.map { "\(Int($0.rounded())) bpm" },
                                    x.strain.map { "strain \(Format.number($0))" }].compactMap { $0 }.joined(separator: " · "),
                           badge: "Band")
            }
            .buttonStyle(.plain)
        }
    }

    /// Monday of the week `ymd` is in.
    static func monday(of ymd: String) -> String {
        guard let d = Format.date(ymd) else { return ymd }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Format.utc
        let weekday = (cal.component(.weekday, from: d) + 5) % 7 // Monday = 0
        return Format.addDays(ymd, -weekday)
    }
}

enum HistoryEntry: Identifiable {
    case log(WorkoutLog)
    case band(Exercise)

    var id: String {
        switch self {
        case .log(let l): return "log-\(l.id)"
        case .band(let x): return "band-\(x.id)"
        }
    }

    private var sortKey: String {
        switch self {
        case .log(let l): return "\(l.date) \(l.startedAt ?? "")"
        case .band(let x): return "\(x.date) \(x.startTime)"
        }
    }

    static func merged(logs: [WorkoutLog], band: [Exercise]) -> [HistoryEntry] {
        (logs.map(HistoryEntry.log) + band.map(HistoryEntry.band)).sorted { $0.sortKey > $1.sortKey }
    }
}

struct HistoryRow: View {
    let icon: String
    let tint: Color
    let title: String
    let date: String
    let detail: String
    let badge: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                Text(detail.isEmpty ? Format.prettyDay(date, today: model.today) : "\(Format.prettyDay(date, today: model.today)) · \(detail)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct RoutineCard: View {
    let routine: Routine
    let lastDone: String?
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(routine.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                if routine.byCoach { CoachBadge() }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
            Text(routine.exercises.isEmpty ? "No exercises yet" : routine.exercises.prefix(4).map(\.name).joined(separator: " · ") + (routine.exercises.count > 4 ? " · +\(routine.exercises.count - 4)" : ""))
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
            Text(lastDone.map { "Last done \(Format.prettyDay($0, today: model.today).lowercasedIfDay)" } ?? "Not done yet")
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
        }
    }
}

struct CoachBadge: View {
    var body: some View {
        Label("Coach", systemImage: "sparkles")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.sleep)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.sleep.opacity(0.16)))
            .accessibilityLabel("Made by the coach")
    }
}

/// Buttons that open the Coach with a question about this part of the app in its message
/// field, ready to finish and send.
struct AskCoachRow: View {
    /// Icon, button title, the text put in the message field.
    let prompts: [(String, String, String)]
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(prompts.indices, id: \.self) { i in
                    let prompt = prompts[i]
                    Button { model.askCoach(prompt.2) } label: {
                        Label(prompt.1, systemImage: prompt.0)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.sleep.opacity(0.16)))
                            .foregroundStyle(Theme.sleep)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ask-coach-\(prompt.1)")
                }
            }
        }
    }
}

extension String {
    /// "Today" → "today", "Yesterday" → "yesterday"; other dates stay as they are.
    var lowercasedIfDay: String {
        self == "Today" || self == "Yesterday" ? lowercased() : self
    }
}
