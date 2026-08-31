//
//  AppWindowManager.swift
//  Sandbox
//
//  App-wide chrome (loader, session state) that individual screens should not
//  each own a copy of.
//

import SwiftUI
import Combine
import IVSDK

final class AppWindowManager: ObservableObject {

    enum RootWindow: Equatable {
        case onboarding
        case appTabBar
    }

    @Published var rootWindow: RootWindow = .onboarding
    @Published var isLoading = false
    @Published var loaderMessage = ""
    @Published var toastMessage: String?

    @AppStorage(AppStorageKey.userDetails.rawValue) var user: UserModel?
    @AppStorage(AppStorageKey.isLoggedIn.rawValue) var isLoggedIn: Bool?

    /// Held for the lifetime of the request. A discarded `AnyCancellable`
    /// cancels its subscription immediately, so the sink never runs and the
    /// loader never comes down.
    private var logoutCancellable: AnyCancellable?

    init() {
        // A stored user alone is not enough — `isLoggedIn` is only set once the
        // account has cleared email verification and owns a space, so a
        // half-finished signup resumes at onboarding rather than a blank home.
        if user != nil, isLoggedIn == true {
            rootWindow = .appTabBar
        } else {
            Factory.userService.localLogout()
            rootWindow = .onboarding
        }
    }

    func showLoader(_ message: String = "") {
        loaderMessage = message
        isLoading = true
    }

    func hideLoader() {
        isLoading = false
        loaderMessage = ""
    }

    /// Signs out on the server, then tears down locally.
    func signOut() {
        showLoader("Signing out…")
        logoutCancellable = Factory.userService.logout()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success, .error:
                    // Local state is cleared either way — a failed server
                    // logout must not strand the user in a signed-in shell.
                    self?.hideLoader()
                    self?.logout()
                @unknown default:
                    break
                }
            }
    }

    /// Teardown for a deleted account.
    ///
    /// Everything `logout()` does, plus the state a sign-out deliberately
    /// keeps: the remembered email, the provider last used, and the saved
    /// Wi-Fi password. Those exist to make signing back in easier, which is
    /// meaningless once the account is gone — and leaving the address on the
    /// login screen makes it look as though the deletion did not take.
    func accountDeleted() {
        let defaults = UserDefaults.standard
        for key: AppStorageKey in [.lastLoggedInUser, .loginType, .rememberedWiFiPassword,
                                   .currentSpace, .userDetails, .isLoggedIn] {
            defaults.removeObject(forKey: key.rawValue)
        }
        logout()
    }

    func logout() {
        // Tear down every WebRTC session first. They are keyed by space and
        // device, and would otherwise outlive the account that opened them.
        LiveViewObjectStore.logout()
        NotificationCenter.default.post(name: .userLogout, object: nil)
        Factory.userService.localLogout()
        user = nil
        isLoggedIn = false
        rootWindow = .onboarding
    }
}
