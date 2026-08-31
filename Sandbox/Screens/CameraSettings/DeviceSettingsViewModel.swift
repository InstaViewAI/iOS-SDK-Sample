//
//  DeviceSettingsViewModel.swift
//  Sandbox
//
//  Shared base for every camera settings screen, across both hardware
//  generations.
//
//  Cameras answer to one of two settings APIs, and which one is decided per
//  device by `clusterGroupVersion`:
//
//    v0 (or absent) → legacy: getDeviceSettings / updateDeviceSettings,
//                     reading and writing a fixed DeviceSettingModel.
//    anything else  → clusters: getDeviceClusters / updateDeviceClustersAttribute,
//                     a self-describing document of typed attributes.
//
//  Screens should not care which. Everything below presents one vocabulary —
//  `SettingsFeature` — and each accessor dispatches to whichever API this
//  camera speaks. Adding a screen means asking `supports(_:)` and binding a
//  value, not branching on the generation.
//
//  Detection AI and notifications sit on their own cloud endpoints in both
//  generations, because they are evaluated server-side on the uploaded clip
//  rather than on the camera.
//

import SwiftUI
import Combine
import IVSDK

/// One configurable thing, named independently of how it is stored.
enum SettingsFeature: CaseIterable {
    // General
    case privacyMode
    case statusLight
    case osdTimestamp
    case osdLogo

    // Image
    case rotation
    case hdr
    case alwaysOn

    // Audio
    case microphone
    case speaker
    case speakerVolume

    // Detection
    case motionDetection
    case motionSensitivity
    case motionCooldown
    case eventScheduling
    case eventDuration
    case humanTracking

    /// Where this lives in a cluster document. `nil` means the feature has no
    /// cluster representation at all.
    var cluster: (type: ClustersType, attribute: ClustersAttribute)? {
        switch self {
        case .privacyMode:        return (.privacyMode, .privacyMode)
        case .statusLight:        return (.statusLight, .statusLightEnabled)
        case .osdTimestamp:       return (.osdSettings, .osdSettingsTimeStamp)
        case .osdLogo:            return (.osdSettings, .osdSettingsInstaviewLogo)
        case .rotation:           return (.rotationalAngle, .rotationAngle)
        case .hdr:                return (.hdrEnable, .hdrEnabled)
        case .alwaysOn:           return (.alwaysON, .alwaysOn)
        case .microphone:         return (.audioSettings, .audioSettingsMicrophoneEnabled)
        case .speaker:            return (.audioSettings, .audioSettingsSpeakerEnabled)
        case .speakerVolume:      return (.audioSettings, .audioSettingsVolumeLevel)
        case .motionDetection:    return (.motionDetection, .motionDetectionEnable)
        case .motionSensitivity:  return (.motionSensorSensitivityLevel, .sensitivityLevel)
        case .motionCooldown:     return (.motionDetection, .motionDetectionCoolDownPeriod)
        case .eventScheduling:    return (.eventScheduling, .eventSchedulingEnable)
        case .eventDuration:      return (.eventDuration, .eventDuration)
        case .humanTracking:      return (.humanTracking, .humanTracking)
        }
    }

    /// Legacy cameras have no per-model capability document in this sample, so
    /// support is inferred from the settings object they return. A field the
    /// legacy model does not carry is one the camera cannot be told about.
    var existsOnLegacy: Bool {
        switch self {
        // Present on every DeviceSettingModel.
        case .privacyMode, .statusLight, .osdTimestamp, .osdLogo, .rotation,
             .microphone, .speaker, .speakerVolume, .motionDetection,
             .motionSensitivity, .motionCooldown, .eventScheduling,
             .humanTracking:
            return true
        // Optional on the legacy model — checked for nil at runtime.
        case .hdr, .alwaysOn, .eventDuration:
            return true
        }
    }
}

/// A choice offered by an enum setting. Cluster devices report these with
/// their own labels; legacy devices fall back to the fixed lists below.
struct SettingOption: Identifiable, Equatable {
    var id: String { value }
    let value: String
    let label: String
}

class DeviceSettingsViewModel: ObservableObject {

    @Published var device: DeviceModel
    @Published var clusters: CameraClustersModel?
    @Published var legacySettings: DeviceSettingModel?
    @Published var cloudSettings: DeviceCloudSettings?
    @Published var result = ResultWrapper()

    let sharedData: SharedDataStore
    let deviceService: DeviceServiceContract

    private var deviceCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var cloudCancellable: AnyCancellable?
    private var updateCancellable: AnyCancellable?

