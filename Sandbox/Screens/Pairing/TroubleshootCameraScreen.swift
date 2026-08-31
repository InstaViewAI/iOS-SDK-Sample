//
//  TroubleshootCameraScreen.swift
//  Sandbox
//

import SwiftUI

struct TroubleshootCameraScreen: View {
    let screenFrom: ScreenFrom
    @EnvironmentObject private var pilot: UIPilot<Destination>

    private let tips: [(String, String, String)] = [
        ("bolt.slash", "No light at all",
         "Try a different outlet and cable. On battery models, charge for 30 minutes before trying again."),
        ("wifi.exclamationmark", "Camera cannot see your network",
         "Cameras join 2.4 GHz networks only. If your router publishes one name for both bands, split them or move closer to the router."),
        ("lock.shield", "Password rejected",
         "Passwords are case sensitive. Networks with a captive portal or sign-in page cannot be used."),
        ("dot.radiowaves.left.and.right", "Not found over Bluetooth",
         "Keep the phone within a metre of the camera, and make sure no other phone is already setting it up.")
    ]

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                NavBar(title: "Troubleshooting") { pilot.pop() }

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: tip.0)
                                    .font(.system(size: 18))
                                    .foregroundColor(AppColors.warning)
                                    .frame(width: 40, height: 40)
                                    .background(AppColors.warning.opacity(0.12))
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tip.1)
                                        .font(AppFont.medium(15))
                                        .foregroundColor(AppColors.textPrimary)
                                    Text(tip.2)
                                        .font(AppFont.body(13))
                                        .foregroundColor(AppColors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(16)
                            .background(AppColors.surface)
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                PrimaryButton(title: "Try setup again") {
                    pilot.pop()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}
