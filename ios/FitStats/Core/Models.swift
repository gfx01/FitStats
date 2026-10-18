import Foundation

// Shapes returned by the `fitstats` Supabase Edge Function.

struct StatusResponse: Codable {
    let version: String
    let serverTime: String
    let today: String
    let timeZone: String?
    let connection: Connection
    let sync: SyncInfo
    let devices: [Device]
    let profile: Profile
    let settings: UserSettings

    struct Connection: Codable {
        let status: String
        let email: String?
        let connectedAt: String?
        let error: String?
        let missingScopes: [String]
    }

    struct SyncInfo: Codable {
        let running: Bool
        let lastRunAt: String?
        let lastRunStatus: String?
        let lastRecentSyncAt: String?
        let backfillOldest: String?
        let backfillTarget: String?
        let backfillDone: Bool
        let backfillProgress: Double?
        let lastRunLog: JSONValue?
    }

    struct Device: Codable, Identifiable {
        let name: String?
        let type: String?
        let batteryLevel: Int?
        let batteryStatus: String?
        let lastSyncTime: String?
        var id: String { (name ?? "device") + (lastSyncTime ?? "") }
    }

    struct Profile: Codable {
        let age: Int?
    }
}

struct UserSettings: Codable, Equatable {
    var sex: String
    var maxHrOverride: Int?
    var sleepNeedMin: Int
    var stepGoal: Int
    var backfillDays: Int

    enum CodingKeys: String, CodingKey {
        case sex
        case maxHrOverride = "max_hr_override"
        case sleepNeedMin = "sleep_need_min"
        case stepGoal = "step_goal"
        case backfillDays = "backfill_days"
    }

    static let defaults = UserSettings(sex: "unspecified", maxHrOverride: nil, sleepNeedMin: 480, stepGoal: 10000, backfillDays: 730)

    // Encode nil explicitly so clearing the max-HR override reaches the server.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sex, forKey: .sex)
        try c.encode(maxHrOverride, forKey: .maxHrOverride)
        try c.encode(sleepNeedMin, forKey: .sleepNeedMin)
        try c.encode(stepGoal, forKey: .stepGoal)
        try c.encode(backfillDays, forKey: .backfillDays)
    }
}

struct SettingsResponse: Codable {
    let settings: UserSettings
}

/// One `fs_days` row. Columns are read by name so new server columns need no app update.
struct DayRecord: Codable, Identifiable {
    let date: String
    let values: [String: JSONValue]
    var id: String { date }

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard let dict = value.object, let date = dict["date"]?.string else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "day row without date"))
        }
        self.date = date
        self.values = dict
    }

    func encode(to encoder: Encoder) throws {
        try JSONValue.object(values).encode(to: encoder)
    }

    func double(_ key: String) -> Double? { values[key]?.double }
    func int(_ key: String) -> Int? { values[key]?.int }
    func string(_ key: String) -> String? { values[key]?.string }
    func bool(_ key: String) -> Bool? { values[key]?.bool }
    func json(_ key: String) -> JSONValue? { values[key] }
}

struct DaysResponse: Codable {
    let from: String
    let to: String
    let today: String
    let days: [DayRecord]
}

struct SleepSession: Codable, Identifiable {
    let id: String
    let date: String
    let startTime: String
    let endTime: String
    let isMain: Bool?
    let isNap: Bool?
    let minutesAsleep: Int?
    let minutesAwake: Int?
    let minutesInPeriod: Int?
    let deepMin: Int?
    let lightMin: Int?
    let remMin: Int?
    let awakeMin: Int?
    let awakeCount: Int?
    let stages: [[Double]]?

    enum CodingKeys: String, CodingKey {
        case id, date, stages
        case startTime = "start_time"
        case endTime = "end_time"
        case isMain = "is_main"
        case isNap = "is_nap"
        case minutesAsleep = "minutes_asleep"
        case minutesAwake = "minutes_awake"
        case minutesInPeriod = "minutes_in_period"
        case deepMin = "deep_min"
        case lightMin = "light_min"
        case remMin = "rem_min"
        case awakeMin = "awake_min"
        case awakeCount = "awake_count"
    }
}

