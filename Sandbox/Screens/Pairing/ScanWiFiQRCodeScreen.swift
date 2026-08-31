//
//  ScanWiFiQRCodeScreen.swift
//  Sandbox
//
//  The phone shows a code and the camera reads it with its own lens. Nothing
//  about the scan is observable from here — the only feedback is the session
//  status endpoint changing, and the camera's chime.
//

import SwiftUI
import Combine
import IVSDK

final class ScanWiFiQRCodeViewModel: PairingSessionViewModel {

    @Published var secondsRemaining = Int(AppConfig.pairingSessionTimeout)

    let payload: PairingPayload
    private var countdown: Timer?

    init(sharedData: SharedDataStore, payload: PairingPayload) {
        self.payload = payload
        super.init(sharedData: sharedData)
        // The screen is reached with a key already minted, so adopt it rather
        // than asking for a second one.
        self.sessionKeyModel = PairingSessionKeyModel(sessionKey: payload.sessionKey,
                                                      region: payload.region)
    }

    var qrImage: UIImage? {
        QRCodeGenerator.generateQRCode(from: payload.qrCodeString, size: 400)
    }

    var progress: Double {
        1 - (Double(secondsRemaining) / AppConfig.pairingSessionTimeout)
    }

    var countdownText: String {
        String(format: "%d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    func start() {
        startPollingSessionStatus()

        countdown?.invalidate()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if self.secondsRemaining > 0 {
                self.secondsRemaining -= 1
            } else {
                timer.invalidate()
                // The backend expires the key at the same moment; failing
                // locally keeps the message immediate.
                self.stopPolling()
                self.pairFailure = .qrNotScanned
            }
        }
    }

    func stop() {
        countdown?.invalidate()
        countdown = nil
        stopPolling()
    }
}

struct ScanWiFiQRCodeScreen: View {
    @StateObject var viewModel: ScanWiFiQRCodeViewModel
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @State private var showQuitConfirm = false
    /// Screen brightness is raised so the camera can read the code, then put
    /// back exactly as the user had it.
    @State private var previousBrightness = UIScreen.main.brightness

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    PairingNavBar(screenFrom: screenFrom, showQuitConfirm: $showQuitConfirm)

                    ScrollView {
                        VStack(spacing: 22) {
                            StepHeader(step: 4, total: 5,
                                       title: "Show this to your camera",
                                       subtitle: "Hold the screen 8–12 inches from the lens until the camera chimes.")
                                .padding(.horizontal, 24)

                            if let image = viewModel.qrImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(22)
                            } else {
                                Text("Could not draw the setup code.")
                                    .font(AppFont.body(14))
                                    .foregroundColor(AppColors.error)
                            }

                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    ProgressView().tint(AppColors.primary).scaleEffect(0.8)
                                    Text("Waiting for the camera…")
                                        .font(AppFont.body(14))
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                Text("Code expires in \(viewModel.countdownText)")
                                    .font(AppFont.caption(12))
                                    .foregroundColor(viewModel.secondsRemaining < 30
                                                     ? AppColors.warning : AppColors.textDisabled)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                tip("Wipe the lens if the camera has been outdoors.")
                                tip("Move somewhere less bright if the screen is reflecting.")
                                tip("Tilt the phone slowly rather than holding it dead straight.")
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.bottom, 24)
                    }

                    SecondaryButton(title: "The camera is not reading it") {
                        viewModel.stop()
                        pilot.push(.pairCameraError(reason: .qrNotScanned, screenFrom: screenFrom))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }, result: $viewModel.result)
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.start()
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.stop()
        }
        .onChange(of: viewModel.readyForActivation) { ready in
            guard ready else { return }
            pilot.pop(andPush: .cameraAuthEmail(deviceId: viewModel.pairedDeviceId,
                                                screenFrom: screenFrom))
        }
        .onChange(of: viewModel.pairedDeviceId) { deviceId in
            // The camera has been seen but is still coming up — move to the
            // status screen so the user gets progress instead of a stale code.
            guard !deviceId.isEmpty, !viewModel.readyForActivation else { return }
            pilot.pop(andPush: .retrievePairingStatus(sessionKey: viewModel.payload.sessionKey,
                                                      deviceId: deviceId,
                                                      screenFrom: screenFrom))
        }
        .onChange(of: viewModel.pairFailure) { failure in
            guard let failure else { return }
            pilot.pop(andPush: .pairCameraError(reason: failure, screenFrom: screenFrom))
        }
        .overlay {
            if showQuitConfirm {
                AppAlertView(shown: $showQuitConfirm,
                             title: "Stop setting up?",
                             okTitle: "Stop setup",
                             cancelTitle: "Keep going", onOk: {
                    pilot.quitPairing(screenFrom: screenFrom)
                })
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 11))
                .foregroundColor(AppColors.accent)
            Text(text)
                .font(AppFont.caption(12))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
