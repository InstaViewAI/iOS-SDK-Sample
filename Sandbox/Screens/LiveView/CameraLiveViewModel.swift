//
//  CameraLiveViewModel.swift
//  Sandbox
//
//  Live video from a camera.
//
//  The SDK owns the hard part: `LiveViewModel` negotiates a WebRTC session with
//  the camera and hands back `IVVideoView`s to render into. This wraps it with
//  the screen's own concerns — connection status, mute, recording, snapshots —
//  and translates the SDK's callback surface into published state.
//
//  Connections are shared, not owned. `LiveViewObjectStore` returns the same
//  object for a given camera, so opening live view twice reuses one stream
//  rather than fighting over the camera's single session slot.
//

import SwiftUI
import Combine
import Photos
import IVSDK

final class CameraLiveViewModel: ObservableObject {

    enum LiveStatus: Equatable {
        case idle
        case connecting
        case connected
        case failed
        case unavailable(reason: String)

        var isConnected: Bool { self == .connected }
    }

    @Published private(set) var status: LiveStatus = .idle
    @Published var audioEnabled = false
    @Published var micEnabled = false
    @Published var isRecording = false
    @Published var toastMessage: String?
    @Published var result = ResultWrapper()

    /// Seconds the recording has been running, for the on-screen timer.
    @Published private(set) var recordingSeconds = 0

    @Published var device: DeviceModel

    let live: LiveViewModel
    private let sharedData: SharedDataStore
    private let deviceService: DeviceServiceContract

    private var recordingTimer: Timer?
    private var ptzCancellable: AnyCancellable?

    init(device: DeviceModel,
         sharedData: SharedDataStore,
         deviceService: DeviceServiceContract = Factory.deviceService) {
        self.device = device
        self.sharedData = sharedData
        self.deviceService = deviceService

        // Battery cameras have to be woken before they will accept a session.
        // `hardwareConfig` tells the SDK the lens layout so multi-lens models
        // come back as several views rather than one stretched one.
        self.live = LiveViewObjectStore.objectFor(
            .liveView,
            spaceId: device.spaceId,
            deviceId: device.id,
            wakeup: device.isMcuSupported,
            supportsCalling: device.supportsVideoCall,
            supportRSSI: false,
            hardwareConfig: sharedData.deviceCluster(device.id)?.hardwareConfig
        )
    }

    deinit {
        recordingTimer?.invalidate()
        // Last line of defence. SwiftUI's onDisappear is not guaranteed to run
        // when a hosting controller is covered or popped, and a leaked session
        // keeps the camera busy for the next viewer.
        live.terminateConnection(privacyEnable: false)
    }

    var videoViews: [IVVideoView] { live.remoteViews }

    /// Why the camera cannot be watched right now, if it cannot.
    private var blockedReason: String? {
        if device.authStatus != .activated { return "This camera has not finished setup." }
        if device.state == .offline { return "This camera is offline." }
        if device.deviceState.privacyMode == true { return "Privacy mode is on. Turn it off to watch live." }
        if device.deviceState.forceUpdate == true { return "A firmware update is required before this camera can stream." }
        return nil
    }

    // MARK: - Connection

    func connect() {
        if let reason = blockedReason {
            status = .unavailable(reason: reason)
            return
        }

        // Reflect an already-live shared connection instead of restarting it.
        status = live.isConnected ? .connected : .connecting

        live.onConnected = { [weak self] in
            self?.status = .connected
        }
        live.onReconnect = { [weak self] in
            self?.status = .connecting
        }
        live.onError = { [weak self] in
            // A backgrounded app drops the stream routinely; that is not a
            // failure worth showing, because it recovers on return.
            guard UIApplication.shared.applicationState == .active else {
                self?.status = .connecting
                return
            }
            self?.status = .failed
        }
        live.onStreamFailed = { [weak self] in
            self?.status = .failed
        }
        live.onStreamEnded = { [weak self] in
            self?.status = .idle
        }
        live.onLiveViewTerminate = { [weak self] in
            // The camera ended the session itself — battery models do this to
            // avoid draining themselves on an unattended stream.
            self?.status = .idle
            self?.toastMessage = "Live view stopped to save battery."
        }
        live.onDeviceRefresh = { [weak self] device in
            self?.device = device
            self?.sharedData.update(device: device)
        }

        live.connect()
        // Audio starts muted: opening a camera should never suddenly make
        // noise in a quiet room.
        live.enableAudio(value: false)
    }

