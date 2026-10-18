import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var appKey: String?
    @Published private(set) var status: StatusResponse?
    @Published private(set) var days: [DayRecord] = [] {
        didSet { daysByDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, b in b }) }
    }
    @Published private(set) var daysByDate: [String: DayRecord] = [:]
    @Published private(set) var stats: StatsPayload?
    @Published private(set) var dayDetails: [String: DayDetail] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSyncing = false
    @Published var errorMessage: String?
    @Published var connectMessage: String?
    @Published var noticeMessage: String?

    let baseURL: URL
    let coach = CoachStore()
    private let authenticator = WebAuthenticator()
    private var lastRefresh: Date?
    /// API-shaped JSON used instead of the server for CI screenshots (see supabase/tests/make-fixtures.ts).
    private let fixtureDir: URL?

    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "FitStatsServerURL") as? String
        baseURL = URL(string: configured ?? "https://zkxnbcrayjwkeyxlungk.supabase.co/functions/v1/fitstats")!
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        fixtureDir = fixtures.isEmpty ? nil : URL(fileURLWithPath: fixtures)
        coach.apiProvider = { [weak self] in self?.api }
        coach.onUnauthorized = { [weak self] in
            self?.signOutLocally()
            self?.connectMessage = "This app key is no longer valid. Connect Google again."
        }
        if let fixtureDir {
            appKey = "fixture"
            loadFixtures()
            coach.loadFixtures(from: fixtureDir)
            return
        }
        appKey = KeyStore.read()
        if appKey != nil { loadCache() }
    }

    private func loadFixtures() {
        guard let dir = fixtureDir else { return }
        func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            do {
                let data = try Data(contentsOf: dir.appendingPathComponent(name))
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                errorMessage = "Fixture \(name): \(error)"
                return nil
            }
        }
        status = load(StatusResponse.self, "status.json")
        days = load(DaysResponse.self, "days.json")?.days ?? []
        stats = load(StatsPayload.self, "stats.json")
        for offset in 0..<7 {
            let date = Format.addDays(today, -offset)
            if let detail = load(DayDetail.self, "day-\(date).json") { dayDetails[date] = detail }
        }
    }

    private var api: APIClient? { appKey.map { APIClient(baseURL: baseURL, key: $0) } }

    var today: String { status?.today ?? Format.localToday() }

    var zone: TimeZone? { status?.timeZone.flatMap(TimeZone.init(identifier:)) }

    var needsReconnect: Bool {
        guard let s = status?.connection.status else { return false }
        return s == "expired" || s == "error" || s == "disconnected"
    }

    // MARK: - Cache

    private func loadCache() {
        let decoder = JSONDecoder()
        if let d = DiskCache.load("status.json"), let s = try? decoder.decode(StatusResponse.self, from: d) { status = s }
        if let d = DiskCache.load("days.json"), let r = try? decoder.decode(DaysResponse.self, from: d) { days = r.days }
        if let d = DiskCache.load("stats.json"), let s = try? decoder.decode(StatsPayload.self, from: d) { stats = s }
    }

    // MARK: - Connect

    func connect() async {
        connectMessage = nil
        let url = APIClient.url(base: baseURL, route: "connect", query: ["app_redirect": "fitstats://connected"])
        do {
            let callback = try await authenticator.start(url: url, callbackScheme: "fitstats")
            handleCallback(callback)
        } catch {
            if let e = error as? URLError, e.code == .cancelled { return }
            let ns = error as NSError
            if ns.domain == "com.apple.AuthenticationServices.WebAuthenticationSession", ns.code == 1 { return } // user cancelled
            connectMessage = "Could not open Google sign-in: \(error.localizedDescription)"
        }
    }

    /// Handles `fitstats://connected?...` from the sign-in sheet (or Safari, via onOpenURL).
    func handleCallback(_ url: URL) {
        guard url.scheme == "fitstats" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        if let error = value("error") {
            connectMessage = value("message") ?? "Google sign-in failed (\(error))."
            return
        }
        guard let key = value("key"), key.count >= 20 else {
            connectMessage = "The server did not return an app key. Try again."
            return
        }
        KeyStore.save(key)
        appKey = key
        connectMessage = nil
        if let missing = value("missing_scopes"), !missing.isEmpty {
            noticeMessage = "Some Google Health permissions were not granted (\(missing)). Those numbers will stay empty until you reconnect and allow them."
        } else {
            noticeMessage = "Connected. The first sync downloads your history in the background; it can take a while."
        }
        Task { await refreshAll(force: true) }
    }

    // MARK: - Loading

    func refreshAll(force: Bool = false) async {
        if fixtureDir != nil { return }
        guard let api else { return }
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < 20 { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let (s, sData) = try await api.fetch(StatusResponse.self, "status")
            status = s
            DiskCache.save(sData, as: "status.json")
            // Full history at most every 12 h (or on pull-to-refresh); otherwise only recent days.
            let lastFull = UserDefaults.standard.double(forKey: "lastFullDaysFetch")
            let needFull = force || days.isEmpty || Date().timeIntervalSince1970 - lastFull > 12 * 3600
            let from = needFull
                ? Format.addDays(s.today, -min(max(s.settings.backfillDays, 90), 1825))
                : Format.addDays(s.today, -10)
            let (d, dData) = try await api.fetch(DaysResponse.self, "days", query: ["from": from, "to": s.today])
            if needFull {
                days = d.days
                DiskCache.save(dData, as: "days.json")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastFullDaysFetch")
            } else {
                var merged = days.filter { $0.date < from }
                merged.append(contentsOf: d.days)
                days = merged
                if let all = try? JSONEncoder().encode(DaysResponse(from: merged.first?.date ?? from, to: s.today, today: s.today, days: merged)) {
                    DiskCache.save(all, as: "days.json")
                }
            }
            if let result = try? await api.fetch(StatsPayload.self, "stats") {
                stats = result.0
                DiskCache.save(result.1, as: "stats.json")
            }
            dayDetails[s.today] = nil
            lastRefresh = Date()
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    @discardableResult
    func loadDay(_ date: String, force: Bool = false) async -> DayDetail? {
        if fixtureDir != nil { return dayDetails[date] }
        if !force, let cached = dayDetails[date], date != today { return cached }
        guard let api else { return nil }
        do {
            let (detail, _) = try await api.fetch(DayDetail.self, "day", query: ["date": date])
            dayDetails[date] = detail
            return detail
        } catch {
            handle(error)
            return dayDetails[date]
        }
    }

    /// Asks the server to sync now, then polls until the run finishes (max ~2.5 min).
    func syncNow() async {
        guard fixtureDir == nil, let api, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            _ = try await api.post("sync")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            for _ in 0..<40 {
                let (s, _) = try await api.fetch(StatusResponse.self, "status")
                status = s
                if !s.sync.running { break }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            await refreshAll(force: true)
        } catch {
            handle(error)
        }
    }

    func saveSettings(_ settings: UserSettings) async -> Bool {
        guard let api else { return false }
        do {
            let body = try JSONEncoder().encode(settings)
            _ = try await api.post("settings", body: body)
            noticeMessage = "Settings saved. Scores are being recalculated."
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await refreshAll(force: true)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func disconnect(wipe: Bool) async {
        if let api {
            _ = try? await api.post("disconnect", query: wipe ? ["wipe": "true"] : [:])
        }
        signOutLocally()
    }

    func signOutLocally() {
        KeyStore.delete()
        DiskCache.clear()
        UserDefaults.standard.removeObject(forKey: "lastFullDaysFetch")
        appKey = nil
        status = nil
        days = []
        stats = nil
        dayDetails = [:]
        coach.reset()
    }

    private func handle(_ error: Error) {
        if case APIError.unauthorized = error {
            signOutLocally()
            connectMessage = "This app key is no longer valid. Connect Google again."
        } else {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived data

    func series(_ def: MetricDef, from: String, through: String) -> [DayPoint] {
        days.compactMap { day in
            guard day.date >= from, day.date <= through else { return nil }
            if def.isDayTotal && day.date >= today { return nil }
            guard let v = def.value(day), let date = Format.chartDate(day.date) else { return nil }
            return DayPoint(date: date, value: v)
        }
    }

    /// Mean of a metric over the `days` days before `date` (baseline for comparisons).
    func baseline(_ def: MetricDef, before date: String, days count: Int = 30) -> Double? {
        let from = Format.addDays(date, -count)
        let values = days.compactMap { d -> Double? in
            guard d.date >= from, d.date < date else { return nil }
            return def.value(d)
        }
        guard values.count >= 3 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func csvExport() -> URL? {
        let defs = MetricCatalog.all
        var lines = [(["date"] + defs.map(\.key)).joined(separator: ",")]
        for day in days {
            let cells = defs.map { def -> String in
                guard let v = def.value(day) else { return "" }
                return String(format: "%.\(def.decimals + 1)f", v)
            }
            lines.append(([day.date] + cells).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FitStats-\(today).csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }
}
