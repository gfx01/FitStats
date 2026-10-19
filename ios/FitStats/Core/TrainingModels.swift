import Foundation

// The Training tab's data, as the server stores it (supabase/functions/fitstats/lib/training.ts):
// routines (plans with target sets, reps and weights), workouts logged set by set, and the
// band's own workouts. Exercises and sets also carry a local id for SwiftUI lists; it isn't sent.

enum ExerciseKind: String, Codable, CaseIterable, Identifiable {
    case strength, cardio, mobility, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strength: return "Strength"
        case .cardio: return "Cardio"
        case .mobility: return "Mobility"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .mobility: return "figure.flexibility"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Cardio is logged in minutes and km; the rest in kg and reps.
    var timed: Bool { self == .cardio }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExerciseKind(rawValue: raw) ?? .other
    }
}

struct RoutineExercise: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var kind: ExerciseKind = .strength
    var sets: Int?
    /// As written: "8", "8-12", "AMRAP".
    var reps: String?
    var weightKg: Double?
    var durationMin: Double?
    var distanceKm: Double?
    var restS: Int?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case name, kind, sets, reps, notes
        case weightKg = "weight_kg"
        case durationMin = "duration_min"
        case distanceKm = "distance_km"
        case restS = "rest_s"
    }

    /// "3 × 8-10 · 60 kg · rest 2 min", "30 min · 5 km".
    var plan: String {
        var parts: [String] = []
        if let sets, let reps, !reps.isEmpty { parts.append("\(sets) × \(reps)") } else if let sets { parts.append("\(sets) sets") } else if let reps, !reps.isEmpty { parts.append("\(reps) reps") }
        if let weightKg { parts.append("\(Format.kg(weightKg)) kg") }
        if let durationMin { parts.append(Format.duration(durationMin)) }
        if let distanceKm { parts.append("\(Format.number(distanceKm, decimals: distanceKm < 10 ? 1 : 0)) km") }
        if let restS, restS > 0 { parts.append("rest \(restS >= 60 && restS % 60 == 0 ? "\(restS / 60) min" : "\(restS) s")") }
        return parts.joined(separator: " · ")
    }
}

struct Routine: Codable, Equatable, Identifiable, Hashable {
    /// Empty until the server saves it.
    var id: String
    var name: String
    var notes: String?
    var exercises: [RoutineExercise]
    var createdBy: String = "user"
    var position: Int = 0
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, notes, exercises, position
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var byCoach: Bool { createdBy == "coach" }

    static func new() -> Routine { Routine(id: "", name: "", exercises: []) }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct LoggedSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var reps: Int?
    var weightKg: Double?
    var durationMin: Double?
    var distanceKm: Double?
    var done = false

    enum CodingKeys: String, CodingKey {
        case reps, done
        case weightKg = "weight_kg"
        case durationMin = "duration_min"
        case distanceKm = "distance_km"
    }

    init(reps: Int? = nil, weightKg: Double? = nil, durationMin: Double? = nil, distanceKm: Double? = nil, done: Bool = false) {
        self.reps = reps
        self.weightKg = weightKg
        self.durationMin = durationMin
        self.distanceKm = distanceKm
        self.done = done
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reps = try c.decodeIfPresent(Int.self, forKey: .reps)
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        durationMin = try c.decodeIfPresent(Double.self, forKey: .durationMin)
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? true
    }

    /// "8 × 60 kg", "30 min · 5 km".
    var summary: String {
        var parts: [String] = []
        if let reps, let weightKg { parts.append("\(reps) × \(Format.kg(weightKg)) kg") } else if let reps { parts.append("\(reps) reps") } else if let weightKg { parts.append("\(Format.kg(weightKg)) kg") }
        if let durationMin { parts.append(Format.duration(durationMin)) }
        if let distanceKm { parts.append("\(Format.number(distanceKm, decimals: 1)) km") }
        return parts.isEmpty ? "Done" : parts.joined(separator: " · ")
    }
}

struct LoggedExercise: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var kind: ExerciseKind = .strength
    var sets: [LoggedSet]
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case name, kind, sets, notes
    }

    var doneSets: [LoggedSet] { sets.filter(\.done) }

    /// Reps × kg over the done sets; nil without any weighted set.
    var volumeKg: Double? {
        let v = doneSets.reduce(0.0) { $0 + Double($1.reps ?? 0) * ($1.weightKg ?? 0) }
        return v > 0 ? v : nil
    }
}

struct WorkoutLog: Codable, Equatable, Identifiable, Hashable {
    /// Empty until the server saves it.
    var id: String
    var date: String
    var startedAt: String?
    var endedAt: String?
    var routineId: String?
    var name: String
    var exercises: [LoggedExercise]
    var notes: String?
    /// How hard it felt, 1–10.
    var effort: Int?

    enum CodingKeys: String, CodingKey {
        case id, date, name, exercises, notes, effort
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case routineId = "routine_id"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var minutes: Double? {
        guard let a = Format.timestamp(startedAt), let b = Format.timestamp(endedAt), b > a else { return nil }
        return b.timeIntervalSince(a) / 60
    }

    var doneSetCount: Int { exercises.reduce(0) { $0 + $1.doneSets.count } }

    var volumeKg: Double? {
        let v = exercises.compactMap(\.volumeKg).reduce(0, +)
        return v > 0 ? v : nil
    }

    /// A new workout from a routine: each exercise with its planned sets, the targets filled in
    /// (the last logged weight when the routine has none), nothing ticked yet.
    static func start(from routine: Routine?, date: String, previous: [WorkoutLog]) -> WorkoutLog {
        let exercises = (routine?.exercises ?? []).map { e -> LoggedExercise in
            let last = WorkoutLog.lastSets(of: e.name, in: previous)
            let count = max(1, e.sets ?? (e.kind.timed ? 1 : 3))
            let reps = e.reps.flatMap { Int($0.split(whereSeparator: { !$0.isNumber }).first ?? "") }
            let sets = (0..<count).map { i -> LoggedSet in
                LoggedSet(reps: e.kind.timed ? nil : reps ?? last?[safe: i]?.reps,
                          weightKg: e.kind.timed ? nil : e.weightKg ?? last?[safe: i]?.weightKg,
                          durationMin: e.durationMin, distanceKm: e.distanceKm)
            }
            return LoggedExercise(name: e.name, kind: e.kind, sets: sets, notes: nil)
        }
        return WorkoutLog(id: "", date: date, startedAt: Format.isoNow(), endedAt: nil, routineId: routine?.id,
                          name: routine?.name ?? "Workout", exercises: exercises, notes: nil, effort: nil)
    }

    /// The done sets of the most recent logged session of an exercise (same name, any case).
    static func lastSets(of name: String, in logs: [WorkoutLog]) -> [LoggedSet]? {
        for log in logs.sorted(by: { $0.date > $1.date }) {
            if let e = log.exercises.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }), !e.doneSets.isEmpty {
                return e.doneSets
            }
        }
        return nil
    }
}

struct TrainingResponse: Codable {
    let routines: [Routine]
    let logs: [WorkoutLog]
    let bandWorkouts: [Exercise]

    enum CodingKeys: String, CodingKey {
        case routines, logs
        case bandWorkouts = "band_workouts"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
