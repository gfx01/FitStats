import Foundation

/// Tonight's sleep need and bedtime. The same rule as the server's coach context
/// (supabase/functions/fitstats/lib/planner.ts); keep the two in step.
///
///     need    = your sleep need
///             + 0–45 min for today's strain (0 at strain 35 or less, 45 at 85 or more)
///             + a quarter of the last 7 nights' sleep debt (at most 60 min; naps on the
///               days before today count as sleep)
///             − today's naps (at most 60 min)
///     in bed  = need ÷ your typical sleep efficiency (median of the last 14 nights, else 90 %)
///     bedtime = the wake-up time you set for tomorrow (Settings → Wake-up times), else
///               your usual wake time for tomorrow's kind of day (weekday or weekend,
///               median of the last 28 nights) − time in bed
///
/// Extras, time in bed and bedtime are rounded to 5 minutes.
struct SleepPlan: Equatable {
    enum WakeBasis: String {
        /// The wake-up time set by hand for tomorrow.
        case set
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
    static func weekdayIndex(_ ymd: String) -> Int {
        guard let d = Format.date(ymd) else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Format.utc
        return (cal.component(.weekday, from: d) + 5) % 7
    }

    /// `wakeTimes`: the ones set by hand, Monday first (see UserSettings.wakeTimes).
    static func plan(days: [String: DayRecord], today: String, sleepNeedMin: Double, wakeTimes: [Int?]? = nil) -> SleepPlan {
        let todayRow = days[today]
        let strain = todayRow?.double("strain") ?? 0
        let strainMin = to5(45 * min(1, max(0, (strain - 35) / 50)))

        // Today's naps come off only through napMin below, so they are not counted twice.
        var debt = 0.0
        for offset in 0...6 {
            let row = days[Format.addDays(today, -offset)]
            if let asleep = row?.double("sleep_asleep_min") {
                let naps = offset > 0 ? (row?.double("nap_min") ?? 0) : 0
                debt += max(0, sleepNeedMin - asleep - naps)
            }
        }
        let debtMin = min(60, to5(debt / 4))
        let napMin = min(60, to5(todayRow?.double("nap_min") ?? 0))
        let needMin = sleepNeedMin + strainMin + debtMin - napMin

        let efficiencies = (0...13).compactMap { days[Format.addDays(today, -$0)]?.double("sleep_efficiency") }.filter { $0 > 0 }
        let efficiency = min(1, max(0.7, efficiencies.count >= minNights ? median(efficiencies)! : 0.9))
        let inBedMin = to5(needMin / efficiency)

        let tomorrow = weekdayIndex(Format.addDays(today, 1))
        var wake: Double?
        var basis: WakeBasis?
        if let times = wakeTimes, times.count == 7, let set = times[tomorrow] {
            wake = Double(set)
            basis = .set
        } else if let usual = usualWake(days: days, today: today, weekendMorning: tomorrow >= 5) {
            wake = usual.wakeMin
            basis = usual.basis
        }
        return SleepPlan(
            needMin: needMin, baseMin: sleepNeedMin, strainMin: strainMin, debtMin: debtMin, napMin: napMin,
            efficiency: efficiency, inBedMin: inBedMin,
            wakeMin: wake.map(jsRound), bedtimeMin: wake.map { to5($0 - inBedMin) }, wakeBasis: basis
        )
    }

    /// The usual wake time from the band for a weekday or a weekend morning: the median of that
    /// kind of the last 28 mornings up to `today`, else of all of them; nil under 3 mornings.
    static func usualWake(days: [String: DayRecord], today: String, weekendMorning: Bool) -> (wakeMin: Double, basis: WakeBasis)? {
        var sameKind: [Double] = [], all: [Double] = []
        for offset in 0...27 {
            let date = Format.addDays(today, -offset)
            guard let wake = days[date]?.double("sleep_waketime_min") else { continue }
            all.append(wake)
            if (weekdayIndex(date) >= 5) == weekendMorning { sameKind.append(wake) }
        }
        if sameKind.count >= minNights { return (median(sameKind)!, weekendMorning ? .weekend : .weekday) }
        if all.count >= minNights { return (median(all)!, .all) }
        return nil
    }
}
