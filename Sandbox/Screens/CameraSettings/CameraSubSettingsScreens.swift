//
//  CameraSubSettingsScreens.swift
//  Sandbox
//
//  The individual settings pages reached from CameraSettingsScreen. Each reads
//  and writes cluster attributes through DeviceSettingsViewModel; the options
//  offered by enum settings come from the camera's own display labels rather
//  than a local list.
//

import SwiftUI
import Combine
import IVSDK

// MARK: - Shared control

/// Radio list for an enum setting. Cluster devices report their own labels;
/// legacy devices fall back to a fixed list. Either way it arrives here as
/// `[SettingOption]`, so this view never learns which generation it is on.
struct SettingOptionPicker: View {
    let title: String
    let options: [SettingOption]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        SectionCard(title: title) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    onSelect(option.value)
                } label: {
                    HStack {
                        Text(option.label)
                            .font(AppFont.body(15))
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Image(systemName: selected == option.value
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(selected == option.value
                                             ? AppColors.primary : AppColors.textDisabled)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                }
                if index < options.count - 1 { RowDivider() }
            }
        }
    }
}

// MARK: - Camera info

final class CameraInfoViewModel: DeviceSettingsViewModel {}

struct CameraInfoScreen: View {
    @StateObject var viewModel: CameraInfoViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Camera info") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 18) {
                            SectionCard(title: "Hardware") {
                                infoRow("Model", viewModel.device.displayModelName)
                                RowDivider()
                                infoRow("Device ID", viewModel.device.id)
                                RowDivider()
                                infoRow("Firmware", viewModel.device.deviceState.firmwareVersion)
                                if let variant = viewModel.device.variantName, variant.isNotEmpty {
                                    RowDivider()
                                    infoRow("Variant", variant)
                                }
                                RowDivider()
                                infoRow("Power", viewModel.device.isBatteryPowered ? "Battery" : "Mains")
                            }

                            SectionCard(title: "Network") {
                                infoRow("Connection",
                                        viewModel.device.is4GCamera ? "Cellular" : "Wi-Fi")
                                if viewModel.device.deviceState.wifiName.isNotEmpty {
                                    RowDivider()
                                    infoRow("Network", viewModel.device.deviceState.wifiName)
                                }
                                RowDivider()
                                infoRow("IP address", viewModel.device.deviceState.ipAddr)
                                if let rssi = viewModel.device.deviceState.rssi, rssi.isNotEmpty {
                                    RowDivider()
                                    infoRow("Signal", "\(rssi) dBm")
                                }
                            }

                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(AppFont.body(15))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(AppFont.medium(14))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
}

// MARK: - Events and detection

final class EventSettingsViewModel: DeviceSettingsViewModel {

    var supportsMotion: Bool { supports(.motionDetection) }

    var motionEnabled: Binding<Bool> { boolBinding(.motionDetection) }

    // Detection AI stays on the cloud endpoint — it runs on the uploaded clip,
    // not on the camera, so it is not part of the cluster document.
    private var detections: CloudAiDetections { cloudSettings?.cloudAiDetections ?? .init() }

    func aiBinding(_ keyPath: WritableKeyPath<CloudAiDetections, Bool?>) -> Binding<Bool> {
        Binding(
            get: { self.detections[keyPath: keyPath] ?? false },
            set: { newValue in
                var updated = self.detections
                updated[keyPath: keyPath] = newValue
                self.updateCloudAI(.init(cloudAi: updated))
            }
        )
    }
}

struct EventSettingsScreen: View {
    @StateObject var viewModel: EventSettingsViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Events and detection") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 18) {
                            if viewModel.supportsMotion {
                                SectionCard(title: "Motion") {
                                    SettingsToggleRow(title: "Motion detection",
                                                      subtitle: "Record a clip whenever the camera sees movement",
                                                      icon: "figure.walk.motion",
                                                      isOn: viewModel.motionEnabled)
                                }
                            }

                            SectionCard(title: "Smart detection") {
                                SettingsToggleRow(title: "People",
                                                  icon: "figure.stand",
                                                  isOn: viewModel.aiBinding(\.person))
                                RowDivider()
                                SettingsToggleRow(title: "Vehicles",
                                                  icon: "car.fill",
                                                  isOn: viewModel.aiBinding(\.vehicle))
                                RowDivider()
                                SettingsToggleRow(title: "Animals",
                                                  icon: "pawprint.fill",
                                                  isOn: viewModel.aiBinding(\.animal))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
    }
}