    init(device: DeviceModel,
         sharedData: SharedDataStore,
         deviceService: DeviceServiceContract = Factory.deviceService) {
        self.device = device
        self.sharedData = sharedData
        self.deviceService = deviceService
        self.clusters = sharedData.deviceCluster(device.id)
    }

    var spaceId: String { device.spaceId }

    /// Which API this camera speaks.
    var usesClusters: Bool { device.supportsClusters }

    /// A sleeping battery camera has to be woken before a setting can be
    /// written. Both APIs take the same flag.
    var needsWakeup: Bool {
        device.isBatteryPowered || device.state == .sleep
    }

    // MARK: - Loading

    func load() {
        let alreadyHaveSettings = usesClusters ? clusters != nil : legacySettings != nil
        if !alreadyHaveSettings { result.update(data: .loading) }
        loadDevice()
        loadSettings()
        loadCloudSettings()
    }

    private func loadDevice() {
        deviceCancellable = sharedData.getDevice(spaceId: spaceId, deviceId: device.id)
            .sink { [weak self] state in
                if case let .success(device) = state {
                    self?.device = device
                }
            }
    }

    private func loadSettings() {
        usesClusters ? loadClusters() : loadLegacySettings()
    }

    private func loadClusters() {
        settingsCancellable = deviceService.getDeviceClusters(spaceId: spaceId, deviceId: device.id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(model):
                    self.clusters = model
                    self.sharedData.setCluster(model, for: self.device.id)
                    self.result.update(data: .success)
                case let .error(error):
                    self.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    private func loadLegacySettings() {
        settingsCancellable = deviceService.getDeviceSettings(spaceId: spaceId, deviceId: device.id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(settings):
                    self?.legacySettings = settings
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    private func loadCloudSettings() {
        cloudCancellable = deviceService.getDeviceCloudSettings(spaceId: spaceId, deviceId: device.id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case let .success(cloud) = state {
                    self?.cloudSettings = cloud
                }
                // A camera that has never had cloud settings written returns an
                // error rather than an empty object. Not worth an alert.
            }
    }

    // MARK: - Capability

    func supports(_ feature: SettingsFeature) -> Bool {
        if usesClusters {
            guard let mapping = feature.cluster, let clusters else { return false }
            return clusters.getClusterFor(clusterType: mapping.type)?
                .getAttributeFor(attributeType: mapping.attribute) != nil
        }
        guard feature.existsOnLegacy, let legacySettings else { return false }
        // The three optional legacy fields only count when the camera actually
        // reported a value for them.
        switch feature {
        case .hdr:           return legacySettings.hdrEnabled != nil
        case .alwaysOn:      return legacySettings.alwaysOn != nil
        case .eventDuration: return legacySettings.eventDuration != nil
        default:             return true
        }
    }

    func supportsAny(_ features: [SettingsFeature]) -> Bool {
        features.contains { supports($0) }
    }

    // MARK: - Reading

    func bool(_ feature: SettingsFeature) -> Bool? {
        if usesClusters {
            guard let mapping = feature.cluster else { return nil }
            return clusters?.getClusterFor(clusterType: mapping.type)?
                .getAttributeValue(attributeType: mapping.attribute)?.boolValue
        }
        guard let s = legacySettings else { return nil }
        switch feature {
        case .privacyMode:     return s.privacyMode
        case .statusLight:     return s.statusLightEnabled
        case .osdTimestamp:    return s.osdSettings.timeStamp
        case .osdLogo:         return s.osdSettings.instaviewLogo
        case .hdr:             return s.hdrEnabled
        case .alwaysOn:        return s.alwaysOn
        case .microphone:      return s.audioSettings.microphoneEnabled
        case .speaker:         return s.audioSettings.speakerEnabled
        case .motionDetection: return s.eventDetectionSettings.motion
        case .eventScheduling: return s.eventSchedulingEnabled
        case .humanTracking:   return s.humanTracking
        default:               return nil
        }
    }

    func string(_ feature: SettingsFeature) -> String? {
        if usesClusters {
            guard let mapping = feature.cluster else { return nil }
            return clusters?.getClusterFor(clusterType: mapping.type)?
                .getAttributeValue(attributeType: mapping.attribute)?.stringValue
        }
        guard let s = legacySettings else { return nil }
        switch feature {
        case .motionSensitivity: return s.sensitivityLevel
        case .motionCooldown:    return s.eventDetectionSettings.coolDown
        default:                 return nil
        }
    }

    func number(_ feature: SettingsFeature) -> Double? {
        if usesClusters {
            guard let mapping = feature.cluster,
                  let value = clusters?.getClusterFor(clusterType: mapping.type)?
                    .getAttributeValue(attributeType: mapping.attribute) else { return nil }
            return value.doubleValue ?? value.intValue.map(Double.init)
        }
        guard let s = legacySettings else { return nil }
        switch feature {
        case .rotation:      return Double(s.rotationAngle)
        case .speakerVolume: return s.audioSettings.volumeLevel
        case .eventDuration: return s.eventDuration.map(Double.init)
        default:             return nil
        }
    }

    /// Choices for an enum setting. Cluster devices describe their own; legacy
    /// firmware does not, so a fixed list stands in.
    func options(_ feature: SettingsFeature) -> [SettingOption] {
        if usesClusters, let mapping = feature.cluster,
           let labels = clusters?.getClusterFor(clusterType: mapping.type)?
            .getAttributeFor(attributeType: mapping.attribute)?.property?.labels,
           !labels.isEmpty {
            return labels.map { SettingOption(value: $0.enumValue, label: $0.label) }
        }
        return Self.legacyOptions(feature)
    }

    static func legacyOptions(_ feature: SettingsFeature) -> [SettingOption] {
        switch feature {
        case .motionSensitivity:
            return [.init(value: "low", label: "Low"),
                    .init(value: "medium", label: "Medium"),
                    .init(value: "high", label: "High")]
        case .motionCooldown:
            return [.init(value: "30", label: "30 seconds"),
                    .init(value: "60", label: "1 minute"),
                    .init(value: "180", label: "3 minutes"),
                    .init(value: "300", label: "5 minutes")]
        default:
            return []
        }
    }

    func range(_ feature: SettingsFeature) -> ClosedRange<Double>? {
        if usesClusters, let mapping = feature.cluster,
           let property = clusters?.getClusterFor(clusterType: mapping.type)?
            .getAttributeFor(attributeType: mapping.attribute)?.property,
           let min = property.min, let max = property.max, min < max {
            return Double(min)...Double(max)
        }
        switch feature {
        case .speakerVolume: return 0...100
        case .eventDuration: return 10...60
        default: return nil
        }
    }

    // MARK: - Writing

    func setBool(_ feature: SettingsFeature, _ value: Bool) {
        usesClusters
            ? setCluster(feature, value: .bool(value))
            : setLegacy(feature, legacyRequest(feature, bool: value))
    }

    func setString(_ feature: SettingsFeature, _ value: String) {
        usesClusters
            ? setCluster(feature, value: .string(value))
            : setLegacy(feature, legacyRequest(feature, string: value))
    }

    func setNumber(_ feature: SettingsFeature, _ value: Double) {
        if usesClusters {
            // Every numeric attribute here is an integer, volume included.
            setCluster(feature, value: .int(Int(value)))
        } else {
            setLegacy(feature, legacyRequest(feature, number: value))
        }
    }

    // MARK: Cluster writes

    /// Updates the local copy first so the control responds immediately, then
    /// reconciles with what the camera stored, or rolls back on failure.
    private func setCluster(_ feature: SettingsFeature, value: AttributeValue) {
        guard let mapping = feature.cluster,
              var model = clusters,
              let cluster = model.getClusterFor(clusterType: mapping.type),
              let attribute = cluster.getAttributeFor(attributeType: mapping.attribute) else {
            Logger.debugLog("Cluster attribute for \(feature) not present on this camera")
            return
        }

        let previous = clusters
        model.updateAttributeValueForCluster(clusterType: mapping.type,
                                             attributeType: mapping.attribute,
                                             value: value)
        clusters = model
        sharedData.setCluster(model, for: device.id)

        updateCancellable = deviceService
            .updateDeviceClustersAttribute(spaceId: spaceId,
                                           deviceId: device.id,
                                           clusterId: cluster.id,
                                           attributeId: attribute.id,
                                           wakeup: needsWakeup,
                                           request: .init(type: attribute.type,
                                                          value: value,
                                                          attributeId: attribute.id))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case let .success(response):
                    var updated = self.clusters
                    updated?.updateCluster(cluster: response.cluster)
                    self.clusters = updated
                    if let updated { self.sharedData.setCluster(updated, for: self.device.id) }
                case let .error(error):
                    self.clusters = previous
                    if let previous { self.sharedData.setCluster(previous, for: self.device.id) }
                    self.result.update(data: .error(error: error))
                default:
                    break
                }
            }
    }

    /// Writes several cluster attributes together, for settings that only make
    /// sense applied as a set. Cluster devices only.
    func setClusterAttributes(_ clusterType: ClustersType,
                              values: [(ClustersAttribute, AttributeValue)]) {
        guard usesClusters,
              var model = clusters,
              let cluster = model.getClusterFor(clusterType: clusterType) else { return }

        let previous = clusters
        var requests: [UpdateClusterAttributeRequestModel] = []

        for (attributeType, value) in values {
            guard let attribute = cluster.getAttributeFor(attributeType: attributeType) else { continue }
            model.updateAttributeValueForCluster(clusterType: clusterType,
                                                 attributeType: attributeType,
                                                 value: value)
            requests.append(.init(type: attribute.type, value: value, attributeId: attribute.id))
        }
        guard !requests.isEmpty else { return }

        clusters = model
        sharedData.setCluster(model, for: device.id)

        updateCancellable = deviceService
            .updateDeviceCluster(spaceId: spaceId,
                                 deviceId: device.id,
                                 clusterId: cluster.id,
                                 wakeup: needsWakeup,
                                 request: .init(attributes: requests))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case let .success(response):
                    var updated = self.clusters
                    updated?.updateCluster(cluster: response.cluster)
                    self.clusters = updated
                    if let updated { self.sharedData.setCluster(updated, for: self.device.id) }
                case let .error(error):
                    self.clusters = previous
                    if let previous { self.sharedData.setCluster(previous, for: self.device.id) }
                    self.result.update(data: .error(error: error))
                default:
                    break
                }
            }
    }

