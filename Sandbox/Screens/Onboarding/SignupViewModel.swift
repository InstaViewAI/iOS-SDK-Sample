//
//  SignupViewModel.swift
//  Sandbox
//

import SwiftUI
import Combine
import AuthenticationServices
import GoogleSignIn
import IVSDK

final class SignupViewModel: ObservableObject {

    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""
    @Published var phoneNumber = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var country = CountryOption.current
    @Published var acceptedTerms = false

    @Published var emailError: String?
    @Published var confirmError: String?
    @Published var result = ResultWrapper()
    @Published var destination: Destination?

    @AppStorage(AppStorageKey.userDetails.rawValue) var user: UserModel?
    @AppStorage(AppStorageKey.isLoggedIn.rawValue) var isLoggedIn: Bool?
    @AppStorage(AppStorageKey.loginType.rawValue) var loginTypeRaw: String?

    private let userService: UserServiceContract
    private let sharedData: SharedDataStore
    private let spaceDataStore: SpaceDataStore

    private var signupCancellable: AnyCancellable?
    private var spaceCancellable: AnyCancellable?

    init(sharedData: SharedDataStore,
         spaceDataStore: SpaceDataStore,
         userService: UserServiceContract = Factory.userService) {
        self.sharedData = sharedData
        self.spaceDataStore = spaceDataStore
        self.userService = userService
    }

    var passwordRules: [PasswordRule] { Validation.passwordRules(password) }

    var canSubmit: Bool {
        firstName.isNotEmpty
            && email.isNotEmpty
            && Validation.isValidPassword(password)
            && password == confirmPassword
            && acceptedTerms
    }

    private var languageCode: String {
        Locale.current.languageCode ?? "en"
    }

    func signupTapped() {
        guard Validation.isValidEmail(email.trim) else {
            emailError = "Enter a valid email address"
            return
        }
        guard password == confirmPassword else {
            confirmError = "Passwords do not match"
            return
        }
        emailError = nil
        confirmError = nil
        result.update(data: .loading)

        let request = SignupRequest(
            name: UserName(firstName: firstName.trim, lastName: lastName.trim),
            email: email.lowercased().trim,
            country: country.code,
            phoneNumber: PhoneNumber(code: country.dialCode, number: phoneNumber.trim),
            password: password,
            language: languageCode
        )

        signupCancellable = userService.signup(request: request)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(user):
                    self?.user = user
                    self?.loginTypeRaw = UserLoginType.email.rawValue
                    // A brand-new account is never verified, so this path
                    // always lands on the verification screen.
                    self?.destination = .emailVerify(autoTriggerEmail: true)
                    self?.result.update(data: .success)
                case let .error(error):
                    Logger.debugLog("Signup failed:", error.localizedDescription)
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    func signupWithGoogleTapped() {
        result.update(data: .loading)
        signupCancellable = userService.signupWithGoogle(languageCode: languageCode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleProvider(state, type: .google)
            }
    }

    func signupWithAppleTapped() {
        result.update(data: .loading)
        signupCancellable = userService.signupWithApple(languageCode: languageCode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleProvider(state, type: .apple)
            }
    }

    /// Google and Apple can hand back an already-verified address, so a
    /// provider signup may skip straight past verification into spaces.
    private func handleProvider(_ state: ResourceState<UserModel>, type: UserLoginType) {
        switch state {
        case .loading:
            break
        case let .success(user):
            self.user = user
            loginTypeRaw = type.rawValue
            if user.emailVerified == true {
                fetchSpaces()
            } else {
                destination = .emailVerify(autoTriggerEmail: true)
                result.update(data: .success)
            }
        case let .error(error):
            if let error = error as? GIDSignInError, error.code == .canceled {
                result.update(data: .success)
            } else if let error = error as? ASAuthorizationError, error.code == .canceled {
                result.update(data: .success)
            } else {
                result.update(data: .error(error: error))
            }
        @unknown default:
            break
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
}
