//
//  CameraAuthEmailScreen.swift
//  Sandbox
//
//  Final step. The camera is claimed; naming it is what turns it from a
//  pending record into an activated device on the home screen.
//

import SwiftUI
import Combine
import IVSDK

final class CameraAuthEmailViewModel: PairingSessionViewModel {

    @Published var cameraName = ""
    @Published var device: DeviceModel?
    @Published var finished = false

    private let deviceService: DeviceServiceContract
    private var deviceCancellable: AnyCancellable?
    private var updateCancellable: AnyCancellable?
    private var refreshCancellable: AnyCancellable?

    private let deviceId: String

    init(sharedData: SharedDataStore,
         deviceId: String,
         deviceService: DeviceServiceContract = Factory.deviceService) {
        self.deviceId = deviceId
        self.deviceService = deviceService
        super.init(sharedData: sharedData)
    }

    /// Suggested names, skipping any already taken in this space.
    var nameSuggestions: [String] {
        let taken = Set(sharedData.devices.map { $0.displayName.lowercased() })
        return ["Front door", "Living room", "Back garden", "Driveway", "Garage", "Nursery"]
            .filter { !taken.contains($0.lowercased()) }
    }

    var canSubmit: Bool { cameraName.isNotEmpty }

    func load() {
        result.update(data: .loading)
        deviceCancellable = sharedData.getDevice(spaceId: spaceId, deviceId: deviceId)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(device):
                    self?.device = device
                    // Only pre-fill from a name the user chose; the factory
                    // default is the model number and helps nobody.
                    if device.name != device.modelName, device.name.isNotEmpty {
                        self?.cameraName = device.name
                    }
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    func finish() {
        result.update(data: .loading)
        updateCancellable = deviceService
            .updateDevice(spaceId: spaceId,
                          deviceId: deviceId,
                          request: .init(name: cameraName.trim,
                                         pairingStatus: DeviceAuthStatus.activated.rawValue))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    // Hold the loader across the refresh so the home screen is
                    // already correct by the time it appears.
                    self?.result.update(data: .success, hideLoader: false)
                    self?.refreshDevices()
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    private func refreshDevices() {
        refreshCancellable = sharedData.fetchDevices()
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success, .error:
                    // Even a failed refresh should not block the user — the
                    // camera is activated either way.
                    self?.result.update(data: .success)
                    self?.finished = true
                @unknown default:
                    break
                }
            }
    }
}

struct CameraAuthEmailScreen: View {
    @StateObject var viewModel: CameraAuthEmailViewModel
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "")

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(AppColors.success)
                                Text("Camera connected")
                                    .font(AppFont.title(28))
                                    .foregroundColor(AppColors.textPrimary)
                                Text("Give it a name so you can tell it apart from your other cameras.")
                                    .font(AppFont.body(15))
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            AppTextField(placeholder: "Camera name",
                                         text: $viewModel.cameraName,
                                         autocapitalization: .words)

                            if viewModel.cameraName.isEmpty {
                                FlowLayoutChips(items: viewModel.nameSuggestions) { suggestion in
                                    viewModel.cameraName = suggestion
                                }
                            }

                            if let device = viewModel.device {
                                SectionCard(title: "Camera") {
                                    SettingsRow(title: "Model",
                                                value: device.displayModelName,
                                                showsChevron: false) {}
                                    RowDivider()
                                    SettingsRow(title: "Firmware",
                                                value: device.deviceState.firmwareVersion,
                                                showsChevron: false) {}
                                    RowDivider()
                                    SettingsRow(title: "Network",
                                                value: device.deviceState.wifiName.isNotEmpty
                                                    ? device.deviceState.wifiName : "Cellular",
                                                showsChevron: false) {}
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }

                    PrimaryButton(title: "Finish setup", enabled: viewModel.canSubmit) {
                        viewModel.finish()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
        .onChange(of: viewModel.finished) { finished in
            guard finished else { return }
            // Setup is done — collapse the whole pairing stack rather than
            // leaving a dozen screens behind the back button.
            pilot.popTo(.appTabBar)
        }
    }
}

/// Wrapping row of tappable suggestions.
struct FlowLayoutChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Button { onTap(item) } label: {
                            Text(item)
                                .font(AppFont.caption(13))
                                .foregroundColor(AppColors.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(AppColors.surface)
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppColors.border, lineWidth: 1))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Three per row is enough for the short labels used here.
    private var rows: [[String]] {
        stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0..<min($0 + 3, items.count)])
        }
    }
}
