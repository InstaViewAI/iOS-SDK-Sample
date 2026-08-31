//
//  Models+Ext.swift
//  Sandbox
//
//  Presentation-level reads over the SDK models, so screens do not each
//  re-derive the same facts.
//

import SwiftUI
import IVSDK

extension DeviceModel {
    var state: DeviceState { DeviceState(rawValue: deviceState.status) ?? .offline }
    var authStatus: DeviceAuthStatus { DeviceAuthStatus(rawValue: pairingStatus) ?? .initialized }

    /// A camera is usable only once it is fully claimed and reachable.
    /// `sleep` counts as online — battery cameras idle there between events.
    var isOnline: Bool {
        (state == .online || state == .sleep) && authStatus == .activated
    }

    var statusText: String {
        switch state {
        case .online: return "Online"
        case .sleep: return "Standby"
        case .offline: return "Offline"
        case .error: return "Error"
        case .uninitialized: return "Setup needed"
        @unknown default: return "Unknown"
        }
    }

    var statusColor: Color {
        switch state {
        case .online: return AppColors.success
        case .sleep: return AppColors.accent
        case .error: return AppColors.error
        case .offline, .uninitialized: return AppColors.offline
        @unknown default: return AppColors.offline
        }
    }

    var snapshotURL: URL? {
        guard let urlString = deviceState.snapshots.first?.url else { return nil }
        return URL(string: urlString)
    }

    var isBatteryPowered: Bool {
        let source = powerSource ?? "ac"
        return source == "battery" || source == "acBattery"
    }

    /// Which settings generation this camera speaks. `v0` (and an absent
    /// value) predates the cluster API and can only be configured through the
    /// legacy device-settings endpoints.
    var supportsClusters: Bool {
        guard let version = clusterGroupVersion?.trim, !version.isEmpty else { return false }
        return version.lowercased() != AppConfig.legacyClusterGroupVersion
    }

    var is4GCamera: Bool {
        fourG != nil || AppConfig.fourGModelIds.contains(modelId)
    }

    var isDoorbell: Bool {
        deviceType == "doorbell" || AppConfig.doorbellModelIds.contains(modelId)
    }

    var hasSDCard: Bool {
        SDCardStatus(rawValue: deviceState.sdCard.sdStatus) != .notFound
    }

    /// True when the installed firmware is behind what the backend offers.
    var hasFirmwareUpdate: Bool {
        guard let latest = deviceState.latestFirmwareVersion, !latest.isEmpty else { return false }
        return latest.compare(deviceState.firmwareVersion, options: .numeric) == .orderedDescending
    }
}

extension EventModel {
    var startDate: Date { Date(timeIntervalSince1970: TimeInterval(startTime) / 1000) }

    var durationText: String? {
        guard let endTime else { return nil }
        let seconds = max(0, Int((endTime - startTime) / 1000))
        return seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }

    var primaryTag: EventTag? {
        // Specific detections read better than the generic motion tag that
        // accompanies almost every event.
        let ranked: [EventTag] = [.person, .vehicle, .animal, .pet, .bird, .wildlife,
                                  .doorbellRing, .cry, .face, .alarm, .motion]
        return ranked.first { tags.contains($0.rawValue) }
    }

    var snapshotURL: URL? {
        guard let snapshotUrl else { return nil }
        return URL(string: snapshotUrl)
    }

    /// The AI-written description of what happened, when the backend produced
    /// one. It is the most informative thing on an event, so it is surfaced
    /// rather than buried — but plenty of events have none.
    var context: String? {
        guard let contextBody = contextBody?.trimmingCharacters(in: .whitespacesAndNewlines),
              !contextBody.isEmpty else { return nil }
        return contextBody
    }
}

extension EventTag {
    var title: String {
        switch self {
        case .motion: return "Motion"
        case .person: return "Person"
        case .vehicle: return "Vehicle"
        case .animal: return "Animal"
        case .alarm: return "Alarm"
        case .doorbellRing: return "Doorbell"
        case .bird: return "Bird"
        case .pet: return "Pet"
        case .wildlife: return "Wildlife"
        case .cry: return "Crying"
        case .highTemperature: return "High temp"
        case .lowTemperature: return "Low temp"
        case .highHumidity: return "High humidity"
        case .lowHumidity: return "Low humidity"
        case .face: return "Known face"
        @unknown default: return rawValue.capitalized
        }
    }

    var icon: String {
        switch self {
        case .person, .face: return "figure.stand"
        case .vehicle: return "car.fill"
        case .animal, .wildlife: return "pawprint.fill"
        case .pet: return "pawprint"
        case .bird: return "bird.fill"
        case .doorbellRing: return "bell.fill"
        case .cry: return "waveform"
        case .alarm: return "exclamationmark.triangle.fill"
        case .highTemperature, .lowTemperature: return "thermometer"
        case .highHumidity, .lowHumidity: return "humidity"
        default: return "sensor.tag.radiowaves.forward.fill"
        }
    }

    var color: Color {
        switch self {
        case .person, .face: return AppColors.primary
        case .vehicle: return AppColors.accent
        case .animal, .pet, .bird, .wildlife: return AppColors.warning
        case .alarm, .cry: return AppColors.error
        case .doorbellRing: return AppColors.accent
        default: return AppColors.textSecondary
        }
    }
}

extension Date {
    /// "2m ago", "3h ago", "Yesterday 14:02", "12 Mar 09:41".
    var relativeEventLabel: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3600))h ago" }

        let formatter = DateFormatter()
        if Calendar.current.isDateInYesterday(self) {
            formatter.dateFormat = "'Yesterday' HH:mm"
        } else {
            formatter.dateFormat = "d MMM HH:mm"
        }
        return formatter.string(from: self)
    }
}

/// Remote image with a placeholder, used for camera snapshots and event
/// thumbnails. AsyncImage alone leaves an empty frame while loading.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        ZStack {
            AppColors.surfaceRaised
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView().tint(AppColors.textSecondary)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "video.slash")
            .font(.system(size: 24, weight: .light))
            .foregroundColor(AppColors.textDisabled)
    }
}
