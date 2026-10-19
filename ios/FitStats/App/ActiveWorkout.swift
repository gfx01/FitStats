import Foundation
import SwiftUI

/// The workout being logged right now, kept on the phone after every change so a closed or
/// killed app picks it up where it was. Separate from AppModel, so typing a weight redraws only
/// the logger.
@MainActor
final class ActiveWorkout: ObservableObject {
    private static let key = "training.activeWorkout"

    /// The workout being logged, or nil. `editing` is true when it is a saved workout being changed.
    @Published var log: WorkoutLog? {
        didSet { persist() }
    }
    @Published var editing = false {
        didSet { persist() }
    }
    /// The logger is on screen (it can be closed and resumed from the Training tab).
    @Published var presented = false

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            log = saved.log
            editing = saved.editing
        }
    }

    private struct Saved: Codable {
        let log: WorkoutLog
        let editing: Bool
    }

    func start(_ workout: WorkoutLog, editing: Bool = false) {
        self.editing = editing
        log = workout
        presented = true
    }

    func discard() {
        log = nil
        editing = false
        presented = false
    }

    private func persist() {
        if let log, let data = try? JSONEncoder().encode(Saved(log: log, editing: editing)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }
}
