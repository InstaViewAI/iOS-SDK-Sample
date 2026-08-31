//
//  BleWiFiScanFailScreen.swift
//  Sandbox
//

import SwiftUI

struct BleWiFiScanFailScreen: View {
    let screenFrom: ScreenFrom
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        PairingStepScreen(
            step: 3,
            total: 5,
            title: "The camera found no networks",
            subtitle: "It could not pick up any Wi-Fi from where it is sitting.",
            bullets: [
                "Move the camera closer to your router and try again.",
                "Confirm your router is broadcasting a 2.4 GHz network — cameras cannot join 5 GHz.",
                "Hidden networks will not appear here; enter one manually instead."
            ],
            primaryTitle: "Scan again",
            secondaryTitle: "Enter a network manually",
            onPrimary: {
                pilot.pop(andPush: .cameraSearch(screenFrom: screenFrom))
            },
            onSecondary: {
                pilot.push(.selectWiFi(mode: .bluetooth, ssid: nil, screenFrom: screenFrom))
            },
            illustration: { PairingIllustration(systemName: "wifi.slash", accent: AppColors.warning) },
            screenFrom: screenFrom
        )
    }
}
