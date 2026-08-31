//
//  EmailVerifyViewModel.swift
//  Sandbox
//
//  Holds the account until the address is confirmed. Verification happens in
//  the user's mail client, off-device, so the only way to notice is to keep
//  re-reading the profile until the flag flips.
//

import SwiftUI
import Combine
import IVSDK

final class EmailVerifyViewModel: ObservableObject {

    @Published var result = ResultWrapper()
    @Published var destination: Destination?
    @Published var showVerifiedAlert = false
    @Published var showEmailSentAlert = false
    /// Seconds until "Resend" becomes tappable again.
    @Published var resendCooldown = 0

    @AppStorage(AppStorageKey.userDetails.rawValue) var user: UserModel?
    @AppStorage(AppStorageKey.isLoggedIn.rawValue) var isLoggedIn: Bool?

    private let userService: UserServiceContract
    private let spaceDataStore: SpaceDataStore

    private var sendCancellable: AnyCancellable?
    private var userCancellable: AnyCancellable?
    private var spaceCancellable: AnyCancellable?
    private var logoutCancellable: AnyCancellable?

    private var pollWorkItem: DispatchWorkItem?
    private var cooldownTimer: Timer?

    init(spaceDataStore: SpaceDataStore,
         userService: UserServiceContract = Factory.userService) {
        self.spaceDataStore = spaceDataStore
        self.userService = userService
    }

    deinit {
        pollWorkItem?.cancel()
        cooldownTimer?.invalidate()
    }

    var email: String { user?.email ?? "" }
    var canResend: Bool { resendCooldown == 0 }

    // MARK: - Sending

    /// `showAlert` is false on the automatic send when the screen opens, so
    /// the user is not greeted by a dialog they did not ask for.
    func sendVerificationEmail(showAlert: Bool) {
        stopPolling()
        result.update(data: .loading)

        sendCancellable = userService.sendVerificationEmail(languageCode: Locale.current.identifier)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.showEmailSentAlert = showAlert
                    self?.startResendCooldown()
                    self?.schedulePoll()
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    private func startResendCooldown() {
        resendCooldown = 60
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if self.resendCooldown > 0 {
                self.resendCooldown -= 1
            } else {
                timer.invalidate()
            }
        }
    }

    // MARK: - Polling

    private func schedulePoll() {
        pollWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.checkVerificationStatus() }
        pollWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: AppConfig.pollingDuration, execute: workItem)
    }

    func stopPolling() {
        pollWorkItem?.cancel()
        pollWorkItem = nil
    }

    private func checkVerificationStatus() {
        userCancellable = userService.getUser()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(user):
                    self?.user = user
                    if user.emailVerified == true {
                        self?.stopPolling()
                        self?.showVerifiedAlert = true
                    } else {
                        self?.schedulePoll()
                    }
                case let .error(error):
                    // Keep polling through transient failures — the user is
                    // sitting on this screen waiting for it to clear itself.
                    Logger.debugLog("Verification poll failed:", error.localizedDescription)
                    self?.schedulePoll()
                @unknown default:
                    break
                }
            }
    }

    // MARK: - Continue

    /// Called once the address is confirmed. Same fork as sign-in: no owned
    /// space means the user still has to create one.
    func continueAfterVerification() {
        result.update(data: .loading)
        spaceCancellable = spaceDataStore.fetchSpaces()
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(spaces):
                    if spaces.filter({ SpaceRoleType(rawValue: $0.role ?? "") == .owner }).isEmpty {
                        self.destination = .spaceScreen(space: nil)
                    } else {
                        self.isLoggedIn = true
                        self.destination = .appTabBar
                    }
                    self.result.update(data: .success)
                case let .error(error):
                    self.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    func logout(completion: @escaping () -> Void) {
        stopPolling()
        logoutCancellable = userService.logout()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    self?.result.update(data: .loading)
                case .success, .error:
                    // Local state is cleared either way; a failed server
                    // logout must not strand the user on this screen.
                    self?.user = nil
                    self?.isLoggedIn = false
                    self?.result.update(data: .success)
                    completion()
                @unknown default:
                    break
                }
            }
    }

    func openMailApp() {
        if let url = URL(string: "message://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
