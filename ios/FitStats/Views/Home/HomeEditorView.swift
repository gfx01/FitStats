import SwiftUI

/// Chooses and orders the cards on Home. Opened by holding any Home card for a moment, or
/// with the "Edit Home screen" button at the bottom of Today.
struct HomeEditorView: View {
    @Binding var cards: [HomeCard]
    @Environment(\.dismiss) private var dismiss

    init(cards: Binding<[HomeCard]>) {
        _cards = cards
    }

    private var moreCards: [HomeCard] {
        HomeCard.allCases.filter { !cards.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                shownSection
                moreSection
                Section {
                    Button {
                        withAnimation { cards = HomeLayout.defaultCards }
                    } label: {
                        Label("Reset to default", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(cards == HomeLayout.defaultCards)
                    .accessibilityIdentifier("home-reset")
                }
            }
            .environment(\.editMode, .constant(.active))
            .screenBackground()
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("home-done")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var shownSection: some View {
        Section {
            ForEach(cards) { card in
                HomeEditorRow(card: card)
                    .deleteDisabled(cards.count <= 1)
                    .accessibilityIdentifier("home-shown-\(card.rawValue)")
            }
            .onMove(perform: move)
            .onDelete(perform: remove)
        } header: {
            Text("On Home")
        } footer: {
            Text("Drag the handles to reorder. Home keeps at least one card. Cards marked Today only are hidden on past days.")
        }
    }

    private var moreSection: some View {
        Section {
            if moreCards.isEmpty {
                Text("Every card is already on Home.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(moreCards) { card in
                Button {
                    add(card)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.recoveryGreen)
                        HomeEditorRow(card: card)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("home-add-\(card.rawValue)")
                .accessibilityLabel(Text("Add \(card.title)"))
                .accessibilityHint(Text(card.subtitle))
            }
        } header: {
            Text("More cards")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var next = cards
        next.move(fromOffsets: source, toOffset: destination)
        cards = next
    }

    private func remove(at offsets: IndexSet) {
        guard offsets.count < cards.count else { return }
        var next = cards
        next.remove(atOffsets: offsets)
        withAnimation { cards = next }
    }

    private func add(_ card: HomeCard) {
        guard !cards.contains(card) else { return }
        withAnimation { cards = cards + [card] }
    }
}

/// Icon, title and one-line description of a Home card.
private struct HomeEditorRow: View {
    let card: HomeCard

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if card.todayOnly {
                        Text("Today only")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
                Text(card.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading) // the add rows are buttons, which centre wrapped text
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch card {
        case .scores, .recoveryTrend: return Theme.recoveryGreen
        case .tonight, .lastNight: return Theme.sleep
        case .journal, .vitals, .hrvTrend, .stressDay: return Theme.stress
        case .activity, .workouts, .thisWeek: return Theme.strain
        case .heartRate, .restingHrTrend, .weeklyZoneMinutes: return Theme.heart
        case .streaks, .topInsight: return Theme.recoveryYellow
        case .coachBrief: return Theme.strainEnd
        case .body: return Theme.body
        }
    }
}
