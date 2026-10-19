import SwiftUI
import UIKit

// MARK: - Swipe back from anywhere

extension View {
    /// Inside a NavigationStack: a pushed screen goes back with a swipe to the right that starts
    /// anywhere on it, not only at the left edge.
    func swipeBackFromAnywhere() -> some View {
        background(SwipeBackInstaller().frame(width: 0, height: 0))
    }
}

/// Finds the navigation controller behind the NavigationStack once the screen is on and gives
/// it a full-width back swipe (FullSwipeBack).
private struct SwipeBackInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            let viaResponders = sequence(first: view as UIResponder, next: { $0.next })
                .first { $0 is UINavigationController } as? UINavigationController
            if let nav = navigationController ?? viaResponders {
                FullSwipeBack.install(on: nav)
            } else {
                DebugLog.note("swipe back: no navigation controller")
            }
        }
    }
}

/// A pan over the whole screen that goes back once it has moved about 70 points to the right
/// (or on a quick flick), with the usual back animation. It starts only for a swipe to the
/// right, mostly sideways, on a pushed screen, and leaves alone horizontal scrollers that can
/// still scroll back and controls such as switches and steppers. A swipe from the very left
/// edge is left to the system's own back swipe, which follows the finger.
///
/// (Handing this pan to that swipe's own handler, as UIKit apps have done, starts nothing in a
/// SwiftUI navigation stack, so it only uses public calls.)
@MainActor
enum FullSwipeBack {
    static func install(on nav: UINavigationController) {
        guard !(nav.view.gestureRecognizers ?? []).contains(where: { $0 is FullSwipeBackPan }) else { return }
        // iOS 26 swipes back from anywhere by itself.
        if nav.responds(to: NSSelectorFromString("interactiveContentPopGestureRecognizer")),
           let content = nav.value(forKey: "interactiveContentPopGestureRecognizer") as? UIGestureRecognizer,
           content.isEnabled {
            DebugLog.note("swipe back: the system's own content swipe is on")
            return
        }
        let rules = FullSwipeBackRules(nav: nav)
        let pan = FullSwipeBackPan(target: rules, action: #selector(FullSwipeBackRules.panned(_:)))
        pan.rules = rules
        pan.delegate = rules
        pan.maximumNumberOfTouches = 1
        nav.view.addGestureRecognizer(pan)
        DebugLog.note("swipe back: installed on \(type(of: nav))")
    }
}

private final class FullSwipeBackPan: UIPanGestureRecognizer {
    /// The delegate, kept alive by the pan (a recognizer holds its delegate weakly).
    var rules: FullSwipeBackRules?
}

@MainActor
private final class FullSwipeBackRules: NSObject, UIGestureRecognizerDelegate {
    weak var nav: UINavigationController?
    /// This swipe has gone back already.
    private var popped = false

    init(nav: UINavigationController) {
        self.nav = nav
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let nav, nav.viewControllers.count > 1, nav.transitionCoordinator == nil,
              let pan = gesture as? UIPanGestureRecognizer else { return false }
        let v = pan.velocity(in: pan.view)
        let t = pan.translation(in: pan.view)
        let startX = pan.location(in: pan.view).x - t.x
        // At the very edge the system's own swipe takes it.
        let begin = startX > 24 && v.x > 0 && v.x > abs(v.y) * 1.2 && !inScrollerThatCanScrollBack(pan)
        DebugLog.note("swipe back: start x \(Int(startX)), velocity \(Int(v.x)),\(Int(v.y)) -> \(begin ? "begins" : "no")")
        return begin
    }

    @objc func panned(_ pan: UIPanGestureRecognizer) {
        let t = pan.translation(in: pan.view)
        switch pan.state {
        case .began:
            popped = false
        case .changed:
            if t.x > 70, t.x > abs(t.y) * 1.5 { goBack(t) }
        case .ended:
            if t.x > 24, pan.velocity(in: pan.view).x > 450 { goBack(t) }
        default:
            break
        }
    }

    private func goBack(_ t: CGPoint) {
        guard !popped, let nav, nav.viewControllers.count > 1, nav.transitionCoordinator == nil else { return }
        popped = true
        DebugLog.note("swipe back: back at \(Int(t.x))")
        nav.popViewController(animated: true)
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let v = view {
            if v is UIControl { return false }
            view = v.superview
        }
        return true
    }

    /// A horizontal scroller under the finger that isn't at its start yet scrolls instead.
    private func inScrollerThatCanScrollBack(_ pan: UIPanGestureRecognizer) -> Bool {
        horizontalScroller(under: pan, canScrollForward: false)
    }
}

/// True when a horizontal scroller under where `pan` started can still scroll that way (forward:
/// toward its end, as a swipe to the left does), so the swipe belongs to it.
@MainActor
private func horizontalScroller(under pan: UIPanGestureRecognizer, canScrollForward forward: Bool) -> Bool {
    guard let root = pan.view else { return false }
    let start = pan.location(in: root) - pan.translation(in: root)
    var view = root.hitTest(start, with: nil)
    while let v = view, v !== root {
        if let scroll = v as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 1 {
            let x = scroll.contentOffset.x
            let end = scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right
            if forward ? x < end - 1 : x > -scroll.adjustedContentInset.left + 1 { return true }
        }
        view = v.superview
    }
    return false
}

private func - (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x - b.x, y: a.y - b.y)
}

