//
//  BLECameraListScreen.swift
//  Sandbox
//

import SwiftUI
import Combine
import IVSDK

final class BLECameraListViewModel: ObservableObject {
    @Published var cameras: [BLECamera] = []
    private var cancellable: AnyCancellable?

    init() {
        cameras = BLEManager.instance.cameraList
        // Signal strength keeps updating while the list is on screen, so the
        // ordering stays honest about which camera is closest.
        cancellable = BLEManager.instance.$cameraList
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                self?.cameras = list.sorted { $0.rssi > $1.rssi }
            }
    }
}

struct BLECameraListScreen: View {
    @StateObject var viewModel: BLECameraListViewModel
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @State private var showQuitConfirm = false

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                PairingNavBar(screenFrom: screenFrom, showQuitConfirm: $showQuitConfirm)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        StepHeader(step: 2, total: 5,
                                   title: "Pick your camera",
                                   subtitle: "The one closest to your phone is listed first.")

                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.cameras.enumerated()), id: \.element.identifier) { index, camera in
                                Button {
                                    pilot.push(.bleCameraWiFiSearching(camera: camera, screenFrom: screenFrom))
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "video.fill")
                                            .foregroundColor(AppColors.primary)
                                            .frame(width: 40, height: 40)
                                            .background(AppColors.primarySoft)
                                            .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(camera.name)
                                                .font(AppFont.medium(15))
                                                .foregroundColor(AppColors.textPrimary)
                                            if let did = camera.cameraDid, !did.isEmpty {
                                                Text(did)
                                                    .font(AppFont.caption(11))
                                                    .foregroundColor(AppColors.textSecondary)
                                            }
                                        }
                                        Spacer()
                                        SignalBars(signal: camera.signal)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppColors.textDisabled)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 66)
                                }
                                if index < viewModel.cameras.count - 1 { RowDivider() }
                            }
                        }
                        .background(AppColors.surface)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))

                        LinkButton(title: "My camera is not listed") {
                            pilot.pop(andPush: .cameraSearchFail(screenFrom: screenFrom))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
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
}

struct SignalBars: View {
    let signal: BLECamera.Signal

    private var filledBars: Int {
        switch signal {
        case .poor: return 1
        case .weak: return 2
        case .good: return 3
        case .excellent: return 4
        @unknown default: return 1
        }
    }

    private var color: Color {
        switch signal {
        case .poor: return AppColors.error
        case .weak: return AppColors.warning
        default: return AppColors.success
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= filledBars ? color : AppColors.border)
                    .frame(width: 3, height: CGFloat(bar) * 3.5 + 3)
            }
        }
    }
}
