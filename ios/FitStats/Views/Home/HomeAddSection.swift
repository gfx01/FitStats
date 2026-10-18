import SwiftUI

/// The bottom of Home while editing: every card that isn't on Home yet, each as a live preview
/// (your own data) at the size you pick, with an Add button, and a reset to the default layout.
struct HomeAddSection: View {
    let date: String
    let shown: [HomeItem]
    let isDefault: Bool
    /// Whether a card can draw on `date` (see TodayView.isVisible); the others preview as placeholders.
    var canShow: (HomeCard) -> Bool
    var onAdd: (HomeItem) -> Void
    var onReset: () -> Void

    /// The size picked for each card's preview; a card's default until changed.
    @State private var sizes: [HomeCard: CardSize] = [:]

    private var more: [HomeCard] {
        HomeCard.allCases.filter { card in !shown.contains { $0.card == card } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Add cards", subtitle: "Previews use your own data. Pick a size, then tap Add.")
                .padding(.top, 16)
            if more.isEmpty {
                Text("Every card is already on Home. Remove one with its minus button to add it back at another size.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            LazyVStack(alignment: .leading, spacing: 26) {
                ForEach(more) { card in
                    previewRow(card)
                }
            }
            Button {
                onReset()
            } label: {
                Label("Reset Home to default", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isDefault ? Theme.tertiary : .white)
            .disabled(isDefault)
            .padding(.top, 8)
            .accessibilityIdentifier("home-reset")
        }
    }

    private func size(for card: HomeCard) -> CardSize {
        sizes[card] ?? card.defaultSize
    }

    private func previewRow(_ card: HomeCard) -> some View {
        let chosen = size(for: card)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: card.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.recoveryGreen)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.recoveryGreen.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
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
                }
                Spacer(minLength: 8)
                Button {
                    onAdd(HomeItem(card: card, size: chosen))
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.recoveryGreen)
                .accessibilityLabel(Text("Add \(card.title), \(chosen.label.lowercased())"))
                .accessibilityIdentifier("home-add-\(card.rawValue)")
            }
            Picker("Size", selection: Binding(get: { size(for: card) }, set: { sizes[card] = $0 })) {
                ForEach(CardSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("home-size-\(card.rawValue)")
            HomeGridLayout(columnSpacing: 12, rowSpacing: 14) {
                preview(card, size: chosen)
                    .layoutValue(key: HomeCardSizeKey.self, value: chosen)
            }
            .allowsHitTesting(false)
            .environment(\.homeCardPreview, true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Preview of \(card.title), \(chosen.label.lowercased())"))
        }
    }

    @ViewBuilder private func preview(_ card: HomeCard, size: CardSize) -> some View {
        if !canShow(card) {
            // Editing always shows today, so only a day that hasn't synced yet hides a card here.
            HomeCardPlaceholder(card: card, size: size, reason: "Shows once today's data has synced.")
        } else if size == .large {
            HomeLargeCard(card: card, date: date)
        } else {
            HomeGlance(card: card, size: size, date: date)
        }
    }
}
