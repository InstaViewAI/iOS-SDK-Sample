//
//  CameraSearchScreen.swift
//  Sandbox
//
//  BLE discovery. A camera in setup mode advertises itself; the app scans for
//  a fixed window and then either lists what it found or offers the QR route
//  as a fallback.
//

import SwiftUI
import Combine
import IVSDK

final class CameraSearchViewModel: ObservableObject {
    /// Give the radio a generous window — a cold-booted camera can take
    /// several seconds to start advertising.
    static let scanTimeout: TimeInterval = 30

    @Published var cameras: [BLECamera] = []
    @Published var searchFailed = false
    @Published var elapsed: TimeInterval = 0

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    func startScan() {
        cameras = []
        searchFailed = false
        elapsed = 0

        BLEManager.instance.initCBCentralManager()
        BLEManager.instance.startScan()

        BLEManager.instance.$cameraList
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in self?.cameras = list }
            .store(in: &cancellables)

        // The SDK raises this when the scan window closes with nothing found.
        BLEManager.instance.$noCameraFound
            .receive(on: DispatchQueue.main)
            .sink { [weak self] noneFound in
                if noneFound, self?.cameras.isEmpty == true {
                    self?.searchFailed = true
                }
            }
            .store(in: &cancellables)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.elapsed += 1
            if self.elapsed >= Self.scanTimeout {
                timer.invalidate()
                self.stopScan()
                if self.cameras.isEmpty { self.searchFailed = true }
            }
        }
    }

    func stopScan() {
        BLEManager.instance.stopScan()
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stopScan()
    }

    var progress: Double { min(elapsed / Self.scanTimeout, 1) }
}

struct CameraSearchScreen: View {
    @StateObject var viewModel: CameraSearchViewModel
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @State private var showQuitConfirm = false

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                PairingNavBar(screenFrom: screenFrom, showQuitConfirm: $showQuitConfirm)

                VStack(spacing: 28) {
                    StepHeader(step: 2, total: 5,
                               title: "Looking for your camera",
                               subtitle: "Keep your phone close to the camera while we search.")
                        .padding(.horizontal, 24)

                    ZStack {
                        Circle()
                            .stroke(AppColors.border, lineWidth: 6)
                            .frame(width: 150, height: 150)
                        Circle()
                            .trim(from: 0, to: viewModel.progress)
                            .stroke(AppColors.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: viewModel.progress)
                        VStack(spacing: 4) {
                            Text("\(viewModel.cameras.count)")
                                .font(AppFont.title(34))
                                .foregroundColor(AppColors.textPrimary)
                            Text(viewModel.cameras.count == 1 ? "camera found" : "cameras found")
                                .font(AppFont.caption(11))
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    Text("This usually takes about 20 seconds.")
                        .font(AppFont.body(14))
                        .foregroundColor(AppColors.textSecondary)

                    Spacer()

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Choose a camera",
                                      enabled: !viewModel.cameras.isEmpty) {
                            viewModel.stopScan()
                            pilot.push(.bleCameraList(screenFrom: screenFrom))
                        }
                        SecondaryButton(title: "Set up with a QR code instead") {
                            viewModel.stopScan()
                            pilot.push(.scanCameraCode(screenFrom: screenFrom))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear { viewModel.startScan() }
        .onDisappear { viewModel.stopScan() }
        .onChange(of: viewModel.searchFailed) { failed in
            if failed {
                pilot.pop(andPush: .cameraSearchFail(screenFrom: screenFrom))
            }
        }
        .overlay {
            if showQuitConfirm {
                AppAlertView(shown: $showQuitConfirm,
                             title: "Stop setting up?",
                             message: "Your camera will not be added.",
                             okTitle: "Stop setup",
                             cancelTitle: "Keep going", onOk: {
                    pilot.quitPairing(screenFrom: screenFrom)
                })
            }
        }
    }
}
