//
//  CameraResetScreen.swift
//  Sandbox
//
//  A camera that has been set up before will not advertise itself until it is
//  reset, which is the most common reason discovery finds nothing.
//

import SwiftUI
import IVSDK

struct CameraResetScreen: View {
    let device: DeviceModel?
    let screenFrom: ScreenFrom
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        PairingStepScreen(
            step: 1,
            total: 5,
            title: "Reset the camera",
            subtitle: "A reset clears the previous network so the camera can be set up again.",
            bullets: [
                "Find the pinhole marked RESET on the back or underside of the camera.",
                "Press and hold it with the reset pin for ten seconds.",
                "Let go when you hear the chime and the light starts blinking blue."
            ],
            primaryTitle: "Done — the light is blinking",
            secondaryTitle: "Still not working",
            onPrimary: {
                pilot.push(.cameraSearch(screenFrom: screenFrom))
            },
            onSecondary: {
                pilot.push(.troubleshootCamera(screenFrom: screenFrom))
            },
            illustration: { PairingIllustration(systemName: "arrow.counterclockwise.circle") },
            screenFrom: screenFrom
        )
    }
}
