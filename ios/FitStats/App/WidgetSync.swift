import Foundation
import WidgetKit

extension AppModel {
    /// Hands today's numbers, the week, tonight's bedtime, the coach's brief, this week's
    /// workouts and the app key to the Home Screen widgets, then redraws them. Called whenever the
    /// days load, the wake-up times change or a new brief arrives.
    func updateWidgets() {
        guard !isFixture else { return }
        guard let key = appKey else {
            SharedStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        SharedStore.saveKey(key)
        guard let snapshot = widgetSnapshot() else { return }
        if SharedStore.write(snapshot) { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// What the widgets show, from what the app has loaded; nil before today's row is there.
    /// Also used for the previews in Settings → Widgets.
    func widgetSnapshot() -> WidgetSnapshot? {
        let date = today
        guard let day = daysByDate[date] else { return nil }
        let plan = SleepPlan.plan(days: daysByDate, today: date,
                                  sleepNeedMin: Double(status?.settings.sleepNeedMin ?? 480), wakeTimes: wakeTimes)
        var s = WidgetSnapshot(date: date, updated: Date(), row: day.values.mapValues { $0.anyValue },
                               bedtimeMin: plan.bedtimeMin, bedtimeFor: plan.bedtimeMin == nil ? nil : date)
        let weekStart = Format.addDays(date, -6)
        s.week = WidgetSnapshot.week(rows: days.filter { $0.date >= weekStart }.map { $0.values.mapValues { $0.anyValue } }, today: date)
        s.stepGoal = Double(status?.settings.stepGoal ?? 10_000)
        s.rhrBaseline = MetricCatalog.def("rhr").flatMap { baseline($0, before: date) }
        s.hrvBaseline = MetricCatalog.def("hrv_rmssd").flatMap { baseline($0, before: date) }
        if let brief = coach.brief {
            s.coachText = brief.text
            s.coachDate = brief.date
        }
        s.coachName = coach.persona.name
        // This week's workouts: logged ones, plus the band's that aren't the same session.
        let monday = TrainingView.monday(of: date)
        let entries = HistoryEntry.merged(logs: workoutLogs, band: bandWorkouts, pairs: workoutPairs)
        let thisWeek = entries.filter { $0.date >= monday && $0.date <= date }
        s.workoutsThisWeek = thisWeek.count
        s.workoutDays = Array(Set(thisWeek.map(\.date))).sorted()
        s.workoutMinutesThisWeek = thisWeek.reduce(0) { total, entry in
            switch entry {
            case .log(let l): return total + (l.minutes ?? 0)
            case .band(let x): return total + (x.durationS ?? 0) / 60
            }
        }
        if let last = entries.first(where: { $0.date <= date }) {
            switch last {
            case .log(let l): s.lastWorkoutName = l.name
            case .band(let x): s.lastWorkoutName = x.displayName
            }
            s.lastWorkoutDate = last.date
        }
        return s
    }
}
