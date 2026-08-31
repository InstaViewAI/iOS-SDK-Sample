//
//  HomeViewModel.swift
//  Sandbox
//

import SwiftUI
import Combine
import IVSDK

final class HomeViewModel: ObservableObject {

    @Published var result = ResultWrapper()
    @Published var devicesLoaded = false
    @Published var showSpacePicker = false

    let sharedData: SharedDataStore

    private let spaceDataStore: SpaceDataStore
    private let eventsDataStore: EventsDataStore

    private var spaceCancellable: AnyCancellable?
    private var deviceCancellable: AnyCancellable?
    private var eventCancellable: AnyCancellable?
    private var pushTokenCancellable: AnyCancellable?
    private var storeCancellables = Set<AnyCancellable>()

    private let userService: UserServiceContract

    /// The last token successfully registered, so a redraw does not re-send it.
    private var registeredToken: String?
    /// iOS only ever presents the critical-alert prompt once; asking again in
    /// the same session achieves nothing.
    private var criticalAlertsAsked = false

    init(sharedData: SharedDataStore,
         spaceDataStore: SpaceDataStore,
         eventsDataStore: EventsDataStore,
         userService: UserServiceContract = Factory.userService) {
        self.sharedData = sharedData
        self.spaceDataStore = spaceDataStore
        self.eventsDataStore = eventsDataStore
        self.userService = userService

        // The screen observes this view model, not the stores. Nesting one
        // ObservableObject inside another does not forward change
        // notifications, so republish them by hand or the device and event
        // lists never redraw when they load.
        sharedData.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        eventsDataStore.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &storeCancellables)

        // Registration needs an authenticated session, so it happens here
        // rather than in the app delegate. `@Published` replays the current
        // value, so a token that arrived before this screen is picked up too.
        sharedData.$apnsToken
            .sink { [weak self] token in self?.registerPushToken(token) }
            .store(in: &storeCancellables)
    }

    // MARK: - Push registration

    /// Hands the APNs token to the backend. Without this the device is never
    /// sent anything, however many permissions it has been granted.
    private func registerPushToken(_ token: String) {
        guard !token.isEmpty, token != registeredToken else { return }

        pushTokenCancellable = userService
            .updatePushNotificationToken(token: token, provider: .apns)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .success:
                    self?.registeredToken = token
                    // Persist it only once the backend has accepted it.
                    self?.userService.saveAPNSToken(token: token)
                    Logger.debugLog("Push token registered with backend")
                case let .error(error):
                    Logger.debugLog("Push token registration failed:", error.localizedDescription)
                default:
                    break
                }
            }
    }

    /// Professional monitoring is the case where a missed notification matters
    /// enough to justify breaking through silent mode, so the prompt is asked
    /// for only when the space actually has a plan.
    private func requestCriticalAlertsIfNeeded() {
        guard !criticalAlertsAsked,
              sharedData.currentSpace?.hasProMonitoringPlan() == true else { return }
        criticalAlertsAsked = true
        AppDelegate.instance?.registerForCriticalRemoteNotifications { granted in
            Logger.debugLog("Critical alerts granted:", granted)
        }
    }

    var devices: [DeviceModel] { sharedData.devices }
    var spaces: [SpaceModel] { sharedData.spaces }
    var spaceName: String { sharedData.currentSpace?.name ?? "Space" }

    /// The three most recent events, shown as a strip under the cameras.
    var recentEvents: [EventModel] { Array(eventsDataStore.events.prefix(3)) }

    var onlineCount: Int { devices.filter(\.isOnline).count }

    /// Cameras that finished pairing but never completed activation. They are
    /// listed apart because tapping one resumes setup rather than opening it.
    var pendingSetupDevices: [DeviceModel] {
        devices.filter { $0.authStatus != .activated }
    }

    func load(refresh: Bool = false) {
        if !refresh { result.update(data: .loading) }

        // Spaces first: the device and event calls are both scoped by space id,
        // so they cannot run until a space is selected.
        spaceCancellable = spaceDataStore.fetchSpaces()
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case .success:
                    self.loadDevices()
                    self.loadRecentEvents()
                    // Only meaningful once a space is known, since the prompt
                    // is gated on that space's plan.
                    self.requestCriticalAlertsIfNeeded()
                case let .error(error):
                    self.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    private func loadDevices() {
        deviceCancellable = sharedData.fetchDevices()
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.devicesLoaded = true
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.devicesLoaded = true
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    private func loadRecentEvents() {
        eventCancellable = eventsDataStore.fetchEvents(refresh: true).sink { _ in }
    }

    func select(space: SpaceModel) {
        sharedData.select(space: space)
        showSpacePicker = false
        devicesLoaded = false
        loadDevices()
        loadRecentEvents()
    }

    /// Where "Add camera" goes. Cameras that talk over cellular skip Wi-Fi
    /// entirely, but the model is unknown until the user picks one, so the
    /// flow always opens at the permission/model gate.
    var addCameraDestination: Destination {
        .cameraPermission(screenFrom: .home)
    }
}
