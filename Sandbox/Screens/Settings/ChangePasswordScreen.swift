//
//  ChangePasswordScreen.swift
//  Sandbox
//

import SwiftUI
import Combine
import IVSDK

final class ChangePasswordViewModel: ObservableObject {

    @Published var currentPassword = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var confirmError: String?
    @Published var result = ResultWrapper()
    @Published var changed = false

    @AppStorage(AppStorageKey.userDetails.rawValue) var user: UserModel?

    private let userService: UserServiceContract
    private var cancellable: AnyCancellable?

    init(userService: UserServiceContract = Factory.userService) {
        self.userService = userService
    }

    var rules: [PasswordRule] { Validation.passwordRules(newPassword) }

    var canSubmit: Bool {
        currentPassword.isNotEmpty
            && Validation.isValidPassword(newPassword)
            && newPassword == confirmPassword
    }

    func change() {
        guard newPassword == confirmPassword else {
            confirmError = "Passwords do not match"
            return
        }
        // Reusing the current password would succeed server-side but is never
        // what the user meant to do.
        guard newPassword != currentPassword else {
            confirmError = "Choose a password you have not used before"
            return
        }
        confirmError = nil
        result.update(data: .loading)

        cancellable = userService.changePassword(email: user?.email ?? "",
                                                 currentPassword: currentPassword,
                                                 newPassword: newPassword,
                                                 languageCode: Locale.current.identifier)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.result.update(data: .success)
                    self?.changed = true
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}

struct ChangePasswordScreen: View {
    @StateObject var viewModel: ChangePasswordViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Change password") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 18) {
                            AppTextField(placeholder: "Current password",
                                         text: $viewModel.currentPassword,
                                         isSecure: true)
                            AppTextField(placeholder: "New password",
                                         text: $viewModel.newPassword,
                                         isSecure: true)
                            AppTextField(placeholder: "Confirm new password",
                                         text: $viewModel.confirmPassword,
                                         isSecure: true,
                                         errorText: viewModel.confirmError)

                            if !viewModel.newPassword.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(viewModel.rules) { rule in
                                        HStack(spacing: 8) {
                                            Image(systemName: rule.satisfied ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 13))
                                                .foregroundColor(rule.satisfied ? AppColors.success : AppColors.textDisabled)
                                            Text(rule.text)
                                                .font(AppFont.caption(12))
                                                .foregroundColor(rule.satisfied ? AppColors.textSecondary : AppColors.textDisabled)
                                        }
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppColors.surface)
                                .cornerRadius(12)
                            }

                            PrimaryButton(title: "Update password", enabled: viewModel.canSubmit) {
                                viewModel.change()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
        .onChange(of: viewModel.changed) { changed in
            if changed { pilot.pop() }
        }
    }
}
