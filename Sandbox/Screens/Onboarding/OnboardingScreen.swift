//
//  OnboardingScreen.swift
//  Sandbox
//
//  Signed-out landing screen. Routes to sign in or create account.
//

import SwiftUI

struct OnboardingScreen: View {
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(AppColors.primarySoft)
                            .frame(width: 112, height: 112)
                        Image(systemName: "video.badge.checkmark")
                            .font(.system(size: 46, weight: .light))
                            .foregroundColor(AppColors.primary)
                    }

                    VStack(spacing: 10) {
                        Text("Sandbox")
                            .font(AppFont.title(34))
                            .foregroundColor(AppColors.textPrimary)
                        Text("Set up your cameras, watch what matters,\nand keep an eye on every space.")
                            .font(AppFont.body(15))
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    PrimaryButton(title: "Create account") {
                        pilot.push(.signUp)
                    }
                    SecondaryButton(title: "I already have an account") {
                        pilot.push(.login)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}
