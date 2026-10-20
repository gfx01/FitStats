import SwiftUI

enum MetricCategory: String, CaseIterable, Identifiable {
    case scores, activity, heart, sleep, vitals, body
    var id: String { rawValue }

    var title: String {
        switch self {
        case .scores: return "Scores"
        case .activity: return "Activity"
        case .heart: return "Heart"
        case .sleep: return "Sleep"
        case .vitals: return "Vitals"
        case .body: return "Body"
        }
    }

    var color: Color {
        switch self {
        case .scores: return Theme.recoveryGreen
        case .activity: return Theme.strain
        case .heart: return Theme.heart
        case .sleep: return Theme.sleep
        case .vitals: return Theme.stress
        case .body: return Theme.body
        }
    }
}

enum MetricFormat {
    case number, signed, duration, clock, percent
}

enum Better {
    case higher, lower
}

/// Client-side mirror of the server's metric list (supabase/functions/fitstats/lib/stats.ts).
struct MetricDef: Identifiable, Hashable {
    let key: String
    let label: String
    /// Fits a half-width tile or a list row without truncating.
    let shortLabel: String
    let unit: String
    let decimals: Int
    let category: MetricCategory
    let isDayTotal: Bool
    let better: Better?
    let format: MetricFormat
    let icon: String
    let extract: (DayRecord) -> Double?

    var id: String { key }

    static func == (a: MetricDef, b: MetricDef) -> Bool { a.key == b.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }

    func value(_ day: DayRecord) -> Double? { extract(day) }

    /// Shorter still, for where even the short label doesn't fit (FittingText falls back to it,
    /// e.g. with large text): "Resting HR", "Calories".
    var compactLabel: String { Self.compactLabels[key] ?? shortLabel }

    private static let compactLabels = [
        "rhr": "Resting HR", "hrv_rmssd": "HRV", "hrv_deep_rmssd": "Deep HRV", "non_rem_hr": "Non-REM HR",
        "hr_avg": "Average HR", "hr_max": "Max HR", "calories_total": "Calories", "calories_active": "Active kcal",
        "azm_total": "Zone min", "active_min_total": "Active min", "active_vigorous_min": "Vigorous min",
        "sedentary_h": "Sedentary", "spo2_avg": "SpO₂", "resp_rate": "Breathing", "vo2max": "VO₂ max",
        "sleep_asleep_min": "Asleep", "sleep_in_bed_min": "In bed", "sleep_efficiency": "Efficiency",
    ]

    /// Clock times and the skin temperature deviation sit around an arbitrary zero, so a percent
    /// change means nothing: they are compared by the absolute change (the server sends no changePct).
    var comparesAbsolute: Bool { format == .clock || key == "skin_temp_dev" }

    func formatted(_ v: Double?, withUnit: Bool = true, decimals override: Int? = nil) -> String {
        guard let v else { return "–" }
        let places = override ?? decimals
        switch format {
        case .duration: return Format.duration(v)
        case .clock: return Format.clock(v)
        case .percent: return "\(Format.number(v, decimals: places))%"
        case .number, .signed:
            let s = format == .signed ? Format.signed(v, decimals: places) : Format.number(v, decimals: places)
            guard withUnit, !unit.isEmpty else { return s }
            return unit == "%" ? "\(s)%" : "\(s) \(unit)"
        }
    }
}

enum MetricCatalog {
    private static func col(_ key: String) -> (DayRecord) -> Double? { { $0.double(key) } }

    private static func sum(_ keys: [String]) -> (DayRecord) -> Double? {
        { day in
            var any = false
            var total = 0.0
            for k in keys {
                if let v = day.double(k) {
                    total += v
                    any = true
                }
            }
            return any ? total : nil
        }
    }

    private static func ratio(_ num: String, _ den: String) -> (DayRecord) -> Double? {
        { day in
            guard let a = day.double(num), let b = day.double(den), b > 0 else { return nil }
            return a / b * 100
        }
    }

    private static func m(
        _ key: String, _ label: String, _ unit: String, _ decimals: Int, _ category: MetricCategory,
        short: String? = nil, total: Bool, better: Better?, format: MetricFormat = .number, icon: String,
        extract: ((DayRecord) -> Double?)? = nil
    ) -> MetricDef {
        MetricDef(key: key, label: label, shortLabel: short ?? label, unit: unit, decimals: decimals, category: category,
                  isDayTotal: total, better: better, format: format, icon: icon, extract: extract ?? col(key))
    }

