import Foundation
import WidgetKit

extension AppModel {
    /// Hands today's numbers, tonight's bedtime and the app key to the Home Screen widgets, then
    /// redraws them. Called whenever the days load or the wake-up times change.
    func updateWidgets() {
        guard !isFixture else { return }
        guard let key = appKey else {
            SharedStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        SharedStore.saveKey(key)
        let date = today
        guard let day = daysByDate[date] else { return }
        let plan = SleepPlan.plan(days: daysByDate, today: date,
                                  sleepNeedMin: Double(status?.settings.sleepNeedMin ?? 480), wakeTimes: wakeTimes)
        let row = day.values.mapValues { $0.anyValue }
        let snapshot = WidgetSnapshot(date: date, updated: Date(), row: row, bedtimeMin: plan.bedtimeMin,
                                      bedtimeFor: plan.bedtimeMin == nil ? nil : date)
        if SharedStore.write(snapshot) { WidgetCenter.shared.reloadAllTimelines() }
    }
}