// MARK: - Notifications

final class NotificationSettingsViewModel: DeviceSettingsViewModel {
    private var current: NotificationSettings {
        cloudSettings?.notifications ?? .init(mute: false, doorbellMute: false)
    }

    /// The API stores mutes, but a switch reads better as "on means notify",
    /// so every binding here inverts.
    func muteBinding(_ get: @escaping (NotificationSettings) -> Bool?,
                     _ makeRequest: @escaping (Bool) -> NotificationSettingsRequest) -> Binding<Bool> {
        Binding(
            get: { !(get(self.current) ?? false) },
            set: { self.updateCloudNotifications(makeRequest(!$0)) }
        )
    }
}

struct NotificationSettingsScreen: View {
    @StateObject var viewModel: NotificationSettingsViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Notifications") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 18) {
                            SectionCard(title: "Push notifications") {
                                SettingsToggleRow(title: "All notifications",
                                                  subtitle: "Turn everything off for this camera",
                                                  icon: "bell",
                                                  isOn: viewModel.muteBinding({ $0.mute },
                                                                              { .init(mute: $0) }))
                                RowDivider()
                                SettingsToggleRow(title: "Camera offline",
                                                  subtitle: "Tell me when this camera loses connection",
                                                  icon: "wifi.exclamationmark",
                                                  isOn: viewModel.muteBinding({ $0.cameraOfflineMute },
                                                                              { .init(cameraOfflineMute: $0) }))
                                if viewModel.device.isDoorbell {
                                    RowDivider()
                                    SettingsToggleRow(title: "Doorbell presses",
                                                      icon: "bell.badge",
                                                      isOn: viewModel.muteBinding({ $0.doorbellMute },
                                                                                  { .init(doorbellMute: $0) }))
                                }
                                if viewModel.usesClusters, viewModel.clusters?.supportsTemperature == true {
                                    RowDivider()
                                    SettingsToggleRow(title: "Temperature alerts",
                                                      icon: "thermometer",
                                                      isOn: viewModel.muteBinding({ $0.temperatureMute },
                                                                                  { .init(temperatureMute: $0) }))
                                }
                                if viewModel.usesClusters, viewModel.clusters?.supportsHumidity == true {
                                    RowDivider()
                                    SettingsToggleRow(title: "Humidity alerts",
                                                      icon: "humidity",
                                                      isOn: viewModel.muteBinding({ $0.humidityMute },
                                                                                  { .init(humidityMute: $0) }))
                                }
                            }

                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(AppColors.accent)
                                Text("These settings apply to this camera only. System-wide notification permission is controlled in iOS Settings.")
                                    .font(AppFont.caption(12))
                                    .foregroundColor(AppColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .background(AppColors.surface)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
    }
}

// MARK: - Audio

final class AudioSettingsViewModel: DeviceSettingsViewModel {

    /// Local while the slider is dragged; the camera is written once on release.
    @Published var draftVolume: Double?

    var supportsMicrophone: Bool { supports(.microphone) }
    var supportsSpeaker: Bool { supports(.speaker) }
    var supportsVolume: Bool { supports(.speakerVolume) }

    var microphoneEnabled: Binding<Bool> { boolBinding(.microphone) }
    var speakerEnabled: Binding<Bool> { boolBinding(.speaker) }

    var volumeRange: ClosedRange<Double> { range(.speakerVolume) ?? 0...100 }

    var volume: Double {
        get { draftVolume ?? number(.speakerVolume) ?? volumeRange.lowerBound }
        set { draftVolume = newValue }
    }

    func commitVolume() {
        guard let value = draftVolume else { return }
        // The attribute is an integer; rounding here keeps the value that is
        // sent identical to the one shown.
        setNumber(.speakerVolume, value.rounded())
        draftVolume = nil
    }
}

struct AudioSettingsScreen: View {
    @StateObject var viewModel: AudioSettingsViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Audio") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 18) {
                            if viewModel.supportsMicrophone {
                                SectionCard(title: "Recording") {
                                    SettingsToggleRow(title: "Microphone",
                                                      subtitle: "Record sound alongside video",
                                                      icon: "mic",
                                                      isOn: viewModel.microphoneEnabled)
                                }
                            }

