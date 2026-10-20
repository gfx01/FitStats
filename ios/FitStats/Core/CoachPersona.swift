import SwiftUI

/// The three coaches you can pick in Coach. They read the same data with the same rules; only
/// their voice differs (the server's COACH_PERSONAS in lib/coach.ts holds what each one is told).
enum CoachPersona: String, CaseIterable, Identifiable, Codable {
    case nova, ace, kai

    static let storageKey = "coach.persona"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .nova: return "Nova"
        case .ace: return "Ace"
        case .kai: return "Kai"
        }
    }

    var tagline: String {
        switch self {
        case .nova: return "The analyst"
        case .ace: return "Tough love"
        case .kai: return "Calm and steady"
        }
    }

    var summary: String {
        switch self {
        case .nova: return "Explains the why behind every answer with your numbers and baselines, and says how sure it is."
        case .ace: return "Direct and demanding. Gives you the verdict and the plan, and pushes you when your recovery allows it."
        case .kai: return "Puts sleep, stress and recovery first, and suggests gentler options on low days."
        }
    }

    /// How it might open an answer, shown in the picker.
    var sample: String {
        switch self {
        case .nova: return "Your HRV is 7% under your 30-night baseline, most likely from two short nights."
        case .ace: return "Recovery's green. Today we lift heavy. Five sets, no skipping the last one."
        case .kai: return "You slept less than you need this week. Let's keep today easy and get to bed early."
        }
    }

    var color: Color {
        switch self {
        case .nova: return Color(red: 0.40, green: 0.47, blue: 1.00)
        case .ace: return Color(red: 1.00, green: 0.48, blue: 0.25)
        case .kai: return Color(red: 0.20, green: 0.86, blue: 0.72)
        }
    }

    static var saved: CoachPersona {
        UserDefaults.standard.string(forKey: storageKey).flatMap(CoachPersona.init(rawValue:)) ?? .nova
    }
}