    static let all: [MetricDef] = [
        m("recovery", "Recovery", "%", 0, .scores, total: false, better: .higher, icon: "bolt.heart.fill"),
        m("strain", "Strain", "", 1, .scores, total: true, better: nil, icon: "flame.fill"),
        m("sleep_score", "Sleep score", "", 0, .scores, total: false, better: .higher, icon: "moon.stars.fill"),
        m("stress", "Stress", "", 0, .scores, total: true, better: .lower, icon: "waveform.path.ecg"),

        m("steps", "Steps", "", 0, .activity, total: true, better: .higher, icon: "figure.walk"),
        m("distance_km", "Distance", "km", 2, .activity, total: true, better: .higher, icon: "map",
          extract: { $0.double("distance_m").map { $0 / 1000 } }),
        m("floors", "Floors", "", 0, .activity, total: true, better: .higher, icon: "stairs"),
        m("calories_total", "Calories burned", "kcal", 0, .activity, total: true, better: nil, icon: "flame"),
        m("calories_active", "Active calories", "kcal", 0, .activity, total: true, better: .higher, icon: "bolt.fill"),
        m("azm_total", "Active Zone Minutes", "min", 0, .activity, short: "Zone Minutes", total: true, better: .higher, icon: "heart.circle",
          extract: sum(["azm_fat_burn", "azm_cardio", "azm_peak"])),
        m("active_min_total", "Active minutes", "min", 0, .activity, total: true, better: .higher, icon: "figure.run",
          extract: sum(["active_light_min", "active_moderate_min", "active_vigorous_min"])),
        m("active_vigorous_min", "Vigorous minutes", "min", 0, .activity, total: true, better: .higher, icon: "hare.fill"),
        m("sedentary_h", "Sedentary time", "h", 1, .activity, total: true, better: .lower, icon: "chair.lounge",
          extract: { $0.double("sedentary_min").map { $0 / 60 } }),
        m("trimp", "Training load (TRIMP)", "", 0, .activity, short: "Training load", total: true, better: nil, icon: "chart.bar.fill"),

        m("rhr", "Resting heart rate", "bpm", 0, .heart, total: false, better: .lower, icon: "heart.fill"),
        m("hrv_rmssd", "HRV (RMSSD)", "ms", 0, .heart, total: false, better: .higher, icon: "waveform.path"),
        m("hrv_deep_rmssd", "Deep-sleep HRV", "ms", 0, .heart, total: false, better: .higher, icon: "waveform"),
        m("non_rem_hr", "Non-REM heart rate", "bpm", 0, .heart, total: false, better: .lower, icon: "bed.double"),
        m("hr_avg", "Average heart rate", "bpm", 0, .heart, total: true, better: nil, icon: "heart"),
        m("hr_max", "Max heart rate", "bpm", 0, .heart, total: true, better: nil, icon: "arrow.up.heart"),
        m("zone_cardio_min", "Cardio + peak zone", "min", 0, .heart, total: true, better: .higher, icon: "speedometer",
          extract: sum(["zone_vigorous_min", "zone_peak_min"])),
        m("vo2max", "Cardio fitness (VO₂ max)", "ml/kg/min", 1, .heart, short: "VO₂ max", total: false, better: .higher, icon: "lungs.fill"),

        m("sleep_asleep_min", "Time asleep", "", 0, .sleep, total: false, better: .higher, format: .duration, icon: "moon.fill"),
        m("sleep_in_bed_min", "Time in bed", "", 0, .sleep, total: false, better: nil, format: .duration, icon: "bed.double.fill"),
        m("sleep_deep_min", "Deep sleep", "", 0, .sleep, total: false, better: .higher, format: .duration, icon: "moon.zzz.fill"),
        m("sleep_rem_min", "REM sleep", "", 0, .sleep, total: false, better: .higher, format: .duration, icon: "sparkles"),
        m("sleep_light_min", "Light sleep", "", 0, .sleep, total: false, better: nil, format: .duration, icon: "cloud.moon"),
        // Google's minutesAwake: every awake stage, including the stretch before falling asleep.
        m("sleep_awake_min", "Awake (incl. falling asleep)", "", 0, .sleep, short: "Awake in bed", total: false, better: .lower, format: .duration, icon: "eye"),
        m("sleep_waso_min", "Awake after falling asleep", "", 0, .sleep, short: "Awake mid-sleep", total: false, better: .lower, format: .duration, icon: "eye.circle"),
        m("deep_pct", "Deep sleep share", "%", 0, .sleep, total: false, better: .higher, format: .percent, icon: "percent",
          extract: ratio("sleep_deep_min", "sleep_asleep_min")),
        m("rem_pct", "REM sleep share", "%", 0, .sleep, total: false, better: .higher, format: .percent, icon: "percent",
          extract: ratio("sleep_rem_min", "sleep_asleep_min")),
        m("sleep_efficiency", "Sleep efficiency", "%", 0, .sleep, total: false, better: .higher, format: .percent, icon: "gauge.with.dots.needle.67percent",
          extract: { $0.double("sleep_efficiency").map { $0 * 100 } }),
        m("sleep_awakenings", "Awakenings", "", 0, .sleep, total: false, better: .lower, icon: "exclamationmark.circle"),
        m("sleep_bedtime_min", "Bedtime", "", 0, .sleep, total: false, better: nil, format: .clock, icon: "bed.double"),
        m("sleep_waketime_min", "Wake time", "", 0, .sleep, total: false, better: nil, format: .clock, icon: "sunrise.fill"),
        m("nap_min", "Naps", "", 0, .sleep, total: false, better: nil, format: .duration, icon: "zzz"),

        m("spo2_avg", "Blood oxygen (SpO₂)", "%", 1, .vitals, short: "Blood oxygen", total: false, better: .higher, icon: "drop.fill"),
        m("resp_rate", "Breathing rate", "/min", 1, .vitals, total: false, better: nil, icon: "wind"),
        m("skin_temp_dev", "Skin temperature variation", "°C", 2, .vitals, short: "Skin temp", total: false, better: nil,
          format: .signed, icon: "thermometer.medium",
          extract: { d in
              guard let t = d.double("skin_temp_c"), let b = d.double("skin_temp_baseline_c") else { return nil }
              return t - b
          }),

        m("weight_kg", "Weight", "kg", 1, .body, total: false, better: nil, icon: "scalemass.fill"),
        m("body_fat_pct", "Body fat", "%", 1, .body, total: false, better: .lower, icon: "figure.arms.open"),
    ]

    static let byKey: [String: MetricDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    static func def(_ key: String) -> MetricDef? { byKey[key] }
}