                            if viewModel.supportsSpeaker {
                                SectionCard(title: "Speaker") {
                                    SettingsToggleRow(title: "Speaker",
                                                      subtitle: "Needed for two-way talk and the siren",
                                                      icon: "speaker.wave.2",
                                                      isOn: viewModel.speakerEnabled)
                                    if viewModel.supportsVolume {
                                        RowDivider()
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("Volume")
                                                    .font(AppFont.body(15))
                                                    .foregroundColor(AppColors.textPrimary)
                                                Spacer()
                                                Text("\(Int(viewModel.volume))")
                                                    .font(AppFont.caption(12))
                                                    .foregroundColor(AppColors.textSecondary)
                                            }
                                            Slider(value: Binding(get: { viewModel.volume },
                                                                  set: { viewModel.volume = $0 }),
                                                   in: viewModel.volumeRange,
                                                   step: 1,
                                                   onEditingChanged: { editing in
                                                if !editing { viewModel.commitVolume() }
                                            })
                                            .tint(AppColors.primary)
                                            .disabled(!viewModel.speakerEnabled.wrappedValue)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
    }
}

// MARK: - Live view

final class LiveViewSettingsViewModel: DeviceSettingsViewModel {

    var supportsRotation: Bool { supports(.rotation) }
    var supportsHDR: Bool { supports(.hdr) }
    var supportsLogo: Bool { supports(.osdLogo) }
    var supportsTimestamp: Bool { supports(.osdTimestamp) }
    var supportsAlwaysOn: Bool { supports(.alwaysOn) }

    var rotationAngle: Int { Int(number(.rotation) ?? 0) }

    func setRotation(_ angle: Int) { setNumber(.rotation, Double(angle)) }

    var hdrEnabled: Binding<Bool> { boolBinding(.hdr) }
    var showLogo: Binding<Bool> { boolBinding(.osdLogo) }
    var showTimestamp: Binding<Bool> { boolBinding(.osdTimestamp) }
    var alwaysOn: Binding<Bool> { boolBinding(.alwaysOn) }
}

struct LiveViewSettingsScreen: View {
    @StateObject var viewModel: LiveViewSettingsViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Live view") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 18) {
                            if viewModel.supportsRotation || viewModel.supportsHDR {
                                SectionCard(title: "Image") {
                                    if viewModel.supportsRotation {
                                        HStack {
                                            Text("Rotation")
                                                .font(AppFont.body(15))
                                                .foregroundColor(AppColors.textPrimary)
                                            Spacer()
                                            // Only the two orientations a
                                            // wall- or ceiling-mounted camera
                                            // actually needs.
                                            Picker("", selection: Binding(get: { viewModel.rotationAngle },
                                                                          set: { viewModel.setRotation($0) })) {
                                                Text("0°").tag(0)
                                                Text("180°").tag(180)
                                            }
                                            .pickerStyle(.segmented)
                                            .frame(width: 140)
                                        }
                                        .padding(.horizontal, 16)
                                        .frame(height: 56)
                                    }
                                    if viewModel.supportsHDR {
                                        RowDivider()
                                        SettingsToggleRow(title: "HDR",
                                                          subtitle: "Better detail against bright backgrounds",
                                                          icon: "sun.max",
                                                          isOn: viewModel.hdrEnabled)
                                    }
                                }
                            }

                            if viewModel.supportsLogo || viewModel.supportsTimestamp {
                                SectionCard(title: "Overlay") {
                                    if viewModel.supportsTimestamp {
                                        SettingsToggleRow(title: "Show timestamp",
                                                          subtitle: "Burned into the video",
                                                          icon: "clock",
                                                          isOn: viewModel.showTimestamp)
                                    }
                                    if viewModel.supportsLogo {
                                        if viewModel.supportsTimestamp { RowDivider() }
                                        SettingsToggleRow(title: "Watermark",
                                                          subtitle: "Show the logo in the corner of the video",
                                                          icon: "seal",
                                                          isOn: viewModel.showLogo)
                                    }
                                }
                            }

