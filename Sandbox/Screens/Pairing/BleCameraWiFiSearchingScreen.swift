//
//  BleCameraWiFiSearchingScreen.swift
//  Sandbox
//
//  Connects over BLE and asks the camera to scan for networks. The list that
//  comes back is what the camera can actually see, which is more useful than
//  what the phone can see — they are often not the same.
//

import SwiftUI
import Combine
import IVSDK

final class BleCameraWiFiSearchingViewModel: ObservableObject {
    static let scanTimeout: TimeInterval = 45

    @Published var connectionStatus: CameraConnectionStatus = .none
    @Published var networks: [WifiNetwork] = []
    @Published var scanFailed = false

    let camera: BLECamera
    private var cancellables = Set<AnyCancellable>()
    private var timeoutTimer: Timer?
    private(set) var didRequestScan = false

    init(camera: BLECamera) {
        self.camera = camera
    }

    func start() {
        BLEManager.instance.connectToCamera(camera: camera)

        BLEManager.instance.$cameraConnectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.connectionStatus = status
                // Only ask for a scan once the link is up, and only once —
                // the publisher fires again on every subsequent state change.
                if status == .connected, !self.didRequestScan {
                    self.didRequestScan = true
                    BLEManager.instance.sendWiFiScanCommand()
                    BLEManager.instance.getWiFiList()
                }
            }
            .store(in: &cancellables)

        BLEManager.instance.$wifiList
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                guard !list.isEmpty else { return }
                // Strongest first, and drop the duplicate SSIDs a mesh network
                // reports once per access point.
                var seen = Set<String>()
                self?.networks = list
                    .sorted { $0.rssi > $1.rssi }
                    .filter { seen.insert($0.ssid).inserted }
                self?.timeoutTimer?.invalidate()
            }
            .store(in: &cancellables)

        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.scanTimeout, repeats: false) { [weak self] _ in
            if self?.networks.isEmpty == true {
                self?.scanFailed = true
            }
        }
    }

    func stop() {
        timeoutTimer?.invalidate()
        cancellables.removeAll()
    }

    var statusText: String {
        switch connectionStatus {
        case .connected:
            return "Asking the camera to scan for networks…"
        case .notConnected:
            // Only a real failure once the link had been established; before
            // that it is just the initial state.
            return didRequestScan ? "Lost the connection to the camera" : "Connecting to the camera…"
        case .none:
            return "Connecting to the camera…"
        @unknown default:
            return "Working…"
        }
    }
}

struct BleCameraWiFiSearchingScreen: View {
    @StateObject var viewModel: BleCameraWiFiSearchingViewModel
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @State private var showQuitConfirm = false

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                PairingNavBar(screenFrom: screenFrom, showQuitConfirm: $showQuitConfirm)

                VStack(spacing: 28) {
                    StepHeader(step: 3, total: 5,
                               title: "Connecting",
                               subtitle: "Hold still — we are talking to \(viewModel.camera.name).")
                        .padding(.horizontal, 24)

                    ZStack {
                        Circle()
                            .fill(AppColors.primarySoft)
                            .frame(width: 140, height: 140)
                        ProgressView()
                            .tint(AppColors.primary)
                            .scaleEffect(1.6)
                    }

                    Text(viewModel.statusText)
                        .font(AppFont.body(15))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                }
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.networks.count) { count in
            guard count > 0 else { return }
            pilot.pop(andPush: .cameraWiFiList(screenFrom: screenFrom))
        }
        .onChange(of: viewModel.scanFailed) { failed in
            if failed { pilot.pop(andPush: .bleWiFiScanFail(screenFrom: screenFrom)) }
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
