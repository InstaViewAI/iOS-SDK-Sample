//
//  PairingScaffold.swift
//  Sandbox
//
//  Pairing is a long sequence of near-identical instruction screens. They
//  share this layout so each one only describes what is different: its
//  artwork, its copy, and where its buttons go.
//

import SwiftUI

struct PairingStepScreen<Illustration: View>: View {
    let step: Int
    let total: Int
    let title: String
    let subtitle: String
    var bullets: [String] = []
    var primaryTitle: String = "Continue"
    var secondaryTitle: String?
    let onPrimary: () -> Void
    var onSecondary: (() -> Void)?
    @ViewBuilder var illustration: Illustration

    @EnvironmentObject private var pilot: UIPilot<Destination>
    let screenFrom: ScreenFrom
    @State private var showQuitConfirm = false

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                PairingNavBar(screenFrom: screenFrom, showQuitConfirm: $showQuitConfirm)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        StepHeader(step: step, total: total, title: title, subtitle: subtitle)

                        illustration
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            .background(AppColors.surface)
                            .cornerRadius(18)

                        if !bullets.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(bullets.enumerated()), id: \.offset) { index, bullet in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(AppFont.caption(11))
                                            .foregroundColor(AppColors.primary)
                                            .frame(width: 20, height: 20)
                                            .background(AppColors.primarySoft)
                                            .clipShape(Circle())
                                        Text(bullet)
                                            .font(AppFont.body(14))
                                            .foregroundColor(AppColors.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: primaryTitle, action: onPrimary)
                    if let secondaryTitle, let onSecondary {
                        SecondaryButton(title: secondaryTitle, action: onSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .overlay {
            if showQuitConfirm {
                AppAlertView(shown: $showQuitConfirm,
                             title: "Stop setting up?",
                             message: "Your camera will not be added and you will have to start again.",
                             okTitle: "Stop setup",
                             cancelTitle: "Keep going", onOk: {
                    pilot.quitPairing(screenFrom: screenFrom)
                })
            }
        }
    }
}

/// Back plus an always-available exit, since the pairing flow can be many
/// screens deep by the time a user gives up on it.
struct PairingNavBar: View {
    let screenFrom: ScreenFrom
    @Binding var showQuitConfirm: Bool
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        HStack {
            Button { pilot.pop() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(AppColors.surface)
                    .clipShape(Circle())
            }
            Spacer()
            Button { showQuitConfirm = true } label: {
                Text("Exit")
                    .font(AppFont.medium(14))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// A framed icon, standing in for the artwork the production app ships.
struct PairingIllustration: View {
    let systemName: String
    var accent: Color = AppColors.primary

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: 132, height: 132)
            Image(systemName: systemName)
                .font(.system(size: 54, weight: .light))
                .foregroundColor(accent)
        }
    }
}

extension UIPilot<Destination> {
    /// Where "Exit" lands. Pairing can be entered from three places and each
    /// has a different sensible destination.
    func quitPairing(screenFrom: ScreenFrom) {
        BLEManager.instance.disconnect()
        switch screenFrom {
        case .onboarding, .home, .security, .securitySettings:
            popTo(.appTabBar)
        case .cameraSettings:
            // Unwind to the camera the user was configuring, if it is still
            // on the stack; otherwise fall back to the tab bar.
            if routes.contains(where: { if case .cameraSettings = $0 { return true } else { return false } }),
               let route = routes.last(where: { if case .cameraSettings = $0 { return true } else { return false } }) {
                popTo(route)
            } else {
                popTo(.appTabBar)
            }
        }
    }
}
