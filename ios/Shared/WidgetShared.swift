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
        let target = ((row["score_details"] as? [String: Any])?["strainTarget"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue }
        strainTarget = target?.count == 2 ? target : nil
        self.bedtimeMin = bedtimeMin
        self.bedtimeFor = bedtimeFor
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
        return s
    }()

    /// Tonight's bedtime, when it was planned for this snapshot's day.
    var tonightBedtime: Double? { bedtimeFor == date ? bedtimeMin : nil }
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

    /// "Updated 10:42", or the weekday too when it's from an earlier day.
    static func updated(_ snapshot: WidgetSnapshot, now: Date = Date()) -> String {
        let time = snapshot.updated.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(snapshot.updated, inSameDayAs: now) { return "Updated \(time)" }
        return "Updated \(snapshot.updated.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}
