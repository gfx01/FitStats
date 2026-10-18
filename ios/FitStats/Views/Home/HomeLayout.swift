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
    case trainingLoad
    case liveHeartRate

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
        case .trainingLoad: return "Training load"
        case .liveHeartRate: return "Live heart rate"
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
        case .trainingLoad: return "Fitness, fatigue and form from your training"
        case .liveHeartRate: return "From your Fitbit Air over Bluetooth"
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
        case .trainingLoad: return "speedometer"
        case .liveHeartRate: return "heart.circle"
        }
    }

    /// Shown only while Today is on the current day (past days skip it).
    var todayOnly: Bool { self == .tonight || self == .coachBrief || self == .liveHeartRate }

    /// The size a card gets when it is added, and when a layout from before sizes is loaded.
    var defaultSize: CardSize {
        switch self {
        case .scores: return .large
        case .vitals, .activity, .heartRate, .workouts, .lastNight, .thisWeek, .topInsight, .coachBrief: return .medium
        case .tonight, .journal, .recoveryTrend, .hrvTrend, .restingHrTrend, .stressDay, .weeklyZoneMinutes,
             .streaks, .body, .trainingLoad, .liveHeartRate: return .small
        }
    }
}

/// How big a Home card is, like iOS widgets: small takes half the width (two sit side by
/// side), medium the full width at the same height, large is the full card with everything.
enum CardSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// The footprint the resize handle works in: small is 1 column, medium 2, large 2 × 2.
    var columns: Int { self == .small ? 1 : 2 }
    var rows: Int { self == .large ? 2 : 1 }

    /// Tapping the resize handle steps through the sizes.
    var next: CardSize {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return .small
        }
    }
}

/// One card on Home and its size.
struct HomeItem: Identifiable, Equatable {
    var card: HomeCard
    var size: CardSize

    var id: HomeCard { card }
}

/// The ordered cards on Home with their sizes, stored for @AppStorage as a comma-separated
/// string of "card:size" under `storageKey`.
enum HomeLayout {
    static let storageKey = "homeCards.v2"
    /// Before sizes: the same list without them. Read once, when nothing is stored under v2.
    static let legacyKey = "homeCards.v1"

    static let defaultItems: [HomeItem] = [
        HomeItem(card: .scores, size: .large),
        HomeItem(card: .tonight, size: .small),
        HomeItem(card: .journal, size: .small),
        HomeItem(card: .vitals, size: .medium),
        HomeItem(card: .activity, size: .medium),
        HomeItem(card: .heartRate, size: .medium),
        HomeItem(card: .workouts, size: .medium),
    ]

    /// CI screenshots launch with FITSTATS_HOME_CARDS=all to show every card, whatever is stored,
    /// and FITSTATS_HOME_SIZE=small|medium|large to show them all at one size.
    static var showsAllCards: Bool {
        ProcessInfo.processInfo.environment["FITSTATS_HOME_CARDS"] == "all"
    }

    /// Every card in declaration order in fixture mode, otherwise nil (use the stored layout).
    static var fixtureItems: [HomeItem]? {
        guard showsAllCards else { return nil }
        let forced = ProcessInfo.processInfo.environment["FITSTATS_HOME_SIZE"].flatMap(CardSize.init(rawValue:))
        return HomeCard.allCases.map { HomeItem(card: $0, size: forced ?? $0.defaultSize) }
    }

    /// Parses a stored value: unknown cards and repeats are dropped, an unknown or missing size
    /// means the card's default. Nothing stored means the layout from before sizes, if there is
    /// one, else the default layout.
    static func decode(_ stored: String?) -> [HomeItem] {
        if let stored, !stored.isEmpty {
            let items = parse(stored)
            if !items.isEmpty { return items }
        }
        if let legacy = UserDefaults.standard.string(forKey: legacyKey), !legacy.isEmpty {
            let items = parse(legacy)
            if !items.isEmpty { return items }
        }
        return defaultItems
    }

    private static func parse(_ stored: String) -> [HomeItem] {
        var seen = Set<HomeCard>()
        var items: [HomeItem] = []
        for part in stored.split(separator: ",") {
            let pieces = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let raw = pieces.first, let card = HomeCard(rawValue: raw), seen.insert(card).inserted else { continue }
            let size = pieces.count > 1 ? CardSize(rawValue: pieces[1]) : nil
            items.append(HomeItem(card: card, size: size ?? card.defaultSize))
        }
        return items
    }

    static func encode(_ items: [HomeItem]) -> String {
        var seen = Set<HomeCard>()
        return items.filter { seen.insert($0.card).inserted }.map { "\($0.card.rawValue):\($0.size.rawValue)" }.joined(separator: ",")
    }
}