// MARK: - Swipe between days

extension View {
    /// On a NavigationStack's root screen: a sideways swipe calls `action` with 1 (a swipe to the
    /// left: the next day) or -1 (to the right: the day before) while `enabled`. Horizontal
    /// scrollers that can still scroll that way, such as a Smart Stack, keep their swipe.
    func onDaySwipe(enabled: Bool, perform action: @escaping (Int) -> Void) -> some View {
        background(DaySwipeInstaller(enabled: enabled, action: action).frame(width: 0, height: 0))
    }
}

private struct DaySwipeInstaller: UIViewControllerRepresentable {
    var enabled: Bool
    var action: (Int) -> Void

    func makeCoordinator() -> DaySwipeRules { DaySwipeRules() }

    func makeUIViewController(context: Context) -> Controller { Controller(rules: context.coordinator) }

    func updateUIViewController(_ controller: Controller, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.action = action
    }

    final class Controller: UIViewController {
        let rules: DaySwipeRules

        init(rules: DaySwipeRules) {
            self.rules = rules
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            let viaResponders = sequence(first: view as UIResponder, next: { $0.next })
                .first { $0 is UINavigationController } as? UINavigationController
            guard let nav = navigationController ?? viaResponders,
                  !(nav.view.gestureRecognizers ?? []).contains(where: { $0 is DaySwipePan }) else { return }
            rules.nav = nav
            let pan = DaySwipePan(target: rules, action: #selector(DaySwipeRules.panned(_:)))
            pan.rules = rules
            pan.delegate = rules
            pan.maximumNumberOfTouches = 1
            nav.view.addGestureRecognizer(pan)
        }
    }
}

private final class DaySwipePan: UIPanGestureRecognizer {
    /// The delegate, kept alive by the pan (a recognizer holds its delegate weakly).
    var rules: DaySwipeRules?
}

@MainActor
final class DaySwipeRules: NSObject, UIGestureRecognizerDelegate {
    weak var nav: UINavigationController?
    var enabled = true
    var action: (Int) -> Void = { _ in }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard enabled, let nav, nav.viewControllers.count == 1, nav.transitionCoordinator == nil,
              let pan = gesture as? UIPanGestureRecognizer else { return false }
        let v = pan.velocity(in: pan.view)
        guard abs(v.x) > abs(v.y) * 1.5 else { return false }
        return !horizontalScroller(under: pan, canScrollForward: v.x < 0)
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let v = view {
            if v is UIControl { return false }
            view = v.superview
        }
        return true
    }

    @objc func panned(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }
        let t = pan.translation(in: pan.view)
        let v = pan.velocity(in: pan.view)
        guard abs(t.x) > abs(t.y), abs(t.x) > 60 || (abs(t.x) > 24 && abs(v.x) > 500) else { return }
        DebugLog.note("day swipe: \(t.x < 0 ? "next" : "previous") day at \(Int(t.x))")
        action(t.x < 0 ? 1 : -1)
    }
}

// MARK: - Tap outside to hide the keyboard

extension View {
    /// While `active`, a tap anywhere outside `keep` (a frame in global coordinates) calls
    /// `action`, without taking the tap from the button or card under it.
    func onTapOutside(of keep: CGRect, active: Bool, perform action: @escaping () -> Void) -> some View {
        background(TapOutside(active: active, keep: keep, action: action).frame(width: 0, height: 0))
    }
}

/// A tap recognizer on the window (so it sees taps on every part of the screen) that only
/// watches: it never cancels or delays the touches it sees.
private struct TapOutside: UIViewRepresentable {
    var active: Bool
    var keep: CGRect
    var action: () -> Void

    func makeUIView(context: Context) -> Host { Host() }

    func updateUIView(_ host: Host, context: Context) {
        host.active = active
        host.keep = keep
        host.action = action
    }

    final class Host: UIView, UIGestureRecognizerDelegate {
        var active = false
        var keep: CGRect = .zero
        var action: () -> Void = {}
        private weak var installedOn: UIWindow?
        private lazy var tap: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            return tap
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            isUserInteractionEnabled = false
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window !== installedOn else { return }
            installedOn?.removeGestureRecognizer(tap)
            installedOn = window
            window?.addGestureRecognizer(tap)
        }

        @objc private func tapped() {
            action()
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            active && !keep.contains(touch.location(in: nil))
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - CI notes

/// CI only (FITSTATS_DEBUG_LOG, a file path the UI tests collect): how a gesture went, for the
/// cases a screenshot can't explain. Does nothing otherwise.
enum DebugLog {
    private static let path = ProcessInfo.processInfo.environment["FITSTATS_DEBUG_LOG"] ?? ""

    static func note(_ line: String) {
        guard !path.isEmpty else { return }
        let data = Data((line + "\n").utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
