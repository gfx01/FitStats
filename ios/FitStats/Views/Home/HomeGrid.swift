import SwiftUI
import UniformTypeIdentifiers

/// The size each Home grid cell asks for (set with `.layoutValue(key:value:)`).
struct HomeCardSizeKey: LayoutValueKey {
    static let defaultValue: CardSize = .large
}

/// True inside the "Add cards" previews: cards there draw from your data but must not start
/// anything (live heart rate stays off).
private struct HomeCardPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var homeCardPreview: Bool {
        get { self[HomeCardPreviewKey.self] }
        set { self[HomeCardPreviewKey.self] = newValue }
    }
}

/// Lays Home cards out like iOS widgets: a small card takes half the width and sits next to the
/// small card after it, medium and large cards take the whole width. The order is kept, so a
/// small card followed by a wide one leaves the other half empty. One flat layout (rather than
/// rows of stacks) keeps every card's identity when its size changes, so a resize drag keeps
/// going while the card grows or shrinks under the finger.
struct HomeGridLayout: Layout {
    var columnSpacing: CGFloat = 12
    var rowSpacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let frames = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let f = frames[index]
            subview.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }

    /// Frames relative to the top-left corner. A cell that draws nothing (height 0) takes no
    /// space and adds no spacing.
    private func arrange(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let half = max(0, (width - columnSpacing) / 2)
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        var y: CGFloat = 0
        // Height of the small card waiting on the left for a partner.
        var leftHeight: CGFloat?
        for (index, subview) in subviews.enumerated() {
            if subview[HomeCardSizeKey.self] == .small {
                let h = subview.sizeThatFits(ProposedViewSize(width: half, height: nil)).height
                guard h > 0 else {
                    frames[index] = CGRect(x: 0, y: y, width: half, height: 0)
                    continue
                }
                if let left = leftHeight {
                    frames[index] = CGRect(x: half + columnSpacing, y: y, width: half, height: h)
                    y += max(left, h) + rowSpacing
                    leftHeight = nil
                } else {
                    frames[index] = CGRect(x: 0, y: y, width: half, height: h)
                    leftHeight = h
                }
            } else {
                if let left = leftHeight {
                    y += left + rowSpacing
                    leftHeight = nil
                }
                let h = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
                frames[index] = CGRect(x: 0, y: y, width: width, height: h)
                if h > 0 { y += h + rowSpacing }
            }
        }
        return frames
    }
}

/// A slight, endless wobble while Home is being edited, like the iOS Home Screen. Off with
/// Reduce Motion.
struct Jiggle: ViewModifier {
    let amplitude: Double
    let seed: Int
    @State private var tilted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(reduceMotion ? 0 : (tilted ? amplitude : -amplitude)))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.13 + Double(seed % 4) * 0.015).repeatForever(autoreverses: true)) {
                    tilted = true
                }
            }
    }
}

/// A Home card in edit mode: it wobbles, can't be tapped through, has a remove button on its
/// top-left corner and a resize handle on its bottom-right one. Holding it and dragging moves
/// it (system drag and drop, see HomeDropDelegate).
struct HomeEditCell<Content: View>: View {
    let item: HomeItem
    let seed: Int
    let canRemove: Bool
    let isDragged: Bool
    var onRemove: () -> Void
    var onResize: (CardSize) -> Void
    var onMove: (Int) -> Void
    var onDragStart: () -> NSItemProvider
    @ViewBuilder var content: () -> Content

    /// The size when the resize drag began; the target is worked out from it and the whole
    /// drag, so growing past a step and coming back undoes it.
    @State private var resizeStart: CardSize?

    var body: some View {
        content()
            .allowsHitTesting(false)
            // Catches touches over the whole card, so holding anywhere on it starts a drag.
            .overlay { Color.white.opacity(0.001) }
            .overlay(alignment: .topLeading) {
                if canRemove { removeButton }
            }
            .overlay(alignment: .bottomTrailing) { resizeHandle }
            .opacity(isDragged ? 0.35 : 1)
            .modifier(Jiggle(amplitude: amplitude, seed: seed))
            .onDrag(onDragStart)
            .sensoryFeedback(.selection, trigger: item.size)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("\(item.card.title), \(item.size.label)"))
            .accessibilityActions {
                ForEach(CardSize.allCases.filter { $0 != item.size }) { size in
                    Button("Make \(size.label.lowercased())") { onResize(size) }
                }
                Button("Move up") { onMove(-1) }
                Button("Move down") { onMove(1) }
                if canRemove { Button("Remove") { onRemove() } }
            }
    }

    /// Bigger cards wobble less, so their far edges don't swing too much.
    private var amplitude: Double {
        switch item.size {
        case .small: return 1.4
        case .medium: return 0.8
        case .large: return 0.45
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "minus")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(white: 0.32)))
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: -16, y: -16)
        .accessibilityLabel(Text("Remove \(item.card.title)"))
        .accessibilityIdentifier("home-remove-\(item.card.rawValue)")
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 26, height: 26)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.35), radius: 3)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .offset(x: 10, y: 10)
            .highPriorityGesture(
                // Global space: the card under the finger grows and moves while dragging.
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        let start = resizeStart ?? item.size
                        if resizeStart == nil { resizeStart = item.size }
                        let target = Self.size(from: start, translation: value.translation)
                        if target != item.size { onResize(target) }
                    }
                    .onEnded { _ in resizeStart = nil }
            )
            .onTapGesture { onResize(item.size.next) }
            .accessibilityLabel(Text("Resize \(item.card.title)"))
            .accessibilityValue(Text(item.size.label))
            .accessibilityHint(Text("Drag to resize, or tap for the next size"))
            .accessibilityIdentifier("home-resize-\(item.card.rawValue)")
    }

    /// Dragging right or left past a step widens or narrows the card, down or up makes it
    /// taller or shorter. Small is 1 × 1, medium 2 × 1 and large 2 × 2; a drag that asks for
    /// 1 × 2 follows whichever direction moved further.
    static func size(from start: CardSize, translation t: CGSize) -> CardSize {
        let step: CGFloat = 50
        var columns = start.columns
        var rows = start.rows
        if t.width > step { columns = 2 } else if t.width < -step { columns = 1 }
        if t.height > step { rows = 2 } else if t.height < -step { rows = 1 }
        if columns == 1 && rows == 2 {
            return abs(t.height) > abs(t.width) ? .large : .small
        }
        if columns == 1 { return .small }
        return rows == 1 ? .medium : .large
    }
}

/// Live reordering while a card is dragged over another one, like the iOS Home Screen.
struct HomeDropDelegate: DropDelegate {
    let target: HomeCard
    @Binding var items: [HomeItem]
    @Binding var dragging: HomeCard?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = items.firstIndex(where: { $0.card == dragging }),
              let to = items.firstIndex(where: { $0.card == target }) else { return }
        var next = items
        next.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { items = next }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Catches a drop between cards, so the dragged card never stays faded.
struct HomeDropEndDelegate: DropDelegate {
    @Binding var dragging: HomeCard?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// A card that can't draw on this day (a today-only card on a past day, or one that needs the
/// day's data before it has synced), shown only while editing so it can still be moved,
/// resized or removed.
struct HomeCardPlaceholder: View {
    let card: HomeCard
    let size: CardSize
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: card.icon)
                .font(.title3)
                .foregroundStyle(Theme.tertiary)
            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
            Text(reason)
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: size == .large ? 2 * HomeGlanceMetrics.height + 14 : HomeGlanceMetrics.height)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.cardBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}
