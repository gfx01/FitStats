import Foundation

/// Tonight's sleep need and bedtime. The same rule as the server's coach context
/// (supabase/functions/fitstats/lib/planner.ts); keep the two in step.
///
///     need    = your sleep need
///             + 0–45 min for today's strain (0 at strain 35 or less, 45 at 85 or more)
///             + a quarter of the last 7 nights' sleep debt (at most 60 min)
///             − today's naps (at most 60 min)
///     in bed  = need ÷ your typical sleep efficiency (median of the last 14 nights, else 90 %)
///     bedtime = your usual wake time for tomorrow's kind of day (weekday or weekend,
///               median of the last 28 nights) − time in bed
///
/// Extras, time in bed and bedtime are rounded to 5 minutes.
struct SleepPlan: Equatable {
    enum WakeBasis: String {
        case weekday, weekend, all
    }

    let needMin: Double
    let baseMin: Double
    let strainMin: Double
    let debtMin: Double
    let napMin: Double
    let efficiency: Double
    let inBedMin: Double
    /// Minutes from local midnight; nil without enough recent wake times.
    let wakeMin: Double?
    /// Minutes from tomorrow's local midnight (negative = this evening).
    let bedtimeMin: Double?
    let wakeBasis: WakeBasis?

    private static let minNights = 3

    /// Like JavaScript's Math.round (halves go up), so both sides agree on negative bedtimes.
    private static func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

    private static func to5(_ v: Double) -> Double { jsRound(v / 5) * 5 }

    private static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// Monday = 0 … Sunday = 6, like the server.
    private static func weekdayIndex(_ ymd: String) -> Int {
        guard let d = Format.date(ymd) else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Format.utc
        return (cal.component(.weekday, from: d) + 5) % 7
    }

    static func plan(days: [String: DayRecord], today: String, sleepNeedMin: Double) -> SleepPlan {
        let todayRow = days[today]
        let strain = todayRow?.double("strain") ?? 0
        let strainMin = to5(45 * min(1, max(0, (strain - 35) / 50)))

        var debt = 0.0
        for offset in 0...6 {
            if let asleep = days[Format.addDays(today, -offset)]?.double("sleep_asleep_min") {
                debt += max(0, sleepNeedMin - asleep)
            }
        }
        let debtMin = min(60, to5(debt / 4))
        let napMin = min(60, to5(todayRow?.double("nap_min") ?? 0))
        let needMin = sleepNeedMin + strainMin + debtMin - napMin

        let efficiencies = (0...13).compactMap { days[Format.addDays(today, -$0)]?.double("sleep_efficiency") }.filter { $0 > 0 }
        let efficiency = min(1, max(0.7, efficiencies.count >= minNights ? median(efficiencies)! : 0.9))
        let inBedMin = to5(needMin / efficiency)

        let weekend: (String) -> Bool = { weekdayIndex($0) >= 5 }
        let tomorrowWeekend = weekend(Format.addDays(today, 1))
        var sameKind: [Double] = [], all: [Double] = []
        for offset in 0...27 {
            let date = Format.addDays(today, -offset)
            guard let wake = days[date]?.double("sleep_waketime_min") else { continue }
            all.append(wake)
            if weekend(date) == tomorrowWeekend { sameKind.append(wake) }
        }
        var wake: Double?
        var basis: WakeBasis?
        if sameKind.count >= minNights {
            wake = median(sameKind)
            basis = tomorrowWeekend ? .weekend : .weekday
        } else if all.count >= minNights {
            wake = median(all)
            basis = .all
        }
        return SleepPlan(
            needMin: needMin, baseMin: sleepNeedMin, strainMin: strainMin, debtMin: debtMin, napMin: napMin,
            efficiency: efficiency, inBedMin: inBedMin,
            wakeMin: wake.map(jsRound), bedtimeMin: wake.map { to5($0 - inBedMin) }, wakeBasis: basis
        )
    }
}
