//
//  EmailVerifyScreen.swift
//  Sandbox
//

import SwiftUI

struct EmailVerifyScreen: View {
    @StateObject var viewModel: EmailVerifyViewModel
    let autoTriggerEmail: Bool

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @EnvironmentObject private var appWindowManager: AppWindowManager

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "")

                    ScrollView {
                        VStack(spacing: 24) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.primarySoft)
                                    .frame(width: 104, height: 104)
                                Image(systemName: "envelope.badge")
                                    .font(.system(size: 42, weight: .light))
                                    .foregroundColor(AppColors.primary)
                            }
                            .padding(.top, 20)

                            VStack(spacing: 10) {
                                Text("Confirm your email")
                                    .font(AppFont.title(28))
                                    .foregroundColor(AppColors.textPrimary)
                                Text("We sent a verification link to")
                                    .font(AppFont.body(15))
                                    .foregroundColor(AppColors.textSecondary)
                                Text(viewModel.email)
                                    .font(AppFont.medium(15))
                                    .foregroundColor(AppColors.primary)
                                Text("Open it on this device and we will take you\nstraight through — no need to come back here.")
                                    .font(AppFont.body(14))
                                    .foregroundColor(AppColors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 4)
                            }

                            HStack(spacing: 10) {
                                ProgressView().tint(AppColors.primary).scaleEffect(0.8)
                                Text("Waiting for confirmation…")
                                    .font(AppFont.caption(13))
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(AppColors.surface)
                            .cornerRadius(12)

                            VStack(spacing: 12) {
                                PrimaryButton(title: "Open Mail") {
                                    viewModel.openMailApp()
                                }
                                SecondaryButton(title: viewModel.canResend
                                                ? "Resend email"
                                                : "Resend in \(viewModel.resendCooldown)s") {
                                    guard viewModel.canResend else { return }
                                    viewModel.sendVerificationEmail(showAlert: true)
                                }
                            }

                            LinkButton(title: "Use a different account") {
                                viewModel.logout {
                                    appWindowManager.logout()
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear {
            if autoTriggerEmail {
                viewModel.sendVerificationEmail(showAlert: false)
            }
        }
        .onDisappear { viewModel.stopPolling() }
        .overlay {
            if viewModel.showEmailSentAlert {
                AppAlertView(shown: $viewModel.showEmailSentAlert,
                             title: "Email sent",
                             message: "Check your inbox for a fresh verification link.")
            }
            if viewModel.showVerifiedAlert {
                AppAlertView(shown: $viewModel.showVerifiedAlert,
                             title: "Email confirmed",
                             message: "Your address is verified. Let's finish setting up.",
                             okTitle: "Continue", onOk: {
                    viewModel.continueAfterVerification()
                })
            }
        }
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
