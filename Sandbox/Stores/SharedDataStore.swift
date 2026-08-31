//
//  SharedDataStore.swift
//  Sandbox
//
//  The one object every signed-in screen observes: which space is selected,
//  and the devices in it. View models read from here rather than each
//  re-fetching the same lists.
//

import SwiftUI
import Combine
import IVSDK

final class SharedDataStore: ObservableObject {

    enum Tab: Int {
        case home, events, security, settings
    }

    @Published var tabSelection: Tab = .home

    /// The APNs device token, once iOS has issued one. Empty until then.
    @Published private(set) var apnsToken = ""

    @Published private(set) var spaces: [SpaceModel] = []
    @Published private(set) var devices: [DeviceModel] = []

    /// Cluster documents keyed by device id. Settings screens read capability
    /// flags and current values straight out of here, so a camera opened twice
    /// does not refetch its whole cluster set.
    @Published private(set) var clusters: [String: CameraClustersModel] = [:]

    /// Persisted so a relaunch reopens the space the user was last in.
    @AppStorage(AppStorageKey.currentSpace.rawValue) var storedSpace: SpaceModel?

    @Published var currentSpace: SpaceModel? {
        didSet { storedSpace = currentSpace }
    }

    private let deviceService: DeviceServiceContract
    private var devicesCancellable: AnyCancellable?

    init(deviceService: DeviceServiceContract = Factory.deviceService) {
        self.deviceService = deviceService
        self.currentSpace = storedSpace

        NotificationCenter.default.addObserver(forName: .userLogout, object: nil, queue: .main) { [weak self] _ in
            self?.clear()
        }

        // The token can arrive before or after this object exists, so take
        // whatever the delegate already holds and listen for a later one.
        apnsToken = AppDelegate.instance?.apnsToken ?? ""
        NotificationCenter.default.addObserver(forName: .apnsTokenReceived, object: nil, queue: .main) { [weak self] note in
            guard let token = note.userInfo?["token"] as? String else { return }
            self?.apnsToken = token
        }
    }

    var currentSpaceId: String { currentSpace?.id ?? "" }

    /// Spaces this user owns, as opposed to ones shared with them. Owning at
    /// least one is what decides whether the create-space screen is needed.
    var ownedSpaces: [SpaceModel] {
        spaces.filter { SpaceRoleType(rawValue: $0.role ?? "") == .owner }
    }

    func setSpaces(_ list: [SpaceModel]) {
        spaces = list
        // Keep the selection pointing at a space that still exists, and
        // refresh the cached copy so subscription/settings changes land.
        if let current = currentSpace, let updated = list.first(where: { $0.id == current.id }) {
            currentSpace = updated
        } else {
            currentSpace = list.first
        }
    }

    func select(space: SpaceModel) {
        guard space.id != currentSpace?.id else { return }
        currentSpace = space
        devices = []
        fetchDevices()
    }

    func device(id: String) -> DeviceModel? {
        devices.first { $0.id == id }
    }

    func deviceCluster(_ deviceId: String) -> CameraClustersModel? {
        clusters[deviceId]
    }

    func setCluster(_ cluster: CameraClustersModel, for deviceId: String) {
        clusters[deviceId] = cluster
    }

    /// Replaces one device in the cached list, so a settings change shows up on
    /// the home screen without a full refetch.
    func update(device: DeviceModel) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
    }

    func remove(deviceId: String) {
        devices.removeAll { $0.id == deviceId }
        clusters[deviceId] = nil
    }

    @discardableResult
    func fetchDevices() -> IVPublisher<[DeviceModel]> {
        let spaceId = currentSpaceId
        guard !spaceId.isEmpty else {
            return Just(.success(data: [])).eraseToAnyPublisher()
        }
        let publisher = deviceService.devices(spaceId)
            .map { state -> ResourceState<[DeviceModel]> in
                switch state {
                case .loading: return .loading
                case let .success(data): return .success(data: data.items)
                case let .error(error): return .error(error: error)
                @unknown default: return .success(data: [])
                }
            }
            .eraseToAnyPublisher()

        devicesCancellable = publisher.sink { [weak self] state in
            if case let .success(list) = state {
                self?.devices = list
            }
        }
        return publisher
    }

    /// Fetches one device and folds it into the cache. The pairing flow polls
    /// this while waiting for a camera to come online.
    func getDevice(spaceId: String, deviceId: String) -> IVPublisher<DeviceModel> {
        deviceService.device(spaceId: spaceId, deviceId: deviceId)
            .handleEvents(receiveOutput: { [weak self] state in
                if case let .success(device) = state {
                    self?.update(device: device)
                }
            })
            .eraseToAnyPublisher()
    }

    private func clear() {
        spaces = []
        devices = []
        clusters = [:]
        currentSpace = nil
        storedSpace = nil
        tabSelection = .home
    }
}

extension Notification.Name {
    static let userLogout = Notification.Name("userLogout")
    static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
}
