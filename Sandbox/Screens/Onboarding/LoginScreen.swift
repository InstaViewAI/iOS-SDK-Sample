//
//  LoginScreen.swift
//  Sandbox
//

import SwiftUI

struct LoginScreen: View {
    @StateObject var viewModel: LoginViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "") { pilot.pop() }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Welcome back")
                                    .font(AppFont.title(30))
                                    .foregroundColor(AppColors.textPrimary)
                                Text("Sign in to reach your spaces and cameras.")
                                    .font(AppFont.body(15))
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            VStack(spacing: 14) {
                                AppTextField(placeholder: "Email",
                                             text: $viewModel.email,
                                             keyboard: .emailAddress,
                                             errorText: viewModel.emailError)
                                AppTextField(placeholder: "Password",
                                             text: $viewModel.password,
                                             isSecure: true)
                            }

                            HStack {
                                AppCheckbox(checked: $viewModel.rememberMe, title: "Remember me")
                                Spacer()
                                LinkButton(title: "Forgot password?") {
                                    pilot.push(.forgotPassword)
                                }
                            }

                            PrimaryButton(title: "Sign in",
                                          enabled: viewModel.canSubmit) {
                                viewModel.loginTapped()
                            }

                            HStack(spacing: 12) {
                                Rectangle().fill(AppColors.border).frame(height: 1)
                                Text("or")
                                    .font(AppFont.caption())
                                    .foregroundColor(AppColors.textSecondary)
                                Rectangle().fill(AppColors.border).frame(height: 1)
                            }

                            VStack(spacing: 12) {
                                SocialButton(systemImage: "globe", title: "Continue with Google") {
                                    viewModel.signInWithGoogleTapped()
                                }
                                SocialButton(systemImage: "apple.logo", title: "Continue with Apple") {
                                    viewModel.signInWithAppleTapped()
                                }
                            }

                            HStack(spacing: 4) {
                                Text("New here?")
                                    .font(AppFont.body(14))
                                    .foregroundColor(AppColors.textSecondary)
                                LinkButton(title: "Create an account") {
                                    pilot.push(.signUp)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
        }, result: $viewModel.result)
        .onChange(of: viewModel.destination) { destination in
            guard let destination else { return }
            navigate(to: destination)
        }
    }

    private func navigate(to destination: Destination) {
        switch destination {
        case .appTabBar:
            // Signed in and set up — replace the stack so back cannot
            // return to the login screen.
            pilot.changeRoot(.appTabBar)
        default:
            pilot.push(destination)
        }
        viewModel.destination = nil
    }
}
