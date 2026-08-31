//
//  ForgotPasswordScreen.swift
//  Sandbox
//

import SwiftUI
import Combine
import IVSDK

final class ForgotPasswordViewModel: ObservableObject {
    @Published var email = ""
    @Published var emailError: String?
    @Published var sent = false
    @Published var result = ResultWrapper()

    private let userService: UserServiceContract
    private var cancellable: AnyCancellable?

    init(userService: UserServiceContract = Factory.userService) {
        self.userService = userService
    }

    var canSubmit: Bool { email.isNotEmpty }

    func sendResetEmail() {
        guard Validation.isValidEmail(email.trim) else {
            emailError = "Enter a valid email address"
            return
        }
        emailError = nil
        result.update(data: .loading)

        cancellable = userService.sendResetPasswordEmail(email.trim, languageCode: Locale.current.identifier)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.sent = true
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}

struct ForgotPasswordScreen: View {
    @StateObject var viewModel: ForgotPasswordViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "") { pilot.pop() }

                    VStack(alignment: .leading, spacing: 22) {
                        if viewModel.sent {
                            sentState
                        } else {
                            formState
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                }
            }
        }, result: $viewModel.result)
    }

    private var formState: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reset your password")
                    .font(AppFont.title(30))
                    .foregroundColor(AppColors.textPrimary)
                Text("Enter the email on your account and we will send you a reset link.")
                    .font(AppFont.body(15))
                    .foregroundColor(AppColors.textSecondary)
            }

            AppTextField(placeholder: "Email",
                         text: $viewModel.email,
                         keyboard: .emailAddress,
                         errorText: viewModel.emailError)

            PrimaryButton(title: "Send reset link", enabled: viewModel.canSubmit) {
                viewModel.sendResetEmail()
            }
        }
    }

    private var sentState: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(AppColors.success)
            Text("Check your inbox")
                .font(AppFont.title(26))
                .foregroundColor(AppColors.textPrimary)
            Text("If an account exists for \(viewModel.email), a reset link is on its way.")
                .font(AppFont.body(15))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Back to sign in") {
                pilot.pop()
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