    /// Ends the session outright rather than just detaching the view.
    ///
    /// `disconnect()` stops rendering but leaves the WebRTC session — and the
    /// camera's single session slot — open. `terminateConnection` is what
    /// actually releases it, which is what leaving this screen should do.
    /// Mic and speaker are dropped too, so neither is left engaged on a camera
    /// nobody is watching.
    func disconnect() {
        guard status != .idle else { return }
        if isRecording { stopRecording() }

        micEnabled = false
        audioEnabled = false
        live.enableMic(value: false)
        live.enableAudio(value: false)
        live.terminateConnection(privacyEnable: false)
        status = .idle
    }

    func retry() {
        status = .connecting
        live.connect()
    }

    // MARK: - Audio

    func toggleAudio() {
        audioEnabled.toggle()
        live.enableAudio(value: audioEnabled)
    }

    func toggleMic() {
        micEnabled.toggle()
        live.enableMic(value: micEnabled)
    }

    // MARK: - Capture

    func captureSnapshot() {
        live.captureSnapshot(size: nil) { [weak self] image in
            guard let image else {
                self?.toastMessage = "Could not capture a snapshot."
                return
            }
            self?.save(image: image)
        }
    }

    private func save(image: UIImage) {
        // Ask before writing; a denied library permission otherwise fails
        // silently and the user is left wondering where the image went.
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    self?.toastMessage = "Allow photo access in Settings to save snapshots."
                    return
                }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                self?.toastMessage = "Snapshot saved to your photos."
            }
        }
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        let name = "\(device.displayName.replacingOccurrences(of: " ", with: "-"))-\(Int(Date().timeIntervalSince1970))"
        live.startRecording(size: nil, fileName: name)
        isRecording = true
        recordingSeconds = 0

        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingSeconds += 1
        }
    }

    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false

        live.stopRecording { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case let .success(path):
                    Logger.debugLog("Recording written to", path)
                    self?.saveVideoToLibrary(at: path)
                case let .failure(error):
                    Logger.debugLog("Recording failed:", error.localizedDescription)
                    self?.toastMessage = "Could not save the recording."
                }
            }
        }
    }

    /// The SDK hands back a file *URL string* ("file:///private/var/..."),
    /// not a bare path. Feeding that to `URL(fileURLWithPath:)` yields
    /// "/file:///private/var/..." — a path that does not exist, which Photos
    /// rejects with "Unable to issue sandbox extension". Accept either form.
    private func fileURL(from value: String) -> URL? {
        if value.hasPrefix("file://") {
            return URL(string: value)
        }
        return URL(fileURLWithPath: value)
    }

    private func saveVideoToLibrary(at path: String) {
        guard let url = fileURL(from: path),
              FileManager.default.fileExists(atPath: url.path) else {
            Logger.debugLog("Recording missing at", path)
            toastMessage = "Could not find the recording to save."
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self?.toastMessage = "Allow photo access in Settings to save recordings."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { saved, error in
                if let error { Logger.debugLog("Photo library save failed:", error.localizedDescription) }
                // The clip lives in tmp; once it is copied into the library
                // there is no reason to leave it filling up the container.
                if saved { try? FileManager.default.removeItem(at: url) }
                DispatchQueue.main.async {
                    self?.toastMessage = saved
                        ? "Recording saved to your photos."
                        : "Could not save the recording."
                }
            }
        }
    }

    var recordingText: String {
        String(format: "%02d:%02d", recordingSeconds / 60, recordingSeconds % 60)
    }

    // MARK: - Pan and tilt

    /// Only pan-tilt models report a `ptz` cluster.
    var supportsPTZ: Bool {
        sharedData.deviceCluster(device.id)?.supportsPTZ ?? false
    }

    enum PTZDirection {
        case up, down, left, right

        var request: MovePtzRequest {
            switch self {
            case .up:    return .init(pan: 0, tilt: 1, nonStop: false)
            case .down:  return .init(pan: 0, tilt: -1, nonStop: false)
            case .left:  return .init(pan: -1, tilt: 0, nonStop: false)
            case .right: return .init(pan: 1, tilt: 0, nonStop: false)
            }
        }
    }

    func move(_ direction: PTZDirection) {
        ptzCancellable = deviceService
            .movePtz(spaceId: device.spaceId, deviceId: device.id, request: direction.request)
            .receive(on: DispatchQueue.main)
            .sink { state in
                if case let .error(error) = state {
                    Logger.debugLog("PTZ move failed:", error.localizedDescription)
                }
            }
    }

    func resetPosition() {
        ptzCancellable = deviceService
            .resetPtz(spaceId: device.spaceId, deviceId: device.id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .success:
                    self?.toastMessage = "Camera returned to its home position."
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                default:
                    break
                }
            }
    }
}
