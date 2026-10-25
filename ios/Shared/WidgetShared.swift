import Foundation

/// What the Home Screen widgets show: today's scores, written by the app and refreshed by the
/// widget itself from the server. Built into both the app and the widget extension.
struct WidgetSnapshot: Codable, Equatable {
    /// The day the numbers are for (yyyy-MM-dd in the account's time zone).
    var date: String
    var updated: Date
    var recovery: Double?
    var strain: Double?
    var strainTarget: [Double]?
    var sleepScore: Double?
    var sleepMin: Double?
    var steps: Double?
    var stress: Double?
    var rhr: Double?
    /// Tonight's "In bed by" (minutes from the next midnight, negative = before it), from the
    /// app's sleep planner, for the evening of `bedtimeFor`.
    var bedtimeMin: Double?
    var bedtimeFor: String?
    var hrv: Double?
    var activeCalories: Double?
    /// Last night's stages (minutes).
    var deepMin: Double?
    var remMin: Double?
    var lightMin: Double?
    var awakeMin: Double?
    /// The last 7 days, oldest first, ending with `date`.
    var week: [WidgetDay]?

    // Known only to the app; the widget's own refresh keeps them (keepAppFields).
    var stepGoal: Double?
    /// 30-day averages before today.
    var rhrBaseline: Double?
    var hrvBaseline: Double?
    /// Today's brief from the coach, for the day in `coachDate`.
    var coachText: String?
    var coachDate: String?
    var coachName: String?
    /// Workouts this week (Monday on) and the latest one.
    var workoutsThisWeek: Int?
    var workoutMinutesThisWeek: Double?
    var lastWorkoutName: String?
    var lastWorkoutDate: String?
    /// Days this week with a workout.
    var workoutDays: [String]?

    /// From a day row of the `days` route (JSON numbers by key).
    init(date: String, updated: Date, row: [String: Any], bedtimeMin: Double? = nil, bedtimeFor: String? = nil) {
        func num(_ key: String) -> Double? { (row[key] as? NSNumber)?.doubleValue }
        self.date = date
        self.updated = updated
        recovery = num("recovery")
        strain = num("strain")
        sleepScore = num("sleep_score")
        sleepMin = num("sleep_asleep_min")
        steps = num("steps")
        stress = num("stress")
        rhr = num("rhr")
        hrv = num("hrv_rmssd")
        activeCalories = num("calories_active")
        deepMin = num("sleep_deep_min")
        remMin = num("sleep_rem_min")
        lightMin = num("sleep_light_min")
        awakeMin = num("sleep_awake_min")
        let target = ((row["score_details"] as? [String: Any])?["strainTarget"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue }
        strainTarget = target?.count == 2 ? target : nil
        self.bedtimeMin = bedtimeMin
        self.bedtimeFor = bedtimeFor
    }

    /// The 7 days ending `today` from day rows (missing days stay empty).
    static func week(rows: [[String: Any]], today: String) -> [WidgetDay] {
        let byDate = Dictionary(rows.compactMap { r in (r["date"] as? String).map { ($0, r) } }, uniquingKeysWith: { _, b in b })
        return (0..<7).reversed().map { offset in
            let date = WidgetDay.addDays(today, -offset)
            let r = byDate[date] ?? [:]
            func num(_ key: String) -> Double? { (r[key] as? NSNumber)?.doubleValue }
            return WidgetDay(date: date, recovery: num("recovery"), sleepMin: num("sleep_asleep_min"), strain: num("strain"),
                             steps: num("steps"), stress: num("stress"))
        }
    }

    /// After the widget's own refresh: the parts only the app knows, while they still apply.
    mutating func keepAppFields(from old: WidgetSnapshot?) {
        guard let old else { return }
        stepGoal = old.stepGoal
        if old.date == date {
            rhrBaseline = old.rhrBaseline
            hrvBaseline = old.hrvBaseline
            workoutsThisWeek = old.workoutsThisWeek
            workoutMinutesThisWeek = old.workoutMinutesThisWeek
            workoutDays = old.workoutDays
        }
        if old.bedtimeFor == date {
            bedtimeMin = old.bedtimeMin
            bedtimeFor = old.bedtimeFor
        }
        coachText = old.coachText
        coachDate = old.coachDate
        coachName = old.coachName
        lastWorkoutName = old.lastWorkoutName
        lastWorkoutDate = old.lastWorkoutDate
    }

    /// For previews and the widget gallery.
    static let sample: WidgetSnapshot = {
        var s = WidgetSnapshot(date: "", updated: Date(), row: [:])
        s.recovery = 72
        s.strain = 46
        s.strainTarget = [55, 80]
        s.sleepScore = 88
        s.sleepMin = 467
        s.steps = 8214
        s.stress = 22
        s.rhr = 54
        s.bedtimeMin = -75
        s.hrv = 52
        s.activeCalories = 410
        s.stepGoal = 10000
        s.rhrBaseline = 56
        s.hrvBaseline = 48
        s.coachName = "Nova"
        s.coachText = "Recovery is solid at 72%. A moderate session fits today: aim for strain 55–80, then get to bed by 22:45."
        s.workoutsThisWeek = 3
        s.workoutMinutesThisWeek = 165
        s.lastWorkoutName = "Upper body A"
        let recoveries: [Double] = [64, 71, 48, 80, 66, 58, 72]
        let sleeps: [Double] = [430, 455, 390, 480, 465, 410, 467]
        let strains: [Double] = [52, 61, 30, 70, 44, 38, 46]
        let steps: [Double] = [9100, 11200, 6400, 12800, 8800, 7300, 8214]
        let stress: [Double] = [30, 22, 48, 18, 26, 35, 22]
        s.week = (0..<7).map {
            WidgetDay(date: "", recovery: recoveries[$0], sleepMin: sleeps[$0], strain: strains[$0], steps: steps[$0], stress: stress[$0])
        }
        s.deepMin = 88
        s.remMin = 120
        s.lightMin = 259
        s.awakeMin = 18
        return s
    }()

    /// Today's brief, when it is today's.
    var todaysCoachText: String? { coachDate == date ? coachText : nil }

    /// Tonight's bedtime, when it was planned for this snapshot's day.
    var tonightBedtime: Double? { bedtimeFor == date ? bedtimeMin : nil }
}

/// One day in the widgets' week view.
struct WidgetDay: Codable, Equatable {
    var date: String
    var recovery: Double?
    var sleepMin: Double?
    var strain: Double?
    var steps: Double?
    var stress: Double?