struct Exercise: Codable, Identifiable {
    let id: String
    let date: String
    let startTime: String
    let endTime: String
    let exerciseType: String?
    let name: String?
    let durationS: Double?
    let activeDurationS: Double?
    let calories: Double?
    let steps: Double?
    let distanceM: Double?
    let avgHr: Double?
    let azm: Double?
    let zoneLightS: Double?
    let zoneModerateS: Double?
    let zoneVigorousS: Double?
    let zonePeakS: Double?
    let elevationGainM: Double?
    let avgSpeedMps: Double?
    let runVo2max: Double?

    enum CodingKeys: String, CodingKey {
        case id, date, name, calories, steps, azm
        case startTime = "start_time"
        case endTime = "end_time"
        case exerciseType = "exercise_type"
        case durationS = "duration_s"
        case activeDurationS = "active_duration_s"
        case distanceM = "distance_m"
        case avgHr = "avg_hr"
        case zoneLightS = "zone_light_s"
        case zoneModerateS = "zone_moderate_s"
        case zoneVigorousS = "zone_vigorous_s"
        case zonePeakS = "zone_peak_s"
        case elevationGainM = "elevation_gain_m"
        case avgSpeedMps = "avg_speed_mps"
        case runVo2max = "run_vo2max"
    }
}

struct DayDetail: Codable {
    let date: String
    let day: DayRecord?
    let intraday: Intraday?
    let sleeps: [SleepSession]
    let exercises: [Exercise]
    let samples: [String: [[Double]]]

    struct Intraday: Codable {
        let hr: [Int?]?
        let steps: [Int?]?
    }
}

// MARK: - Statistics

struct StatsPayload: Codable {
    let generatedAt: String
    let today: String
    let firstDate: String?
    let dayCount: Int
    let metrics: [String: MetricStats]
    let streaks: [Streak]
    let correlations: [Correlation]
    let insights: [Insight]
}

struct MetricStats: Codable {
    let key: String
    let latest: Double?
    let latestDate: String?
    let ranges: [String: RangeStats]
    let weekday: [Double?]
    let best: Record?
    let worst: Record?

    struct Record: Codable {
        let value: Double
        let date: String
    }
}

struct RangeStats: Codable {
    let days: Int?
    let n: Int
    let mean: Double?
    let median: Double?
    let min: Double?
    let minDate: String?
    let max: Double?
    let maxDate: String?
    let sd: Double?
    let sum: Double?
    let slopePerWeek: Double?
    let prevMean: Double?
    let changePct: Double?
}

struct Streak: Codable, Identifiable {
    let key: String
    let label: String
    let current: Int
    let longest: Int
    let longestEnd: String?
    var id: String { key }
}

struct Correlation: Codable, Identifiable {
    let x: String
    let y: String
    let lag: Int
    let title: String
    let r: Double?
    let n: Int
    let slope: Double?
    let strength: String
    var id: String { "\(x)-\(y)-\(lag)" }
}

struct Insight: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let tone: String
    let metric: String?
}

// MARK: - Score details stored in fs_days.score_details

struct ScoreComponentInfo: Identifiable {
    let key: String
    let label: String
    let value: Double
    let weight: Double
    let detail: String
    var id: String { key }
}

struct ScoreBreakdown {
    let score: Double?
    let status: String
    let components: [ScoreComponentInfo]

    init(_ json: JSONValue?) {
        score = json?["score"]?.double
        status = json?["status"]?.string ?? "no_data"
        components = (json?["components"]?.array ?? []).compactMap { c in
            guard let key = c["key"]?.string, let value = c["value"]?.double else { return nil }
            return ScoreComponentInfo(
                key: key,
                label: c["label"]?.string ?? key,
                value: value,
                weight: c["weight"]?.double ?? 0,
                detail: c["detail"]?.string ?? ""
            )
        }
    }
}
