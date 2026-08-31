//
//  CameraSettingsScreen.swift
//  Sandbox
//
//  Index of everything configurable on one camera. Every row is gated on a
//  cluster capability flag, so a model that does not report a cluster simply
//  does not show the row.
//

import SwiftUI
import Combine
import IVSDK

final class CameraSettingsViewModel: DeviceSettingsViewModel {

    @Published var editingName = false
    @Published var draftName = ""
    @Published var showDeleteConfirm = false
    @Published var deleted = false

    private var renameCancellable: AnyCancellable?
    private var deleteCancellable: AnyCancellable?

    func beginRename() {
        draftName = device.displayName
        editingName = true
    }

    func commitRename() {
        let name = draftName.trim
        guard name.isNotEmpty, name != device.name else {
            editingName = false
            return
        }
        result.update(data: .loading)

        renameCancellable = deviceService
            .updateDevice(spaceId: spaceId, deviceId: device.id, request: .init(name: name))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(device):
                    self?.device = device
                    self?.sharedData.update(device: device)
                    self?.editingName = false
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    func deleteCamera() {
        result.update(data: .loading)
        deleteCancellable = deviceService
            .deleteDevice(spaceId: spaceId, deviceId: device.id, wakeup: needsWakeup)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.sharedData.remove(deviceId: self?.device.id ?? "")
                    self?.result.update(data: .success)
                    self?.deleted = true
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    // Capability gates. `supports(_:)` answers for whichever settings API this
    // camera speaks, so nothing here branches on the generation.
    var supportsPrivacyMode: Bool { supports(.privacyMode) }
    var supportsStatusLight: Bool { supports(.statusLight) }
    var supportsAudio: Bool { supportsAny([.microphone, .speaker, .speakerVolume]) }
    var supportsLiveViewOptions: Bool {
        supportsAny([.rotation, .hdr, .osdLogo, .osdTimestamp, .alwaysOn])
    }
    var supportsDetection: Bool {
        supportsAny([.motionDetection, .motionSensitivity, .eventScheduling, .humanTracking])
    }

    var privacyMode: Binding<Bool> { boolBinding(.privacyMode) }
    var statusLight: Binding<Bool> { boolBinding(.statusLight) }
}

struct CameraSettingsScreen: View {
    @StateObject var viewModel: CameraSettingsViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Camera settings") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 18) {
                            headerCard

                            SectionCard(title: "Camera") {
                                SettingsRow(title: "Name",
                                            value: viewModel.device.displayName,
                                            icon: "textformat") {
                                    viewModel.beginRename()
                                }
                                RowDivider()
                                SettingsRow(title: "Camera info",
                                            value: viewModel.device.displayModelName,
                                            icon: "info.circle") {
                                    pilot.push(.cameraInfo(device: viewModel.device))
                                }
                                RowDivider()
                                SettingsRow(title: "Firmware",
                                            value: viewModel.device.hasFirmwareUpdate
                                                ? "Update available"
                                                : viewModel.device.deviceState.firmwareVersion,
                                            icon: "arrow.down.circle") {
                                    pilot.push(.updateFirmware(device: viewModel.device))
                                }
                            }

                            SectionCard(title: "Detection") {
                                if viewModel.supportsDetection {
                                    SettingsRow(title: "Events and detection",
                                                icon: "sensor.tag.radiowaves.forward") {
                                        pilot.push(.eventSettings(device: viewModel.device))
                                    }
                                    RowDivider()
                                }
                                SettingsRow(title: "Notifications", icon: "bell") {
                                    pilot.push(.notificationSettings(device: viewModel.device))
                                }
                            }

                            if viewModel.supportsLiveViewOptions || viewModel.supportsAudio {
                                SectionCard(title: "Video and audio") {
                                    if viewModel.supportsLiveViewOptions {
                                        SettingsRow(title: "Live view", icon: "video") {
                                            pilot.push(.liveViewSettings(device: viewModel.device))
                                        }
                                    }
                                    if viewModel.supportsAudio {
                                        RowDivider()
                                        SettingsRow(title: "Audio", icon: "speaker.wave.2") {
                                            pilot.push(.audioSettings(device: viewModel.device))
                                        }
                                    }
                                }
                            }

                            if viewModel.supportsPrivacyMode || viewModel.supportsStatusLight {
                                SectionCard(title: "General") {
                                    if viewModel.supportsPrivacyMode {
                                        SettingsToggleRow(title: "Privacy mode",
                                                          subtitle: "Stops recording and disables the lens",
                                                          icon: "eye.slash",
                                                          isOn: viewModel.privacyMode)
                                    }
                                    if viewModel.supportsStatusLight {
                                        RowDivider()
                                        SettingsToggleRow(title: "Status light",
                                                          subtitle: "The small LED on the camera body",
                                                          icon: "light.beacon.max",
                                                          isOn: viewModel.statusLight)
                                    }
                                }
                            }

                            Button {
                                viewModel.showDeleteConfirm = true
                            } label: {
                                Text("Remove this camera")
                                    .font(AppFont.medium(15))
                                    .foregroundColor(AppColors.error)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(AppColors.error.opacity(0.1))
                                    .cornerRadius(14)
                            }
                            .padding(.top, 6)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
        .overlay {
            if viewModel.editingName { renameDialog }
            if viewModel.showDeleteConfirm {
                AppAlertView(shown: $viewModel.showDeleteConfirm,
                             title: "Remove \(viewModel.device.displayName)?",
                             message: "The camera will be unpaired and its recordings deleted. This cannot be undone.",
                             okTitle: "Remove",
                             cancelTitle: "Cancel", onOk: {
                    viewModel.deleteCamera()
                })
            }
        }
        .onChange(of: viewModel.deleted) { deleted in
            if deleted { pilot.popTo(.appTabBar) }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 0) {
            RemoteImage(url: viewModel.device.snapshotURL)
                .frame(height: 170)
                .clipped()
                .opacity(viewModel.device.isOnline ? 1 : 0.4)

            HStack(spacing: 10) {
                Circle()
                    .fill(viewModel.device.statusColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.device.statusText)
                    .font(AppFont.medium(14))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if viewModel.device.isBatteryPowered,
                   let battery = viewModel.device.deviceState.batteryPercentage {
                    Label("\(Int(battery))%", systemImage: "battery.100")
                        .font(AppFont.caption(12))
                        .foregroundColor(AppColors.textSecondary)
                }
                if viewModel.device.deviceState.wifiName.isNotEmpty {
                    Label(viewModel.device.deviceState.wifiName, systemImage: "wifi")
                        .font(AppFont.caption(12))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
        }
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
    }

    private var renameDialog: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Rename camera")
                    .font(AppFont.heading(18))
                    .foregroundColor(AppColors.textPrimary)
                AppTextField(placeholder: "Camera name",
                             text: $viewModel.draftName,
                             autocapitalization: .words)
                HStack(spacing: 12) {
                    SecondaryButton(title: "Cancel") { viewModel.editingName = false }
                    PrimaryButton(title: "Save") { viewModel.commitRename() }
                }
            }
            .padding(24)
            .background(AppColors.surfaceRaised)
            .cornerRadius(20)
            .padding(.horizontal, 32)
        }
    }
}
