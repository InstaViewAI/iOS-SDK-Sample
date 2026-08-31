//
//  CameraPermissionScreen.swift
//  Sandbox
//
//  Pairing needs three permissions and they are all easier to ask for up
//  front than mid-flow, where a denial strands the user on a dead screen.
//

import SwiftUI
import AVFoundation
import CoreLocation
import CoreBluetooth
import IVSDK

final class CameraPermissionViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var cameraGranted = false
    @Published var locationGranted = false
    @Published var bluetoothGranted = false

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        refresh()
    }

    var allGranted: Bool { cameraGranted && locationGranted && bluetoothGranted }

    func refresh() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let status = locationManager.authorizationStatus
        locationGranted = status == .authorizedWhenInUse || status == .authorizedAlways
        bluetoothGranted = BLEManager.instance.authorizationStatus == .allowed
    }

    func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async { self?.cameraGranted = granted }
        }
    }

    /// Location is what lets iOS reveal the current Wi-Fi name, so the user
    /// does not have to type an SSID they cannot see.
    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// There is no explicit Bluetooth prompt — initialising the central
    /// manager is what triggers it.
    func requestBluetooth() {
        BLEManager.instance.initCBCentralManager()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refresh()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
    }
}

struct CameraPermissionScreen: View {
    let screenFrom: ScreenFrom
    @StateObject private var viewModel = CameraPermissionViewModel()
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                NavBar(title: "") { pilot.pop() }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Before we start")
                                .font(AppFont.title(28))
                                .foregroundColor(AppColors.textPrimary)
                            Text("Setup needs a few permissions. You can change these later in iOS Settings.")
                                .font(AppFont.body(15))
                                .foregroundColor(AppColors.textSecondary)
                        }

                        VStack(spacing: 0) {
                            permissionRow(icon: "camera.fill",
                                          title: "Camera",
                                          detail: "To scan setup and SIM codes",
                                          granted: viewModel.cameraGranted) {
                                viewModel.requestCamera()
                            }
                            RowDivider()
                            permissionRow(icon: "wifi",
                                          title: "Location",
                                          detail: "To read your current Wi-Fi name",
                                          granted: viewModel.locationGranted) {
                                viewModel.requestLocation()
                            }
                            RowDivider()
                            permissionRow(icon: "dot.radiowaves.left.and.right",
                                          title: "Bluetooth",
                                          detail: "To find cameras nearby",
                                          granted: viewModel.bluetoothGranted) {
                                viewModel.requestBluetooth()
                            }
                        }
                        .background(AppColors.surface)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
                    }
                    .padding(.horizontal, 24)
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "Continue") {
                        pilot.push(.turnOnCamera(device: nil, screenFrom: screenFrom))
                    }
                    if !viewModel.allGranted {
                        Text("You can continue without all of them, but some steps may not work.")
                            .font(AppFont.caption(11))
                            .foregroundColor(AppColors.textDisabled)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear { viewModel.refresh() }
    }

    private func permissionRow(icon: String, title: String, detail: String,
                               granted: Bool, request: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(AppColors.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.medium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(detail)
                    .font(AppFont.caption(12))
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.success)
            } else {
                Button("Allow", action: request)
                    .font(AppFont.medium(13))
                    .foregroundColor(AppColors.primary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
    }
}
