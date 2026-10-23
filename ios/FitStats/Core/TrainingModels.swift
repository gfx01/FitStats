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
    /// Muscles chosen for an exercise the library doesn't know (nil: the library's).
    var muscles: [String]?

    enum CodingKeys: String, CodingKey {
        case name, kind, sets, reps, notes, muscles
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

    /// Sets in a row that are the same, counted once: "5 × 80 kg (5 sets)",
    /// "8 × 60 kg (2 sets), 7 × 60 kg".
    static func compact(_ sets: [LoggedSet]) -> String {
        var runs: [(text: String, count: Int)] = []
        for text in sets.map(\.summary) {
            if runs.last?.text == text { runs[runs.count - 1].count += 1 } else { runs.append((text: text, count: 1)) }
        }
        return runs.map { $0.count > 1 ? "\($0.text) (\($0.count) sets)" : $0.text }.joined(separator: ", ")
    }
}

struct LoggedExercise: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var kind: ExerciseKind = .strength
    var sets: [LoggedSet]
    var notes: String?
    /// As RoutineExercise.muscles.
    var muscles: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case name, kind, sets, notes, muscles
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
            return LoggedExercise(name: e.name, kind: e.kind, sets: sets, notes: nil, muscles: e.muscles)
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
    /// Missing from servers before 1.8.0.
    let library: ExerciseLibrary?

    enum CodingKeys: String, CodingKey {
        case routines, logs, library
        case bandWorkouts = "band_workouts"
    }
}

// MARK: - Exercise library

/// Which muscles common exercises work, from the server (lib/exercises.ts). `primary` muscles
/// do most of the work, `secondary` ones help.
struct ExerciseLibrary: Codable, Equatable {
    let muscles: [MuscleInfo]
    let exercises: [LibraryExercise]

    static let empty = ExerciseLibrary(muscles: [], exercises: [])

    func label(_ muscle: String) -> String {
        muscles.first { $0.id == muscle }?.label ?? muscle.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// "Pull-up", "pull up" and "Pullups" are the same exercise (as the server's
    /// normalizeExerciseName).
    static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    func find(_ name: String) -> LibraryExercise? {
        func exact(_ s: String) -> LibraryExercise? {
            let n = Self.normalize(s)
            guard !n.isEmpty else { return nil }
            func matches(_ key: String) -> LibraryExercise? {
                exercises.first { e in ([e.name] + e.aliases).contains { Self.normalize($0) == key } }
            }
            return matches(n) ?? (n.hasSuffix("s") ? matches(String(n.dropLast())) : nil)
        }
        if let found = exact(name) { return found }
        // "Bench Press (Dumbbell)", as Strong and Hevy write them (lib/exercises.ts findExercise).
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "(") else { return nil }
        let base = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        let equipment = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)].trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        return exact("\(equipment) \(base)") ?? exact("\(base) \(equipment)") ?? exact(base)
    }

    /// What an exercise works: the muscles chosen for it, or the library's.
    func muscles(for name: String, chosen: [String]?) -> (primary: [String], secondary: [String]) {
        if let chosen, !chosen.isEmpty { return (chosen, []) }
        guard let e = find(name) else { return ([], []) }
        return (e.primary, e.secondary)
    }

    /// Done sets per muscle: 1 for each primary muscle, ½ for each secondary one. Cardio isn't
    /// counted (a run isn't a set). The same rule as the server's muscleSets.
    func sets(in logs: [WorkoutLog]) -> [String: Double] {
        var out: [String: Double] = [:]
        for log in logs {
            for e in log.exercises where e.kind != .cardio {
                let done = Double(e.doneSets.count)
                guard done > 0 else { continue }
                // Cardio, sports and stretches aren't sets of an exercise.
                if e.muscles?.isEmpty ?? true, let kind = find(e.name)?.kind, kind == "cardio" || kind == "mobility" { continue }
                let m = muscles(for: e.name, chosen: e.muscles)
                for id in m.primary { out[id, default: 0] += done }
                for id in m.secondary { out[id, default: 0] += done * 0.5 }
            }
        }
        return out
    }

    /// The muscles a routine works, weighted by its planned sets (as `sets(in:)`).
    func sets(in routine: Routine) -> [String: Double] {
        var out: [String: Double] = [:]
        for e in routine.exercises where e.kind != .cardio {
            if e.muscles?.isEmpty ?? true, let kind = find(e.name)?.kind, kind == "cardio" || kind == "mobility" { continue }
            let planned = Double(e.sets ?? 1)
            let m = muscles(for: e.name, chosen: e.muscles)
            for id in m.primary { out[id, default: 0] += planned }
            for id in m.secondary { out[id, default: 0] += planned * 0.5 }
        }
        return out
    }
}

struct MuscleInfo: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let label: String
    /// front, back or both: where the body map draws it.
    let side: String
}

struct LibraryExercise: Codable, Equatable, Identifiable, Hashable {
    let name: String
    let aliases: [String]
    let kind: String
    /// Chest, Back, …, Cardio, Sports, Mobility; missing from servers before the bigger library.
    let category: String?
    let equipment: String
    let primary: [String]
    let secondary: [String]

    var id: String { name }
    var exerciseKind: ExerciseKind { ExerciseKind(rawValue: kind) ?? .other }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
