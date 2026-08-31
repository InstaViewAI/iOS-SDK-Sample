//
//  TurnOnCameraScreen.swift
//  Sandbox
//

import SwiftUI
import IVSDK

struct TurnOnCameraScreen: View {
    let device: DeviceModel?
    let screenFrom: ScreenFrom
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        PairingStepScreen(
            step: 1,
            total: 5,
            title: "Power on your camera",
            subtitle: "Plug the camera in and wait for it to finish starting up.",
            bullets: [
                "Connect the power adapter, or hold the power button for three seconds on a battery model.",
                "Wait for the status light to blink blue — that can take up to a minute.",
                "Keep the camera within arm's reach of your phone for the rest of setup."
            ],
            primaryTitle: "The light is blinking blue",
            secondaryTitle: "The light is off or a different colour",
            onPrimary: {
                pilot.push(.cameraSearch(screenFrom: screenFrom))
            },
            onSecondary: {
                pilot.push(.cameraReset(device: device, screenFrom: screenFrom))
            },
            illustration: { PairingIllustration(systemName: "poweroutlet.type.b.fill") },
            screenFrom: screenFrom
        )
    }
}
