import SwiftUI

/// A workout logged in the app: every set, the totals, how hard it felt, and the band's
/// recording of the same session when there is one.
struct WorkoutLogDetailView: View {
    let logID: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workout: ActiveWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        let log = model.workoutLogs.first { $0.id == logID }
        ScrollView {
            VStack(spacing: 14) {
                if let log {
                    header(log)
                    totals(log)
                    if let band = bandMatch(log) { bandCard(band) }
                    ForEach(log.exercises) { exerciseCard($0) }
                    if let notes = log.notes, !notes.isEmpty {
                        Card {
                            SectionHeader(title: "Notes")
                            Text(notes).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    AskCoachRow(prompts: [
                        ("checklist", "Review this workout", "About my workout “\(log.name)” on \(Format.longDay(log.date)): how did it go, and what should I change next time?"),
                        ("arrow.up.right", "What next time?", "About my workout “\(log.name)” on \(Format.longDay(log.date)): what weights and reps should I aim for next time?"),
                    ])
                } else {
                    Card { EmptyStateView(icon: "questionmark", title: "Workout not found", message: "It may have been deleted.") }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(log.map { Format.shortDay($0.date) } ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let log {
                    Menu {
                        Button("Edit", systemImage: "pencil") { workout.start(log, editing: true) }
                            .disabled(workout.log != nil)
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Workout options")
                    .accessibilityIdentifier("log-options")
                }
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                Task {
                    await model.deleteLog(logID)
                    dismiss()
                }
            }
        }
    }

    private func header(_ log: WorkoutLog) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(log.name).font(.title3.weight(.semibold))
                Spacer()
                if let effort = log.effort {
                    Text("Effort \(effort)/10")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Effort.color(effort).opacity(0.18)))
                        .foregroundStyle(Effort.color(effort))
                }
            }
            Text([Format.longDay(log.date), timeRange(log)].compactMap { $0 }.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            if let id = log.routineId, let routine = model.routines.first(where: { $0.id == id }) {
                NavigationLink(value: TrainingRoute.routine(id)) {
                    Label("From \(routine.name)", systemImage: "list.bullet.clipboard")
                        .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    private func totals(_ log: WorkoutLog) -> some View {
        HStack(spacing: 10) {
            tile("Duration", log.minutes.map { Format.duration($0) } ?? "–")
            tile("Sets done", "\(log.doneSetCount)")
            tile("Volume", log.volumeKg.map { "\(Format.number($0)) kg" } ?? "–")
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.number(20)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private func exerciseCard(_ e: LoggedExercise) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label(e.name, systemImage: e.kind.icon).font(.headline)
                Spacer()
                if let v = e.volumeKg {
                    Text("\(Format.number(v)) kg").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            ForEach(Array(e.sets.enumerated()), id: \.element.id) { item in
                HStack {
                    Text("Set \(item.offset + 1)").foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(item.element.summary).monospacedDigit()
                    Image(systemName: item.element.done ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(item.element.done ? Theme.recoveryGreen : Theme.tertiary)
                }
                .font(.subheadline)
                .opacity(item.element.done ? 1 : 0.55)
                .accessibilityElement(children: .combine)
            }
            if let notes = e.notes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(Theme.secondary).italic()
            }
        }
    }

    private func bandCard(_ x: Exercise) -> some View {
        NavigationLink(value: DetailRoute.workout(x.date, x.id)) {
            Card {
                HStack {
                    SectionHeader(title: "Recorded by your band")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Theme.tertiary)
                }
                HStack(spacing: 12) {
                    Image(systemName: x.symbol)
                        .font(.subheadline)
                        .foregroundStyle(Theme.heart)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.heart.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(x.displayName).font(.subheadline.weight(.semibold))
                        Text([x.durationS.map { Format.duration($0 / 60) }, x.avgHr.map { "avg \(Int($0.rounded())) bpm" },
                              x.strain.map { "strain \(Format.number($0, decimals: 1))" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("log-band-workout")
    }

    /// The band workout of the same day that overlaps this one in time; without times, the
    /// day's only band workout.
    private func bandMatch(_ log: WorkoutLog) -> Exercise? {
        let sameDay = model.bandWorkouts.filter { $0.date == log.date }
        guard let start = Format.timestamp(log.startedAt) else { return sameDay.count == 1 ? sameDay[0] : nil }
        let end = Format.timestamp(log.endedAt) ?? start.addingTimeInterval(3600)
        return sameDay
            .compactMap { x -> (Exercise, TimeInterval)? in
                guard let a = Format.timestamp(x.startTime), let b = Format.timestamp(x.endTime) else { return nil }
                let overlap = min(b, end).timeIntervalSince(max(a, start))
                return overlap > 0 ? (x, overlap) : nil
            }
            .max { $0.1 < $1.1 }?.0
    }

    private func timeRange(_ log: WorkoutLog) -> String? {
        guard let start = Format.timestamp(log.startedAt) else { return nil }
        guard let end = Format.timestamp(log.endedAt) else { return Format.time(start, zone: model.zone) }
        return "\(Format.time(start, zone: model.zone))–\(Format.time(end, zone: model.zone))"
    }
}
