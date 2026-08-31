//
//  PairingSessionViewModel.swift
//  Sandbox
//
//  The engine every pairing route shares.
//
//  Pairing is a three-way handshake. The app asks the backend for a short-lived
//  session key; the key plus Wi-Fi credentials reach the camera (as a QR code
//  it reads with its own lens, or written over BLE); the camera then calls home
//  with that key, which is what ties it to this account. The app has no direct
//  channel to the camera, so every stage is discovered by polling.
//

import SwiftUI
import Combine
import IVSDK

class PairingSessionViewModel: NSObject, ObservableObject {

    @Published var result = ResultWrapper()
    @Published var sessionKeyModel: PairingSessionKeyModel?
    @Published var pairedDeviceId = ""
    @Published var isSessionExpired = false
    @Published var pairFailure: PairFailureReason?
    /// Set once the camera is claimed and ready for the activation step.
    @Published var readyForActivation = false

    @AppStorage(AppStorageKey.serverRegion.rawValue) var serverRegionRaw: String?

    let sharedData: SharedDataStore
    let spaceService: SpaceServiceContract

    private var sessionKeyCancellable: AnyCancellable?
    private var statusCancellable: AnyCancellable?
    private var deviceCancellable: AnyCancellable?

    private var statusPollItem: DispatchWorkItem?
    private var devicePollItem: DispatchWorkItem?

    /// Guards every scheduled retry. Setting it false stops the flow dead —
    /// used on disappear so a backgrounded screen does not keep polling.
    var pollingActive = false {
        didSet {
            if !pollingActive {
                statusPollItem?.cancel()
                devicePollItem?.cancel()
            }
        }
    }

    init(sharedData: SharedDataStore, spaceService: SpaceServiceContract = Factory.spaceService) {
        self.sharedData = sharedData
        self.spaceService = spaceService
        super.init()
    }

    deinit {
        statusPollItem?.cancel()
        devicePollItem?.cancel()
    }

    var spaceId: String { sharedData.currentSpaceId }

    var serverRegion: ServerRegion {
        ServerRegion(rawValue: serverRegionRaw ?? "") ?? .us
    }

    /// Numeric environment the camera firmware expects: 1 prod, 2 staging, 3 dev.
    var envCode: String {
        switch AppEnvironment.environment {
        case .prod: return "1"
        case .staging: return "2"
        case .dev: return "3"
        }
    }

    /// Numeric region code. Dev and staging only exist in US, so the stored
    /// region is only consulted in production.
    var regionCode: String {
        switch AppEnvironment.environment {
        case .dev, .staging:
            return "1"
        case .prod:
            switch serverRegion {
            case .us: return "1"
            case .apac: return "3"
            @unknown default: return "1"
            }
        }
    }

    /// The camera sets its own clock from this, so events carry local times.
    var timezoneSettings: TimezoneSettings {
        let zone = TimeZone.current
        let offsetMinutes = zone.secondsFromGMT() / 60
        let sign = offsetMinutes < 0 ? "-" : "+"
        let hours = abs(offsetMinutes) / 60
        let minutes = abs(offsetMinutes) % 60
        return TimezoneSettings(id: zone.identifier,
                                tzFormat: String(format: "GMT%@%02d:%02d", sign, hours, minutes))
    }

    // MARK: - Session key

    /// `sessionType` is `.fourG` when the camera has no Wi-Fi and identifies
    /// itself by device id instead of by reading a code.
    func createSessionKey(sessionType: SessionType = .other,
                          showLoader: Bool = true,
                          completion: ((PairingSessionKeyModel) -> Void)? = nil) {
        if showLoader { result.update(data: .loading) }

        sessionKeyCancellable = spaceService
            .createPairingSessionKey(spaceId: spaceId,
                                     request: .init(sessionType: sessionType,
                                                    timezoneSettings: timezoneSettings))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(model):
                    self.sessionKeyModel = model
                    self.result.update(data: .success)
                    completion?(model)
                case let .error(error):
                    self.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    // MARK: - Session status polling

    func startPollingSessionStatus() {
        pollingActive = true
        pollSessionStatus()
    }

    func stopPolling() {
        pollingActive = false
    }

    private func schedule(_ block: @escaping () -> Void, into item: inout DispatchWorkItem?) {
        guard pollingActive else { return }
        item?.cancel()
        let workItem = DispatchWorkItem(block: block)
        item = workItem
        DispatchQueue.global().asyncAfter(deadline: AppConfig.pollingDuration, execute: workItem)
    }

    private func pollSessionStatus() {
        guard let sessionKey = sessionKeyModel?.sessionKey, !sessionKey.isEmpty else { return }

        statusCancellable = spaceService
            .getPairingSessionStatus(spaceId: spaceId, sessionKey: sessionKey)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(status):
                    self.handle(status)
                case .error:
                    // A failed poll is usually the camera not being reachable
                    // yet, not a dead session. Keep trying until it expires.
                    self.schedule({ [weak self] in self?.pollSessionStatus() }, into: &self.statusPollItem)
                @unknown default:
                    break
                }
            }
    }

    private func handle(_ status: PairingSessionStatusModel) {
        // Either sub-step reporting failure ends the session — the camera
        // could not sign in, or could not join the network.
        if status.login?.status == "Failure" {
            fail(with: .wifiRejected)
            return
        }
        if status.pairing?.status == "Failure" {
            fail(with: .wifiRejected)
            return
        }

        switch DeviceAuthStatus(rawValue: status.status) {
        case .processed, .paired, .activated:
            // The device id can lag the status by a poll or two.
            guard !status.deviceId.isEmpty else {
                schedule({ [weak self] in self?.pollSessionStatus() }, into: &statusPollItem)
                return
            }
            pairedDeviceId = status.deviceId
            pollDeviceUntilReady()

        case .initialized, .none:
            if status.expired {
                fail(with: .sessionExpired)
            } else {
                schedule({ [weak self] in self?.pollSessionStatus() }, into: &statusPollItem)
            }
        @unknown default:
            schedule({ [weak self] in self?.pollSessionStatus() }, into: &statusPollItem)
        }
    }

    private func fail(with reason: PairFailureReason) {
        pollingActive = false
        isSessionExpired = true
        pairFailure = reason
        BLEManager.instance.disconnect()
        Logger.debugLog("Pairing failed:", reason.rawValue)
    }

    // MARK: - Device polling

    /// Once the camera exists as a device record, wait for it to report a
    /// status that accepts activation.
    private func pollDeviceUntilReady() {
        deviceCancellable = sharedData.getDevice(spaceId: spaceId, deviceId: pairedDeviceId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(device):
                    if device.authStatus.isReadyForAuth || device.authStatus == .activated {
                        self.pollingActive = false
                        self.readyForActivation = true
                    } else {
                        self.schedule({ [weak self] in self?.pollDeviceUntilReady() }, into: &self.devicePollItem)
                    }
                case .error:
                    self.schedule({ [weak self] in self?.pollDeviceUntilReady() }, into: &self.devicePollItem)
                @unknown default:
                    break
                }
            }
    }
}
