//
//  Pilot.swift
//  Sandbox
//
//  A UINavigationController driven from a plain array of routes. SwiftUI's own
//  NavigationStack cannot express "pop three and push one" as a single
//  animation, which the pairing flow needs constantly, so the stack is kept
//  here and mirrored into UIKit.
//

import SwiftUI
import Combine
import UIKit

public class UIPilot<T: Equatable>: ObservableObject {
    private var _routes: [T] = []
    public var routes: [T] { _routes }

    var onPush: ((T, Bool, Int) -> Void)?
    var onChangeRoot: ((T, Bool) -> Void)?
    fileprivate var onPopLast: ((Int, Bool) -> Void)?

    public init(initial: T? = nil) {
        if let initial {
            push(initial, animated: false)
        }
    }

    /// Replaces the whole stack. Used when the app switches between the
    /// onboarding and signed-in worlds.
    public func changeRoot(_ route: T, animated: Bool = true) {
        _routes = [route]
        onChangeRoot?(route, animated)
    }

    public func push(_ route: T, animated: Bool = true) {
        guard _routes.last != route else { return }
        _routes.append(route)
        onPush?(route, animated, 0)
        resignKeyboard()
        Logger.debugLog("Pilot push -> \(route), depth \(_routes.count)")
    }

    /// Pops the top route, optionally replacing it in the same animation.
    public func pop(animated: Bool = true, andPush route: T? = nil) {
        guard !_routes.isEmpty else { return }
        _routes.removeLast()
        if let route {
            _routes.append(route)
            onPush?(route, animated, 1)
        } else {
            onPopLast?(1, animated)
        }
        resignKeyboard()
        Logger.debugLog("Pilot pop -> depth \(_routes.count)")
    }

    public func popLast(_ number: Int, animated: Bool = true) {
        let count = min(_routes.count, number)
        guard count > 0 else { return }
        _routes.removeLast(count)
        onPopLast?(count, animated)
        resignKeyboard()
    }

    /// Unwinds to an earlier screen. `inclusive` also removes that screen,
    /// which is how the pairing flow exits back past its own entry point.
    public func popTo(_ route: T, inclusive: Bool = false, animated: Bool = true, andPush newRoute: T? = nil) {
        guard !_routes.isEmpty else { return }
        guard var found = _routes.lastIndex(where: { $0 == route }) else {
            // The caller's intent was to end up somewhere. Honouring the push
            // leaves a slightly deeper stack, but silently doing nothing
            // strands the user on a screen they have finished with.
            Logger.debugLog("Pilot popTo — target not on stack:", route)
            if let newRoute {
                push(newRoute, animated: animated)
            }
            return
        }
        if !inclusive { found += 1 }

        let numToPop = (found..<_routes.endIndex).count
        guard numToPop > 0 || newRoute != nil else { return }
        _routes.removeLast(numToPop)

        if let newRoute {
            _routes.append(newRoute)
            onPush?(newRoute, animated, numToPop)
        } else {
            onPopLast?(numToPop, animated)
        }
        resignKeyboard()
    }

    /// Keeps the route array in step when the user swipes back.
    public func onSystemPop() {
        guard !_routes.isEmpty else { return }
        _routes.removeLast()
        resignKeyboard()
    }

    private func resignKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

public struct UIPilotHost<T: Equatable, Screen: View>: View {
    let pilot: UIPilot<T>
    @ViewBuilder let routeMap: (T) -> Screen

    public init(_ pilot: UIPilot<T>, @ViewBuilder _ routeMap: @escaping (T) -> Screen) {
        self.pilot = pilot
        self.routeMap = routeMap
    }

    public var body: some View {
        NavigationControllerHost(pilot: pilot, routeMap: routeMap)
            .ignoresSafeArea()
            .environmentObject(pilot)
    }
}

struct NavigationControllerHost<T: Equatable, Screen: View>: UIViewControllerRepresentable {
    let pilot: UIPilot<T>
    @ViewBuilder var routeMap: (T) -> Screen

    func makeUIViewController(context: Context) -> UINavigationController {
        let navigation = PopAwareNavigationController()
        // Screens draw their own headers via NavBar.
        navigation.isNavigationBarHidden = true
        navigation.popHandler = { pilot.onSystemPop() }
        navigation.stackSizeProvider = { pilot.routes.count }

        for route in pilot.routes {
            navigation.pushViewController(host(route), animated: false)
        }

        pilot.onPush = { route, animated, numToPop in
            navigation.pushViewController(host(route), animated: animated)
            // Splice out the screens being replaced, leaving the push animation
            // to run from the old top to the new one.
            if numToPop > 0, navigation.viewControllers.count > numToPop {
                let end = navigation.viewControllers.count - 1
                navigation.viewControllers.removeSubrange((end - numToPop)..<end)
            }
        }

        pilot.onChangeRoot = { route, _ in
            navigation.viewControllers = [host(route)]
        }

        pilot.onPopLast = { numToPop, animated in
            if numToPop >= navigation.viewControllers.count {
                navigation.popToRootViewController(animated: animated)
            } else {
                let target = navigation.viewControllers[navigation.viewControllers.count - numToPop - 1]
                navigation.popToViewController(target, animated: animated)
            }
        }

        return navigation
    }

    private func host(_ route: T) -> UIViewController {
        let controller = UIHostingController(rootView: routeMap(route))
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ navigation: UINavigationController, context: Context) {}

    static func dismantleUIViewController(_ navigation: UINavigationController, coordinator: ()) {
        (navigation as? PopAwareNavigationController)?.popHandler = nil
        navigation.viewControllers = []
    }
}

/// Reports interactive (swipe) pops back to the pilot, which UIKit otherwise
/// performs without telling anyone.
final class PopAwareNavigationController: UINavigationController, UINavigationControllerDelegate {
    var popHandler: (() -> Void)?
    var stackSizeProvider: (() -> Int)?

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        interactivePopGestureRecognizer?.delegate = nil
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        if let stackSizeProvider, stackSizeProvider() > navigationController.viewControllers.count {
            popHandler?()
        }
    }
}