    // MARK: Legacy writes

    /// The legacy endpoint takes a sparse request: only the fields set are
    /// changed, so each feature contributes exactly one.
    private func legacyRequest(_ feature: SettingsFeature, bool: Bool) -> UpdateDeviceSettingRequestModel {
        switch feature {
        case .privacyMode:     return .init(privacyMode: bool)
        case .statusLight:     return .init(statusLightEnabled: bool)
        case .osdTimestamp:    return .init(osdSettings: .init(timeStamp: bool))
        case .osdLogo:         return .init(osdSettings: .init(instaviewLogo: bool))
        case .hdr:             return .init(hdrEnabled: bool)
        case .alwaysOn:        return .init(alwaysOn: bool)
        case .microphone:      return .init(audioSettings: .init(microphoneEnabled: bool))
        case .speaker:         return .init(audioSettings: .init(speakerEnabled: bool))
        case .motionDetection: return .init(eventDetectionSettings: .init(motion: bool))
        case .eventScheduling: return .init(eventSchedulingEnabled: bool)
        case .humanTracking:   return .init(humanTracking: bool)
        default:               return .init()
        }
    }

    private func legacyRequest(_ feature: SettingsFeature, string: String) -> UpdateDeviceSettingRequestModel {
        switch feature {
        case .motionSensitivity: return .init(sensitivityLevel: string)
        case .motionCooldown:    return .init(eventDetectionSettings: .init(coolDown: string))
        default:                 return .init()
        }
    }

