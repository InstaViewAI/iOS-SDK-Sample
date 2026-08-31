//
//  RetrievePairingStatusScreen.swift
//  Sandbox
//
//  The camera has what it needs and is registering itself. The app has no
//  channel to it, so all this screen can do is poll and wait.
//

import SwiftUI
import Combine
import IVSDK

final class RetrievePairingStatusViewModel: PairingSessionViewModel {

    @Published var elapsed = 0

    private var timer: Timer?

    init(sharedData: SharedDataStore, sessionKey: String, deviceId: String) {
        super.init(sharedData: sharedData)
        self.sessionKeyModel = PairingSessionKeyModel(sessionKey: sessionKey, region: "")
        self.pairedDeviceId = deviceId
    }

    func start() {
        startPollingSessionStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.elapsed += 1

            if self.elapsed >= Int(AppConfig.pairingSessionTimeout) {
                timer.invalidate()
                self.stopPolling()
                self.pairFailure = .cameraUnreachable
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stopPolling()
    }
}

struct RetrievePairingStatusScreen: View {
    @StateObject var viewModel: RetrievePairingStatusViewModel
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 28) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(AppColors.primarySoft)
                            .frame(width: 150, height: 150)
                        ProgressView()
                            .tint(AppColors.primary)
                            .scaleEffect(1.8)
                    }

                    VStack(spacing: 10) {
                        Text("Adding camera to your space")
                            .font(AppFont.title(24))
                            .foregroundColor(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("Keep the camera powered on. This can take up to two minutes.")
                            .font(AppFont.body(14))
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)

                    Spacer()
                }
            }
        }, result: $viewModel.result)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.stop()
        }
        .onChange(of: viewModel.readyForActivation) { ready in
            guard ready else { return }
            pilot.pop(andPush: .cameraAuthEmail(deviceId: viewModel.pairedDeviceId,
                                                screenFrom: screenFrom))
        }
        .onChange(of: viewModel.pairFailure) { failure in
            guard let failure else { return }
            pilot.pop(andPush: .pairCameraError(reason: failure, screenFrom: screenFrom))
        }
    }
}
