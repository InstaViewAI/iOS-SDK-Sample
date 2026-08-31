//
//  SelectWiFiScreen.swift
//  Sandbox
//
//  Where credentials are collected and the session key is minted. Both
//  transports converge here: BLE writes the result to the camera directly,
//  QR mode renders it as a code for the camera to read.
//

import SwiftUI
import Combine
import CoreLocation
import SystemConfiguration.CaptiveNetwork
import IVSDK

final class SelectWiFiViewModel: PairingSessionViewModel, CLLocationManagerDelegate {

    @Published var ssid = ""
    @Published var password = ""
    @Published var rememberPassword = true
    @Published var show5GHzWarning = false
    @Published var payload: PairingPayload?
    @Published var sentOverBLE = false

    let mode: CameraPairingMode
    private let presetSSID: String?
    /// True once the user edits the field, so the auto-filled SSID never
    /// overwrites what they typed.
    private var userEditedSSID = false

    private let locationManager = CLLocationManager()

    @AppStorage(AppStorageKey.rememberedWiFiPassword.rawValue) private var savedPassword: String?

    init(sharedData: SharedDataStore, mode: CameraPairingMode, presetSSID: String?) {
        self.mode = mode
        self.presetSSID = presetSSID
        super.init(sharedData: sharedData)
        locationManager.delegate = self
    }

    func prepare() {
        guard !userEditedSSID else { return }

        if let presetSSID {
            // Came from the camera's own scan — that name is authoritative.
            ssid = presetSSID
        } else if isLocationAuthorized {
            ssid = currentSSID ?? ""
        } else {
            // iOS only reveals the joined network's name to apps with
            // location access.
            locationManager.requestWhenInUseAuthorization()
        }

        if let savedPassword, !savedPassword.isEmpty {
            password = savedPassword
        }
    }

    func ssidChanged() {
        userEditedSSID = true
        // A 5 GHz-only network is the single most common setup failure, and
        // the name is usually the only hint available.
        show5GHzWarning = ssid.lowercased().contains("5g")
            || ssid.lowercased().contains("5ghz")
            || ssid.contains("-5G")
    }

    var canSubmit: Bool { ssid.isNotEmpty }

    private var isLocationAuthorized: Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private var currentSSID: String? {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return nil }
        for interface in interfaces {
            guard let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] else { continue }
            if let name = info[kCNNetworkInfoKeySSID as String] as? String { return name }
        }
        return nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLocationAuthorized, !userEditedSSID, presetSSID == nil else { return }
        ssid = currentSSID ?? ""
    }

    /// Mints the session key, then hands the credentials to the camera by
    /// whichever route this flow came in on.
    func submit() {
        savedPassword = rememberPassword ? password : nil

        createSessionKey { [weak self] model in
            guard let self else { return }
            let payload = PairingPayload(ssid: self.ssid.trim,
                                         password: self.password,
                                         sessionKey: model.sessionKey,
                                         region: self.regionCode,
                                         env: self.envCode)
            switch self.mode {
            case .qrCode, .fourG:
                self.payload = payload
            case .bluetooth:
                self.sendOverBLE(payload)
            }
        }
    }

    private func sendOverBLE(_ payload: PairingPayload) {
        BLEManager.instance.updateWifiInfo(wifiInfo: .init(ssid: payload.ssid,
                                                           password: payload.password,
                                                           sessionKey: payload.sessionKey,
                                                           env: payload.env,
                                                           region: payload.region))
        // The write is fire-and-forget; from here the camera's progress is
        // only visible through the session status endpoint.
        startPollingSessionStatus()
        sentOverBLE = true
    }
}

struct SelectWiFiScreen: View {
    @StateObject var viewModel: SelectWiFiViewModel
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @State private var showQuitConfirm = false

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    PairingNavBar(screenFrom: screenFrom, showQuitConfirm: $showQuitConfirm)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            StepHeader(step: 3, total: 5,
                                       title: "Wi-Fi details",
                                       subtitle: "Your camera will use this network. It stays on your device and is sent straight to the camera.")

                            VStack(spacing: 14) {
                                AppTextField(placeholder: "Network name",
                                             text: $viewModel.ssid)
                                    .onChange(of: viewModel.ssid) { _ in viewModel.ssidChanged() }
                                AppTextField(placeholder: "Password",
                                             text: $viewModel.password,
                                             isSecure: true)
                            }

                            if viewModel.show5GHzWarning {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(AppColors.warning)
                                    Text("That looks like a 5 GHz network. Cameras can only join 2.4 GHz — pick the 2.4 GHz name if your router has both.")
                                        .font(AppFont.caption(12))
                                        .foregroundColor(AppColors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(14)
                                .background(AppColors.warning.opacity(0.1))
                                .cornerRadius(12)
                            }

                            AppCheckbox(checked: $viewModel.rememberPassword,
                                        title: "Remember this password for the next camera")
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }

                    PrimaryButton(title: "Continue", enabled: viewModel.canSubmit) {
                        viewModel.submit()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.prepare() }
        .onChange(of: viewModel.payload) { payload in
            guard let payload else { return }
            pilot.push(.scanWiFiQRCode(payload: payload, screenFrom: screenFrom))
        }
        .onChange(of: viewModel.sentOverBLE) { sent in
            guard sent, let sessionKey = viewModel.sessionKeyModel?.sessionKey else { return }
            pilot.push(.retrievePairingStatus(sessionKey: sessionKey,
                                              deviceId: "",
                                              screenFrom: screenFrom))
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
