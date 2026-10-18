import Foundation

/// A card the Today (Home) screen can show. The raw values are what gets stored, so never
/// rename them: add new cases instead (stored values that no longer match are dropped).
enum HomeCard: String, CaseIterable, Identifiable, Codable {
    // The cards Today always had, in their original order.
    case scores
    case tonight
    case journal
    case vitals
    case activity
    case heartRate
    case workouts
    // Optional cards.
    case lastNight
    case recoveryTrend
    case hrvTrend
    case restingHrTrend
    case stressDay
    case thisWeek
    case weeklyZoneMinutes
    case streaks
    case topInsight
    case coachBrief
    case body

    var id: String { rawValue }

    /// The name in the Home editor: the same as the header the card shows (Scores has none).
    var title: String {
        switch self {
        case .scores: return "Scores"
        case .tonight: return "Tonight"
        case .journal: return "Journal"
        case .vitals: return "Vitals"
        case .activity: return "Activity"
        case .heartRate: return "Heart rate"
        case .workouts: return "Workouts"
        case .lastNight: return "Last night"
        case .recoveryTrend: return "Recovery trend"
        case .hrvTrend: return "HRV trend"
        case .restingHrTrend: return "Resting heart rate trend"
        case .stressDay: return "Stress through the day"
        case .thisWeek: return "This week"
        case .weeklyZoneMinutes: return "Weekly Zone Minutes"
        case .streaks: return "Streaks"
        case .topInsight: return "Insights"
        case .coachBrief: return "Coach briefing"
        case .body: return "Body"
        }
    }

    /// One line for the Home editor.
    var subtitle: String {
        switch self {
        case .scores: return "Recovery, strain, sleep and stress rings"
        case .tonight: return "Tonight's sleep need and bedtime"
        case .journal: return "Tag what you did that day"
        case .vitals: return "Overnight vitals against your 30-day average"
        case .activity: return "Steps, calories, distance and zone minutes"
        case .heartRate: return "The day's minute-by-minute heart rate"
        case .workouts: return "Workouts recorded that day"
        case .lastNight: return "Last night's sleep, stages and efficiency"
        case .recoveryTrend: return "Recovery over the last few weeks"
        case .hrvTrend: return "HRV against your baseline"
        case .restingHrTrend: return "Resting heart rate against your baseline"
        case .stressDay: return "How stress went through the day"
        case .thisWeek: return "The last 7 days at a glance"
        case .weeklyZoneMinutes: return "Heart-rate zone minutes over the week"
        case .streaks: return "Your current streaks"
        case .topInsight: return "Plain-language insights from your latest stats"
        case .coachBrief: return "Today's briefing from your coach"
        case .body: return "Weight and body fat"
        }
    }

    /// SF Symbol.
    var icon: String {
        switch self {
        case .scores: return "circle.circle"
        case .tonight: return "moon.stars.fill"
        case .journal: return "square.and.pencil"
        case .vitals: return "stethoscope"
        case .activity: return "figure.walk"
        case .heartRate: return "heart.fill"
        case .workouts: return "figure.run"
        case .lastNight: return "bed.double.fill"
        case .recoveryTrend: return "chart.line.uptrend.xyaxis"
        case .hrvTrend: return "waveform.path.ecg"
        case .restingHrTrend: return "heart.text.square"
        case .stressDay: return "brain.head.profile"
        case .thisWeek: return "calendar"
        case .weeklyZoneMinutes: return "flame.fill"
        case .streaks: return "trophy.fill"
        case .topInsight: return "sparkles"
        case .coachBrief: return "text.bubble.fill"
        case .body: return "scalemass.fill"
        }
    }

    /// Shown only while Today is on the current day (past days skip it).
    var todayOnly: Bool { self == .tonight || self == .coachBrief }
}

/// The ordered list of cards shown on Home, stored for @AppStorage as a comma-separated
/// string of raw values under `storageKey`.
enum HomeLayout {
    static let storageKey = "homeCards.v1"

    static let defaultCards: [HomeCard] = [.scores, .tonight, .journal, .vitals, .activity, .heartRate, .workouts]

    /// CI screenshots launch with FITSTATS_HOME_CARDS=all to show every card, whatever is stored.
    static var showsAllCards: Bool {
        ProcessInfo.processInfo.environment["FITSTATS_HOME_CARDS"] == "all"
    }

    /// Every card in declaration order in fixture mode, otherwise nil (use the stored layout).
    static var fixtureCards: [HomeCard]? {
        showsAllCards ? HomeCard.allCases : nil
    }

    /// Parses a stored value: unknown raw values and repeats are dropped, and an empty or
    /// missing value means the default layout.
    static func decode(_ stored: String?) -> [HomeCard] {
        guard let stored else { return defaultCards }
        var seen = Set<HomeCard>()
        var cards: [HomeCard] = []
        for part in stored.split(separator: ",") {
            let raw = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let card = HomeCard(rawValue: raw), seen.insert(card).inserted {
                cards.append(card)
            }
        }
        return cards.isEmpty ? defaultCards : cards
    }

    static func encode(_ cards: [HomeCard]) -> String {
        var seen = Set<HomeCard>()
        return cards.filter { seen.insert($0).inserted }.map(\.rawValue).joined(separator: ",")
    }

    /// The layout to show: every card in fixture mode, otherwise the stored one.
    static func load(_ stored: String?) -> [HomeCard] {
        fixtureCards ?? decode(stored)
    }

    /// The stored layout straight from UserDefaults (same key and format as the @AppStorage).
    static var current: [HomeCard] {
        load(UserDefaults.standard.string(forKey: storageKey))
    }
}
