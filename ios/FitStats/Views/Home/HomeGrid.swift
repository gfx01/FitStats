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

/// A slight, endless wobble while Home is being edited, like the iOS Home Screen. It pauses
/// while `active` is false (a card being resized holds still) and is off with Reduce Motion.
struct Jiggle: ViewModifier {
    let amplitude: Double
    let seed: Int
    var active = true
    @State private var tilted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(reduceMotion || !active ? 0 : (tilted ? amplitude : -amplitude)))
            .onAppear { start() }
            .onChange(of: active) { _, on in
                if on { start() }
            }
    }

    private func start() {
        guard !reduceMotion, active else { return }
        tilted = false
        withAnimation(.easeInOut(duration: 0.13 + Double(seed % 4) * 0.015).repeatForever(autoreverses: true)) {
            tilted = true
        }
    }
}

/// A Home card in edit mode: it wobbles, can't be tapped through, has a remove button on its
/// top-left corner and a resize handle on its bottom-right one. Tapping it opens its settings;
/// holding it and dragging moves it (system drag and drop, see HomeDropDelegate).
///
/// Resizing works like iOS widgets: while the handle is dragged an outline follows the finger
/// (from small up to the large footprint), labelled with the size it will take, and the card
/// snaps to that size when the finger lifts.
struct HomeEditCell<Content: View>: View {
    let item: HomeItem
    let seed: Int
    let canRemove: Bool
    let isDragged: Bool
    var onRemove: () -> Void
    var onResize: (CardSize) -> Void
    var onMove: (Int) -> Void
    var onEdit: () -> Void
    /// True while the resize outline is up, so Today can draw this card above its neighbours.
    var onResizing: (Bool) -> Void
    var onDragStart: () -> NSItemProvider
    @ViewBuilder var content: () -> Content

    /// How far the resize handle has been dragged; nil when it isn't (also after a cancelled drag).
    @GestureState private var resizeDrag: CGSize? = nil
    @State private var cellSize: CGSize = .zero

    // Computed: a generic type can't have static stored properties. Same as HomeGridLayout.
    private static var columnSpacing: CGFloat { 12 }
    private static var rowSpacing: CGFloat { 14 }

    var body: some View {
        content()
            .allowsHitTesting(false)
            // Catches touches over the whole card: a tap opens its settings, holding anywhere
            // on it starts a drag.
            .overlay {
                Color.white.opacity(0.001)
                    .onTapGesture { onEdit() }
            }
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { cellSize = geo.size }
                        .onChange(of: geo.size) { _, size in cellSize = size }
                }
            }
            .overlay(alignment: .topLeading) {
                if let resizeDrag { outline(resizeDrag) }
            }
            .overlay(alignment: .topLeading) {
                if canRemove && resizeDrag == nil { removeButton }
            }
            .overlay(alignment: .bottomTrailing) {
                if resizeDrag == nil { resizeHandle }
            }
            .opacity(isDragged ? 0.35 : 1)
            .modifier(Jiggle(amplitude: amplitude, seed: seed, active: resizeDrag == nil))
            .onDrag(onDragStart)
            .sensoryFeedback(.selection, trigger: item.size)
            .sensoryFeedback(.selection, trigger: resizeDrag.map(target))
            .onChange(of: resizeDrag) { old, new in
                if (old == nil) != (new == nil) { onResizing(new != nil) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("\(item.title), \(item.size.label)"))
            .accessibilityHint(Text(item.card.hasSettings ? "Tap for its settings" : ""))
            .accessibilityActions {
                ForEach(item.card.sizes.filter { $0 != item.size }) { size in
                    Button("Make \(size.label.lowercased())") { onResize(size) }
                }
                if item.card.hasSettings { Button("Settings") { onEdit() } }
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

    // MARK: resize geometry

    /// The full row width: a small card is half of it.
    private var fullWidth: CGFloat {
        item.size == .small ? cellSize.width * 2 + Self.columnSpacing : cellSize.width
    }

    private var smallWidth: CGFloat { max(0, (fullWidth - Self.columnSpacing) / 2) }

    /// The tallest the outline goes: two glance rows, or the large card's own height if taller.
    private var largeHeight: CGFloat {
        let twoRows = 2 * HomeGlanceMetrics.height + Self.rowSpacing
        return item.size == .large ? max(twoRows, cellSize.height) : twoRows
    }

    private func outlineSize(_ t: CGSize) -> CGSize {
        let w = min(max(cellSize.width + t.width, smallWidth), fullWidth)
        let maxH = item.card.sizes.contains(.large) ? largeHeight : HomeGlanceMetrics.height
        let h = min(max(cellSize.height + t.height, min(HomeGlanceMetrics.height, cellSize.height)), maxH)
        return CGSize(width: w, height: h)
    }

    /// The size the card takes when the finger lifts: past halfway between two footprints it
    /// takes the bigger one. A one-column card can't be tall, so narrow means small.
    private func target(_ t: CGSize) -> CardSize {
        let o = outlineSize(t)
        let wide = o.width > (smallWidth + fullWidth) / 2
        let tall = o.height > (HomeGlanceMetrics.height + largeHeight) / 2
        let size: CardSize = !wide ? .small : (tall ? .large : .medium)
        return item.card.sizes.contains(size) ? size : .medium
    }

    private func outline(_ t: CGSize) -> some View {
        let o = outlineSize(t)
        return RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
            )
            .overlay {
                Text(target(t).label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white))
            }
            .frame(width: o.width, height: o.height)
            .allowsHitTesting(false)
    }

    // MARK: corner controls

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
        .accessibilityLabel(Text("Remove \(item.title)"))
        .accessibilityIdentifier("home-remove-\(item.id)")
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
                // Global space, so the wobble's rotation doesn't shake the outline.
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .updating($resizeDrag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        let size = target(value.translation)
                        if size != item.size { onResize(size) }
                    }
            )
            .onTapGesture { onResize(nextSize) }
            .accessibilityLabel(Text("Resize \(item.title)"))
            .accessibilityValue(Text(item.size.label))
            .accessibilityHint(Text("Drag to resize, or tap for the next size"))
            .accessibilityIdentifier("home-resize-\(item.id)")
    }

    private var nextSize: CardSize {
        let sizes = item.card.sizes
        guard let i = sizes.firstIndex(of: item.size) else { return item.card.defaultSize }
        return sizes[(i + 1) % sizes.count]
    }
}

/// Live reordering while a card is dragged over another one, like the iOS Home Screen.
struct HomeDropDelegate: DropDelegate {
    let target: String
    @Binding var items: [HomeItem]
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = items.firstIndex(where: { $0.id == dragging }),
              let to = items.firstIndex(where: { $0.id == target }) else { return }
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
    @Binding var dragging: String?

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
    let title: String
    let size: CardSize
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: card.icon)
                .font(.title3)
                .foregroundStyle(Theme.tertiary)
            Text(title)
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