                            if viewModel.supportsAlwaysOn {
                                SectionCard(title: "Power") {
                                    SettingsToggleRow(title: "Always on",
                                                      subtitle: "Skip standby so live view starts instantly. Uses more battery.",
                                                      icon: "bolt.circle",
                                                      isOn: viewModel.alwaysOn)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
    }
}

// MARK: - Firmware

final class UpdateFirmwareViewModel: DeviceSettingsViewModel {

    @Published var latestVersion: FirmwareVersionModel?
    @Published var updateStatus: String?
    @Published var updating = false

    private var latestCancellable: AnyCancellable?
    private var upgradeCancellable: AnyCancellable?
    private var statusCancellable: AnyCancellable?
    private var statusPollItem: DispatchWorkItem?

    deinit { statusPollItem?.cancel() }

    var updateAvailable: Bool {
        guard let latest = latestVersion?.fwVersion else { return false }
        return latest.compare(device.deviceState.firmwareVersion, options: .numeric) == .orderedDescending
    }

    func checkForUpdate() {
        latestCancellable = deviceService
            .getLatestFirmwareVersion(spaceId: spaceId, deviceId: device.id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case let .success(version) = state {
                    self?.latestVersion = version
                }
            }
    }

    func startUpdate() {
        guard let version = latestVersion?.fwVersion else { return }
        updating = true
        result.update(data: .loading)

        upgradeCancellable = deviceService
            .upgradeFirmware(spaceId: spaceId,
                             deviceId: device.id,
                             wakeup: needsWakeup,
                             request: .init(fwVersion: version))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    // The call only starts the flash; progress arrives through
                    // a separate status endpoint that has to be polled.
                    self?.result.update(data: .success)
                    self?.pollUpdateStatus()
                case let .error(error):
                    self?.updating = false
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    private func pollUpdateStatus() {
        statusCancellable = deviceService
            .getFirmwareUpdatingStatus(spaceId: spaceId, deviceId: device.id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case let .success(status):
                    self.updateStatus = status.message ?? status.status
                    if status.status.lowercased() == "completed" {
                        self.updating = false
                        self.load()
                    } else {
                        self.scheduleStatusPoll()
                    }
                case .error:
                    // The camera reboots mid-update and stops answering; that
                    // is expected, so keep polling rather than reporting it.
                    self.scheduleStatusPoll()
                default:
                    break
                }
            }
    }

    private func scheduleStatusPoll() {
        statusPollItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.pollUpdateStatus() }
        statusPollItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: item)
    }
}

struct UpdateFirmwareScreen: View {
    @StateObject var viewModel: UpdateFirmwareViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Firmware") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 18) {
                            SectionCard(title: "Installed") {
                                HStack {
                                    Text("Current version")
                                        .font(AppFont.body(15))
                                        .foregroundColor(AppColors.textSecondary)
                                    Spacer()
                                    Text(viewModel.device.deviceState.firmwareVersion)
                                        .font(AppFont.medium(14))
                                        .foregroundColor(AppColors.textPrimary)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 50)

                                if let latest = viewModel.latestVersion?.fwVersion {
                                    RowDivider()
                                    HStack {
                                        Text("Latest version")
                                            .font(AppFont.body(15))
                                            .foregroundColor(AppColors.textSecondary)
                                        Spacer()
                                        Text(latest)
                                            .font(AppFont.medium(14))
                                            .foregroundColor(viewModel.updateAvailable
                                                             ? AppColors.warning : AppColors.textPrimary)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 50)
                                }
                            }

                            if viewModel.updating {
                                VStack(spacing: 12) {
                                    ProgressView().tint(AppColors.primary)
                                    Text(viewModel.updateStatus ?? "Updating…")
                                        .font(AppFont.body(14))
                                        .foregroundColor(AppColors.textSecondary)
                                    Text("Leave the camera powered on. It will restart on its own.")
                                        .font(AppFont.caption(11))
                                        .foregroundColor(AppColors.textDisabled)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(20)
                                .frame(maxWidth: .infinity)
                                .background(AppColors.surface)
                                .cornerRadius(16)
                            } else if viewModel.updateAvailable {
                                PrimaryButton(title: "Install update") {
                                    viewModel.startUpdate()
                                }
                            } else {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppColors.success)
                                    Text("This camera is up to date.")
                                        .font(AppFont.body(14))
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity)
                                .background(AppColors.surface)
                                .cornerRadius(14)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear {
            viewModel.load()
            viewModel.checkForUpdate()
        }
    }
}
