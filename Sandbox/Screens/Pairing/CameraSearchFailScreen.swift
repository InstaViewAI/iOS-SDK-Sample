//
//  CameraSearchFailScreen.swift
//  Sandbox
//

import SwiftUI

struct CameraSearchFailScreen: View {
    let screenFrom: ScreenFrom
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        PairingStepScreen(
            step: 2,
            total: 5,
            title: "No camera found",
            subtitle: "We could not pick up a camera in setup mode nearby.",
            bullets: [
                "Check the status light is blinking blue. If it is not, reset the camera.",
                "Move the phone within a metre of the camera.",
                "Make sure nobody else is setting up the same camera right now."
            ],
            primaryTitle: "Search again",
            secondaryTitle: "Set up with a QR code instead",
            onPrimary: {
                pilot.pop(andPush: .cameraSearch(screenFrom: screenFrom))
            },
            onSecondary: {
                pilot.push(.scanCameraCode(screenFrom: screenFrom))
            },
            illustration: { PairingIllustration(systemName: "wave.3.right.circle", accent: AppColors.warning) },
            screenFrom: screenFrom
        )
    }
}
