//
//  PairCameraErrorScreen.swift
//  Sandbox
//

import SwiftUI

struct PairCameraErrorScreen: View {
    let reason: PairFailureReason
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                NavBar(title: "")

                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(AppColors.error.opacity(0.14))
                            .frame(width: 120, height: 120)
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(AppColors.error)
                    }

                    VStack(spacing: 10) {
                        Text(reason.title)
                            .font(AppFont.title(26))
                            .foregroundColor(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(reason.message)
                            .font(AppFont.body(15))
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 10) {
                    PrimaryButton(title: "Try again") {
                        // Restart from credential entry — the session key is
                        // spent, so anything earlier would only be repeated.
                        pilot.pop(andPush: .scanCameraCode(screenFrom: screenFrom))
                    }
                    SecondaryButton(title: "Get help") {
                        pilot.push(.troubleshootCamera(screenFrom: screenFrom))
                    }
                    LinkButton(title: "Set this up later") {
                        pilot.quitPairing(screenFrom: screenFrom)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
    }
}
