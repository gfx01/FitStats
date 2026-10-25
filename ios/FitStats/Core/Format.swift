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

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = utc
        f.dateFormat = "MMM d"
        return f
    }()

    /// "Oct 5".
    static func monthDay(_ ymd: String) -> String {
        guard let d = date(ymd) else { return ymd }
        return monthDayFormatter.string(from: d)
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

    /// Seconds → "16s" under a minute, otherwise like `duration` ("1h 35m").
    static func duration(seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "–" }
        return seconds < 59.5 ? "\(Int(seconds.rounded()))s" : duration(seconds / 60)
    }

    /// Minutes from local midnight (negative = evening before) → "23:30"
    /// Hours and minutes in the device's 12- or 24-hour style.
    /// The phone shows 24-hour times (Settings → General → Date & Time). The coach is told, so
    /// its times read like the app's.
    static var uses24HourClock: Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    /// An hour on a chart axis as the phone shows hours: "6 AM" or "06".
    static func hour(_ h: Int) -> String {
        hourFormatter.string(from: Date(timeIntervalSince1970: Double(((h % 24) + 24) % 24) * 3600))
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// Minutes from midnight as a time of day.
    static func clock(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite else { return "–" }
        var m = Int(minutes.rounded()) % 1440
        if m < 0 { m += 1440 }
        return clockFormatter.string(from: Date(timeIntervalSince1970: Double(m * 60)))
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

    /// A weight without trailing zeros: "60", "62.5", "1.25".
    static func kg(_ value: Double) -> String {
        number(value, decimals: value == value.rounded() ? 0 : (value * 10 == (value * 10).rounded() ? 1 : 2))
    }

    /// Now as an ISO 8601 timestamp, as the server stores times.
    static func isoNow() -> String {
        isoFractional.string(from: Date())
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
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }

    /// A whole-hour tick on a time axis, short so several fit: "5 AM" or "05".
    static func hour(_ date: Date, zone: TimeZone?) -> String {
        let f = DateFormatter()
        f.timeZone = zone ?? .current
        f.setLocalizedDateFormatFromTemplate("j")
        return f.string(from: date)
    }
}
