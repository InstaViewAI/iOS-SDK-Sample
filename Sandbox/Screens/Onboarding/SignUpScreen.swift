//
//  SignUpScreen.swift
//  Sandbox
//

import SwiftUI

struct SignUpScreen: View {
    @StateObject var viewModel: SignupViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "") { pilot.pop() }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Create your account")
                                    .font(AppFont.title(30))
                                    .foregroundColor(AppColors.textPrimary)
                                Text("You will confirm your email address on the next step.")
                                    .font(AppFont.body(15))
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            HStack(spacing: 12) {
                                AppTextField(placeholder: "First name",
                                             text: $viewModel.firstName,
                                             autocapitalization: .words)
                                AppTextField(placeholder: "Last name",
                                             text: $viewModel.lastName,
                                             autocapitalization: .words)
                            }

                            AppTextField(placeholder: "Email",
                                         text: $viewModel.email,
                                         keyboard: .emailAddress,
                                         errorText: viewModel.emailError)

                            HStack(spacing: 12) {
                                Menu {
                                    ForEach(CountryOption.all) { option in
                                        Button("\(option.name) (\(option.dialCode))") {
                                            viewModel.country = option
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(viewModel.country.dialCode)
                                            .font(AppFont.body(16))
                                            .foregroundColor(AppColors.textPrimary)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 52)
                                    .background(AppColors.surface)
                                    .cornerRadius(14)
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .stroke(AppColors.border, lineWidth: 1))
                                }

                                AppTextField(placeholder: "Phone number",
                                             text: $viewModel.phoneNumber,
                                             keyboard: .phonePad)
                            }

                            VStack(spacing: 14) {
                                AppTextField(placeholder: "Password",
                                             text: $viewModel.password,
                                             isSecure: true)
                                AppTextField(placeholder: "Confirm password",
                                             text: $viewModel.confirmPassword,
                                             isSecure: true,
                                             errorText: viewModel.confirmError)
                            }

                            if !viewModel.password.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(viewModel.passwordRules) { rule in
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

                            AppCheckbox(checked: $viewModel.acceptedTerms,
                                        title: "I agree to the Terms of Service and Privacy Policy")

                            PrimaryButton(title: "Create account",
                                          enabled: viewModel.canSubmit) {
                                viewModel.signupTapped()
                            }

                            HStack(spacing: 12) {
                                Rectangle().fill(AppColors.border).frame(height: 1)
                                Text("or").font(AppFont.caption()).foregroundColor(AppColors.textSecondary)
                                Rectangle().fill(AppColors.border).frame(height: 1)
                            }

                            VStack(spacing: 12) {
                                SocialButton(systemImage: "globe", title: "Sign up with Google") {
                                    viewModel.signupWithGoogleTapped()
                                }
                                SocialButton(systemImage: "apple.logo", title: "Sign up with Apple") {
                                    viewModel.signupWithAppleTapped()
                                }
                            }

                            HStack(spacing: 4) {
                                Text("Already have an account?")
                                    .font(AppFont.body(14))
                                    .foregroundColor(AppColors.textSecondary)
                                LinkButton(title: "Sign in") {
                                    pilot.pop(andPush: .login)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
        }, result: $viewModel.result)
        .onChange(of: viewModel.destination) { destination in
            guard let destination else { return }
            if case .appTabBar = destination {
                pilot.changeRoot(.appTabBar)
            } else {
                pilot.push(destination)
            }
            viewModel.destination = nil
        }
    }
}
