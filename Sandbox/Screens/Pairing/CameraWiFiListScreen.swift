//
//  CameraWiFiListScreen.swift
//  Sandbox
//
//  The networks the camera itself can see.
//

import SwiftUI
import Combine
import IVSDK

final class CameraWiFiListViewModel: ObservableObject {
    @Published var networks: [WifiNetwork] = []
    private var cancellable: AnyCancellable?

    init() {
        cancellable = BLEManager.instance.$wifiList
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                var seen = Set<String>()
                self?.networks = list
                    .sorted { $0.rssi > $1.rssi }
                    .filter { seen.insert($0.ssid).inserted }
            }
    }
}

struct CameraWiFiListScreen: View {
    @StateObject var viewModel: CameraWiFiListViewModel
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @State private var showQuitConfirm = false

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                PairingNavBar(screenFrom: screenFrom, showQuitConfirm: $showQuitConfirm)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        StepHeader(step: 3, total: 5,
                                   title: "Choose a network",
                                   subtitle: "These are the networks your camera can reach. Cameras join 2.4 GHz networks only.")

                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.networks.enumerated()), id: \.element.ssid) { index, network in
                                Button {
                                    pilot.push(.selectWiFi(mode: .bluetooth,
                                                           ssid: network.ssid,
                                                           screenFrom: screenFrom))
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: wifiIcon(network.rssi))
                                            .foregroundColor(AppColors.primary)
                                            .frame(width: 24)
                                        Text(network.ssid)
                                            .font(AppFont.body(15))
                                            .foregroundColor(AppColors.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        // securityProtocol 0 means an open network.
                                        if network.securityProtocol != 0 {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(AppColors.textDisabled)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppColors.textDisabled)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 56)
                                }
                                if index < viewModel.networks.count - 1 { RowDivider() }
                            }
                        }
                        .background(AppColors.surface)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))

                        LinkButton(title: "Enter a network manually") {
                            pilot.push(.selectWiFi(mode: .bluetooth, ssid: nil, screenFrom: screenFrom))
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

    private func wifiIcon(_ rssi: Int) -> String {
        switch rssi {
        case ..<(-75): return "wifi"
        case ..<(-60): return "wifi.exclamationmark"
        default: return "wifi"
        }
    }
}
