//
//  LoginViewModel.swift
//  Sandbox
//

import SwiftUI
import Combine
import AuthenticationServices
import GoogleSignIn
import FirebaseAuth
import IVSDK

final class LoginViewModel: ObservableObject {

    @Published var email = ""
    @Published var password = ""
    @Published var rememberMe = false
    @Published var emailError: String?
    @Published var result = ResultWrapper()

    /// Set once a sign-in resolves; the screen navigates when it changes.
    @Published var destination: Destination?

    @AppStorage(AppStorageKey.userDetails.rawValue) var user: UserModel?
    @AppStorage(AppStorageKey.isLoggedIn.rawValue) var isLoggedIn: Bool?
    @AppStorage(AppStorageKey.lastLoggedInUser.rawValue) var lastLoggedInUser: LastLoggedInUserModel?
    @AppStorage(AppStorageKey.loginType.rawValue) var loginTypeRaw: String?

    private let userService: UserServiceContract
    private let sharedData: SharedDataStore
    private let spaceDataStore: SpaceDataStore

    private var signInCancellable: AnyCancellable?
    private var userCancellable: AnyCancellable?
    private var spaceCancellable: AnyCancellable?

    init(sharedData: SharedDataStore,
         spaceDataStore: SpaceDataStore,
         userService: UserServiceContract = Factory.userService) {
        self.sharedData = sharedData
        self.spaceDataStore = spaceDataStore
        self.userService = userService

        // Prefill from the last successful sign-in, if the user opted in.
        if let lastLoggedInUser {
            email = lastLoggedInUser.email
            rememberMe = true
        }
    }

    var canSubmit: Bool {
        email.isNotEmpty && password.isNotEmpty
    }

    // MARK: - Email

    func loginTapped() {
        guard Validation.isValidEmail(email.trim) else {
            emailError = "Enter a valid email address"
            return
        }
        emailError = nil
        result.update(data: .loading)

        signInCancellable = userService.signin(email: email.trim, password: password)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(user):
                    self?.loginTypeRaw = UserLoginType.email.rawValue
                    self?.handleSignedIn(user)
                case let .error(error):
                    self?.handle(error)
                @unknown default:
                    break
                }
            }
    }

    func signInWithGoogleTapped() {
        result.update(data: .loading)
        signInCancellable = userService.signinWithGoogle()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(user):
                    self?.loginTypeRaw = UserLoginType.google.rawValue
                    self?.handleSignedIn(user)
                case let .error(error):
                    // A user backing out of the provider sheet is not an error.
                    if let error = error as? GIDSignInError, error.code == .canceled {
                        self?.result.update(data: .success)
                    } else {
                        self?.handle(error)
                    }
                @unknown default:
                    break
                }
            }
    }

    func signInWithAppleTapped() {
        result.update(data: .loading)
        signInCancellable = userService.signinWithApple()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(user):
                    self?.loginTypeRaw = UserLoginType.apple.rawValue
                    self?.handleSignedIn(user)
                case let .error(error):
                    if let error = error as? ASAuthorizationError, error.code == .canceled {
                        self?.result.update(data: .success)
                    } else {
                        self?.handle(error)
                    }
                @unknown default:
                    break
                }
            }
    }

    // MARK: - Post sign-in routing

    /// The gate every sign-in path funnels through:
    /// unverified email -> verification screen, otherwise carry on to spaces.
    private func handleSignedIn(_ user: UserModel) {
        self.user = user
        lastLoggedInUser = rememberMe
            ? LastLoggedInUserModel(name: user.name, email: user.email, country: user.country)
            : nil

        guard user.emailVerified == true else {
            destination = .emailVerify(autoTriggerEmail: true)
            result.update(data: .success)
            return
        }
        fetchUserThenSpaces()
    }

    /// Re-reads the profile before routing. Sign-in returns whatever the auth
    /// provider knew; this is the app's own record, including a verification
    /// flag that may have flipped since the token was issued.
    private func fetchUserThenSpaces() {
        userCancellable = userService.getUser()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(user):
                    self?.user = user
                    self?.fetchSpaces()
                case let .error(error):
                    self?.handle(error)
                @unknown default:
                    break
                }
            }
    }

    private func fetchSpaces() {
        spaceCancellable = spaceDataStore.fetchSpaces()
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(spaces):
                    // Owning no space means setup never finished — send the
                    // user to create one before the app has anything to show.
                    if spaces.filter({ SpaceRoleType(rawValue: $0.role ?? "") == .owner }).isEmpty {
                        self.destination = .spaceScreen(space: nil)
                    } else {
                        self.isLoggedIn = true
                        self.destination = .appTabBar
                    }
                    self.result.update(data: .success)
                case let .error(error):
                    self.handle(error)
                @unknown default:
                    break
                }
            }
    }

    private func handle(_ error: Error) {
        Logger.debugLog("Login failed:", error.localizedDescription)
        // Firebase reports every bad-credential shape with its own code; the
        // user only needs to know the pair did not match.
        if let code = AuthErrorCode(rawValue: (error as NSError).code),
           [.invalidEmail, .invalidCredential, .wrongPassword, .userNotFound].contains(code) {
            result.update(data: .error(error: IVError.invalidCredential))
        } else {
            result.update(data: .error(error: error))
        }
    }
}