    private func legacyRequest(_ feature: SettingsFeature, number: Double) -> UpdateDeviceSettingRequestModel {
        switch feature {
        case .rotation:      return .init(rotationAngle: Int(number))
        case .speakerVolume: return .init(audioSettings: .init(volumeLevel: number))
        case .eventDuration: return .init(eventDuration: Int(number))
        default:             return .init()
        }
    }

    private func setLegacy(_ feature: SettingsFeature, _ request: UpdateDeviceSettingRequestModel) {
        let previous = legacySettings

        updateCancellable = deviceService
            .updateDeviceSettings(spaceId: spaceId,
                                  deviceId: device.id,
                                  wakeup: needsWakeup,
                                  request: request)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(updated):
                    // The legacy endpoint returns the whole settings object,
                    // so the response is the new truth.
                    self?.legacySettings = updated
                case let .error(error):
                    self?.legacySettings = previous
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    // MARK: - Bindings

    func boolBinding(_ feature: SettingsFeature) -> Binding<Bool> {
        Binding(
            get: { self.bool(feature) ?? false },
            set: { self.setBool(feature, $0) }
        )
    }

    // MARK: - Cloud-side settings

    func updateCloudAI(_ request: EventDetectionSettingsRequest) {
        updateCancellable = deviceService
            .updateDeviceCloudAISettings(spaceId: spaceId,
                                         deviceId: device.id,
                                         wakeup: needsWakeup,
                                         request: request)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case let .success(cloud):
                    self?.cloudSettings = cloud
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                    self?.loadCloudSettings()
                default:
                    break
                }
            }
    }

    func updateCloudNotifications(_ request: NotificationSettingsRequest) {
        updateCancellable = deviceService
            .updateDeviceCloudNotificationsSettings(spaceId: spaceId,
                                                    deviceId: device.id,
                                                    wakeup: needsWakeup,
                                                    request: request)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case let .success(cloud):
                    self?.cloudSettings = cloud
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                    self?.loadCloudSettings()
                default:
                    break
                }
            }
    }
}
