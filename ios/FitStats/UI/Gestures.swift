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
            if let nav = navigationController ?? viaResponders { FullSwipeBack.install(on: nav) }
        }
    }
}

/// A pan over the whole screen that drives the navigation controller's own back-swipe
/// transition, so it follows the finger and can be cancelled halfway like the edge swipe. It
/// starts only for a swipe to the right, mostly sideways, on a pushed screen, and leaves alone
/// horizontal scrollers that can still scroll back and controls such as switches and steppers.
/// The edge swipe keeps working as before.
@MainActor
enum FullSwipeBack {
    static func install(on nav: UINavigationController) {
        guard !(nav.view.gestureRecognizers ?? []).contains(where: { $0 is FullSwipeBackPan }),
              let edge = nav.interactivePopGestureRecognizer else { return }
        // iOS 26 swipes back from anywhere by itself.
        if nav.responds(to: NSSelectorFromString("interactiveContentPopGestureRecognizer")),
           let content = nav.value(forKey: "interactiveContentPopGestureRecognizer") as? UIGestureRecognizer,
           content.isEnabled {
            return
        }
        // The edge swipe's own handler (UIKit has no public way to reach it).
        guard let targets = edge.value(forKey: "targets") as? [NSObject],
              let handler = targets.first?.value(forKey: "target") as? NSObject else { return }
        let action = NSSelectorFromString("handleNavigationTransition:")
        guard handler.responds(to: action) else { return }
        let pan = FullSwipeBackPan(target: handler, action: action)
        let rules = FullSwipeBackRules(nav: nav)
        pan.rules = rules
        pan.delegate = rules
        pan.maximumNumberOfTouches = 1
        // Near the left edge the system's swipe goes first, so only one of them drives the transition.
        pan.require(toFail: edge)
        nav.view.addGestureRecognizer(pan)
    }
}

private final class FullSwipeBackPan: UIPanGestureRecognizer {
    /// The delegate, kept alive by the pan (a recognizer holds its delegate weakly).
    var rules: FullSwipeBackRules?
}

@MainActor
private final class FullSwipeBackRules: NSObject, UIGestureRecognizerDelegate {
    weak var nav: UINavigationController?

    init(nav: UINavigationController) {
        self.nav = nav
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let nav, nav.viewControllers.count > 1, nav.transitionCoordinator == nil,
              let pan = gesture as? UIPanGestureRecognizer else { return false }
        let v = pan.velocity(in: pan.view)
        guard v.x > 0, v.x > abs(v.y) * 1.2 else { return false }
        return !inScrollerThatCanScrollBack(pan)
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
        guard let root = pan.view else { return false }
        var view = root.hitTest(pan.location(in: root), with: nil)
        while let v = view, v !== root {
            if let scroll = v as? UIScrollView,
               scroll.contentSize.width > scroll.bounds.width + 1,
               scroll.contentOffset.x > -scroll.adjustedContentInset.left + 1 {
                return true
            }
            view = v.superview
        }
        return false
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
