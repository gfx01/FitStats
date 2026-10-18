import Foundation

enum Format {
    /// Calendar days are handled as UTC midnights so "YYYY-MM-DD" maths never hits DST.
    static let utc = TimeZone(identifier: "UTC")!

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ ymd: String) -> Date? { dayFormatter.date(from: ymd) }

    static func ymd(_ date: Date) -> String { dayFormatter.string(from: date) }

    private static let chartDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Local midnight of a calendar day. Swift Charts bins and labels dates in the device time zone,
    /// so a UTC midnight would land on the previous day anywhere west of UTC.
    static func chartDate(_ ymd: String) -> Date? { chartDayFormatter.date(from: ymd) }

    static func addDays(_ ymd: String, _ n: Int) -> String {
        guard let d = date(ymd) else { return ymd }
        return self.ymd(d.addingTimeInterval(Double(n) * 86_400))
    }

    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = date(a), let db = date(b) else { return 0 }
        return Int((db.timeIntervalSince(da) / 86_400).rounded())
    }

    static func localToday() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static let prettyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = utc
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static let longFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = utc
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let weekdayLetterFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = utc
        f.dateFormat = "EEEEE"
        return f
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = utc
        f.dateFormat = "d"
        return f
    }()

    static func weekdayLetter(_ ymd: String) -> String {
        guard let d = date(ymd) else { return "" }
        return weekdayLetterFormatter.string(from: d)
    }

    static func dayNumber(_ ymd: String) -> String {
        guard let d = date(ymd) else { return "" }
        return dayNumberFormatter.string(from: d)
    }

    static func prettyDay(_ ymd: String, today: String) -> String {
        if ymd == today { return "Today" }
        if ymd == addDays(today, -1) { return "Yesterday" }
        guard let d = date(ymd) else { return ymd }
        return prettyFormatter.string(from: d)
    }

    static func longDay(_ ymd: String) -> String {
        guard let d = date(ymd) else { return ymd }
        return longFormatter.string(from: d)
    }

    static func shortDay(_ ymd: String?) -> String {
        guard let ymd, let d = date(ymd) else { return "–" }
        return prettyFormatter.string(from: d)
    }

    /// 452 → "7h 32m"
    static func duration(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite else { return "–" }
        let total = Int(minutes.rounded())
        let h = abs(total) / 60, m = abs(total) % 60
        let sign = total < 0 ? "-" : ""
        return h > 0 ? "\(sign)\(h)h \(m)m" : "\(sign)\(m)m"
    }

    /// Minutes from local midnight (negative = evening before) → "23:30"
    static func clock(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite else { return "–" }
        var m = Int(minutes.rounded()) % 1440
        if m < 0 { m += 1440 }
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    private static let numberFormatters: [NumberFormatter] = (0...3).map { decimals in
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        return f
    }

    static func number(_ value: Double?, decimals: Int = 0) -> String {
        guard let value, value.isFinite else { return "–" }
        let f = numberFormatters[min(max(decimals, 0), 3)]
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func signed(_ value: Double?, decimals: Int = 0) -> String {
        guard let value, value.isFinite else { return "–" }
        let s = number(abs(value), decimals: decimals)
        return value >= 0 ? "+\(s)" : "−\(s)"
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func timestamp(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    static func relative(_ s: String?) -> String {
        guard let date = timestamp(s) else { return "never" }
        if abs(date.timeIntervalSinceNow) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func time(_ date: Date, zone: TimeZone?) -> String {
        let f = DateFormatter()
        f.timeZone = zone ?? .current
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