    /// yyyy-MM-dd plus `n` days, in UTC like the app's day keys.
    static func addDays(_ ymd: String, _ n: Int) -> String {
        guard let d = dayFormatter.date(from: ymd) else { return ymd }
        return dayFormatter.string(from: d.addingTimeInterval(Double(n) * 86_400))
    }

    /// "M", "T"… for the week bars.
    var weekdayLetter: String {
        guard let d = Self.dayFormatter.date(from: date) else { return "" }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f.string(from: d)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// The app group the app and the widget share. Signing apps for free Apple IDs often rename
/// the group (adding your team ID), so the name is read from this bundle's own provisioning
/// profile, and the name in FitStats.entitlements is only the fallback.
enum SharedStore {
    static let defaultGroup = "group.com.fitstats.air.k29x"

    /// The groups this bundle (the app or the widget) was signed with.
    static let signedGroups: [String] = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }()

    static var groupID: String {
        signedGroups.first { $0.hasPrefix(defaultGroup) } ?? signedGroups.first ?? defaultGroup
    }

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    private static func file(_ name: String) -> URL? { container?.appendingPathComponent(name) }

    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = file("widget.json"), let data = try? JSONEncoder().encode(snapshot) else { return false }
        return (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }

    static func readSnapshot() -> WidgetSnapshot? {
        guard let url = file("widget.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// The app key, so the widget can fetch today's numbers itself. Only apps signed into the
    /// same group (the app and its widget) can read the group's folder.
    static func saveKey(_ key: String) {
        guard let url = file("key"), readKey() != key else { return }
        try? Data(key.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func readKey() -> String? {
        guard let url = file("key"), let data = try? Data(contentsOf: url) else { return nil }
        let key = String(decoding: data, as: UTF8.self)
        return key.isEmpty ? nil : key
    }

    static func clear() {
        for name in ["widget.json", "key"] {
            if let url = file(name) { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Whether the shared folder can actually be written: false when the signing app left the
    /// app group out, and the widget then can't see the app's data.
    static func isWorking() -> Bool {
        guard let url = file("probe") else { return false }
        let ok = (try? Data("ok".utf8).write(to: url, options: .atomic)) != nil
        try? FileManager.default.removeItem(at: url)
        return ok
    }
}

/// Small formatting helpers for the widget views, which can't use the app's Format.
enum WidgetFormat {
    static func number(_ v: Double?, decimals: Int = 0) -> String {
        guard let v, v.isFinite else { return "–" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = decimals
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "–"
    }

    /// "7h 47m".
    static func duration(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite, minutes >= 0 else { return "–" }
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// Minutes from midnight as the phone shows times: "22:45" or "10:45 PM".
    static func clock(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite else { return "–" }
        var m = Int(minutes.rounded()) % 1440
        if m < 0 { m += 1440 }
        return clockFormatter.string(from: Date(timeIntervalSince1970: Double(m * 60)))
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// "10k", "8.5k" for goals.
    static func compact(_ v: Double) -> String {
        v >= 1000 ? (v.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(v / 1000))k" : String(format: "%.1fk", v / 1000)) : number(v)
    }

    /// "Today", "Yesterday", or "Mon 19".
    static func day(_ ymd: String, today: String) -> String {
        if ymd == today { return "Today" }
        if ymd == WidgetDay.addDays(today, -1) { return "Yesterday" }
        guard let d = WidgetDay.dayFormatter.date(from: ymd) else { return ymd }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEd")
        return f.string(from: d)
    }

    /// "Updated 10:42", or the weekday too when it's from an earlier day.
    static func updated(_ snapshot: WidgetSnapshot, now: Date = Date()) -> String {
        let time = snapshot.updated.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(snapshot.updated, inSameDayAs: now) { return "Updated \(time)" }
        return "Updated \(snapshot.updated.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}
