//
//  ProSecurityStore.swift
//  Sandbox
//
//  One owner for the security profile.
//
//  Every setup screen writes a slice of the same profile and then re-reads it,
//  because the backend decides what `setupStep` becomes — the client proposes,
//  the server confirms. Keeping that in one store means a screen never has to
//  guess where the ladder is up to.
//

import SwiftUI
import Combine
import IVSDK

final class ProSecurityStore: ObservableObject {

    @Published private(set) var profile: ProMonitoringModel?
    @Published private(set) var securityLogs: [SecurityLogsModel] = []
    @Published private(set) var scheduledAlarms: [ScheduledAlarmModel] = []

    /// True once a profile load has come back with no profile on record. The
    /// space is subscribed, setup simply has not begun.
    @Published private(set) var profileNotFound = false

    /// Furthest step the app itself has marked complete. The hub reflects this
    /// immediately, so finishing a step advances the ladder without waiting on
    /// a profile re-read — which may lag, fail, or return a record the backend
    /// has not updated yet.
    @Published private(set) var locallyCompletedStep: SecuritySetupStep?

    private let service: ProMonitoringServiceContract
    /// Reference data (timezones, states) lives on the space service.
    private let spaceService: SpaceServiceContract
    private let sharedData: SharedDataStore

    private var profileCancellable: AnyCancellable?
    private var logsCancellable: AnyCancellable?
    private var scheduleCancellable: AnyCancellable?
    private var actionCancellable: AnyCancellable?

    private var statusPollItem: DispatchWorkItem?

    init(sharedData: SharedDataStore,
         service: ProMonitoringServiceContract = Factory.proMonitoringService,
         spaceService: SpaceServiceContract = Factory.spaceService) {
        self.sharedData = sharedData
        self.service = service
        self.spaceService = spaceService

        NotificationCenter.default.addObserver(forName: .userLogout, object: nil, queue: .main) { [weak self] _ in
            self?.clear()
        }
    }

    deinit { statusPollItem?.cancel() }

    var spaceId: String { sharedData.currentSpaceId }

    var status: ProMonitoringStatus { profile?.systemStatus ?? .disarmed }

    /// Subscription state comes from the space itself. Inferring it from how
    /// `getProfile` fails hides setup from customers who have paid for it.
    var hasPlan: Bool { sharedData.currentSpace?.hasProMonitoringPlan() ?? false }

    /// Someone the space was shared with, rather than its owner. They can watch
    /// the system but cannot configure it — the profile is not theirs.
    var isViewer: Bool {
        sharedData.currentSpace?.monitoring?.role == .viewer
    }

    /// The furthest completed step, taking whichever is further along: what the
    /// server last recorded, or what the app has marked since.
    var completedStep: SecuritySetupStep {
        var furthest = locallyCompletedStep ?? .started

        if let profile {
            // The backend records progress two ways and does not always use
            // both: an explicit list of finished steps, and `setupStep` naming
            // the furthest one reached. Take whichever is further along rather
            // than trusting one of them — reading only `setupStep` misses
            // progress recorded in the list, and vice versa.
            for raw in profile.completedSteps {
                if let step = SecuritySetupStep(rawValue: raw), step.order > furthest.order {
                    furthest = step
                }
            }
            if profile.currentStep.order > furthest.order {
                furthest = profile.currentStep
            }
        }
        return furthest
    }

    /// A step is done once the marker has reached it. Inclusive: the backend
    /// records the furthest step *completed*, not the one outstanding.
    func isComplete(_ step: SecuritySetupStep) -> Bool {
        step.order <= completedStep.order
    }

    /// Finished when the SDK says so, or when the ladder has been walked to the
    /// end — the backend does not always move `setupStep` on to a terminal
    /// value once the last step is done.
    var setupFinished: Bool {
        guard let profile else { return false }
        return profile.setupFinished
            || SecuritySetupStep.visibleSteps.allSatisfy { isComplete($0) }
    }

    /// The first step still outstanding, or nil once the ladder is walked.
    var nextSetupStep: SecuritySetupStep? {
        SecuritySetupStep.visibleSteps.first { !isComplete($0) }
    }

    /// Records a step as done without waiting for the server to confirm it.
    /// Only ever moves forward, so a stale response cannot walk it back.
    func markStepCompleted(_ step: SecuritySetupStep) {
        guard step.order > (locallyCompletedStep?.order ?? -1) else { return }
        locallyCompletedStep = step
    }
    var isTestMode: Bool { profile?.testMode ?? false }

    /// Cameras in this space that are enrolled in the security profile.
    var securedDevices: [DeviceModel] {
        let ids = Set(profile?.securedDeviceIds ?? [])
        return sharedData.devices.filter { ids.contains($0.id) }
    }

    /// A camera can only be armed if it is activated and reachable. Arming a
    /// system where nothing can actually see is worse than not arming at all.
    var armableDevices: [DeviceModel] {
        sharedData.devices.filter { $0.authStatus == .activated }
    }

    var canArm: Bool {
        !securedDevices.isEmpty && securedDevices.contains(where: \.isOnline)
    }

    /// Refreshes the space's camera list. Security screens need it before they
    /// can offer anything to enrol.
    func sharedDataDevices() -> IVPublisher<[DeviceModel]> {
        sharedData.fetchDevices()
    }

    /// The one API error that means "nothing is wrong, there is just no
    /// profile yet". Everything else is a real failure worth surfacing.
    static func isProfileNotFound(_ error: Error) -> Bool {
        (error as? APIError)?.code == "SecurityProfile_NotFound"
    }

    private func clear() {
        profile = nil
        securityLogs = []
        scheduledAlarms = []
        profileNotFound = false
        didCreateProfile = false
        locallyCompletedStep = nil
        statusPollItem?.cancel()
    }

    // MARK: - Profile

    func loadProfile(completion: ((Bool) -> Void)? = nil) -> IVPublisher<ProMonitoringModel> {
        let publisher = service.getProfile(spaceId: spaceId)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                switch state {
                case let .success(profile):
                    self?.profileNotFound = false
                    self?.profile = profile
                    completion?(true)
                case let .error(error):
                    // A subscribed space that has not started setup has no
                    // profile on record yet. The backend says so with this
                    // code, and it is a normal state, not a failure.
                    self?.profileNotFound = Self.isProfileNotFound(error)
                    completion?(false)
                default:
                    break
                }
            })
            .eraseToAnyPublisher()

        profileCancellable = publisher.sink { _ in }
        return publisher
    }

    /// Set once a create has succeeded in this session, so a profile the
    /// backend has not caught up on yet cannot cause a second POST on the next
    /// screen.
    private var didCreateProfile = false

    /// The only condition for creating: nothing loaded. Deliberately *not*
    /// keyed on `profileCreated`, which can be false or absent on a profile
    /// that genuinely exists — gating on it makes the app POST forever and
    /// blocks the user on the first setup screen.
    var needsProfileCreation: Bool { profile == nil && !didCreateProfile }

    /// Creates the profile. The request carries the address and timezone, so
    /// no data PATCH follows it — callers re-read the profile instead.
    func createProfile(_ request: ProMonitoringRequest) -> IVPublisher<Void> {
        service.createProfile(spaceId: spaceId, request: request)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                if case .success = state { self?.didCreateProfile = true }
            })
            .eraseToAnyPublisher()
    }

    /// Advances the setup ladder. `setupStep` names the step being completed;
    /// the response carries whatever the backend decided comes next.
    func setupProfile(_ request: ProMonitoringRequest) -> IVPublisher<ProMonitoringModel> {
        service.setupProfile(spaceId: spaceId, request: request)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                if case let .success(profile) = state {
                    self?.profile = profile
                }
            })
            .eraseToAnyPublisher()
    }

    /// Edits an already-configured profile without touching the ladder.
    func updateProfile(_ request: ProMonitoringRequest) -> IVPublisher<ProMonitoringModel> {
        service.updateProfile(spaceId: spaceId, request: request)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                if case let .success(profile) = state {
                    self?.profile = profile
                }
            })
            .eraseToAnyPublisher()
    }

    func updateDevices(ids: [String]) -> IVPublisher<[ProMonitoringDeviceIDModel]> {
        service.updateDevices(spaceId: spaceId, request: .init(deviceIds: ids))
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                if case .success = state {
                    // The response is only the device list; re-read the profile
                    // so per-camera arm states come with it.
                    _ = self?.loadProfile()
                }
            })
            .eraseToAnyPublisher()
    }

    // MARK: - Reference data

    /// Timezones the monitoring centre recognises. These are not the phone's
    /// timezone database — the backend publishes the set it will accept, and
    /// sending anything else is rejected.
    func loadTimezones() -> IVPublisher<[TimezoneModel]> {
        spaceService.getUSATimezones(spaceId: spaceId)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    // MARK: - Arm / disarm

    func arm() -> IVPublisher<Void> {
        service.armSystem(spaceId: spaceId)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                guard case .success = state else { return }
                self?.pollStatusUntilSettled()
            })
            .eraseToAnyPublisher()
    }

    func disarm() -> IVPublisher<Void> {
        service.disarmSystem(spaceId: spaceId)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                guard case .success = state else { return }
                self?.pollStatusUntilSettled()
            })
            .eraseToAnyPublisher()
    }

    /// Arming is not instant — each camera has to acknowledge. Poll until the
    /// system leaves the transitional state so the UI stops lying about it.
    private func pollStatusUntilSettled(attemptsLeft: Int = 20) {
        statusPollItem?.cancel()
        guard attemptsLeft > 0 else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = self.loadProfile { _ in
                if self.status.isTransitioning {
                    self.pollStatusUntilSettled(attemptsLeft: attemptsLeft - 1)
                }
            }
        }
        statusPollItem = item
        DispatchQueue.global().asyncAfter(deadline: AppConfig.pollingDuration, execute: item)
    }

    func stopStatusPolling() {
        statusPollItem?.cancel()
        statusPollItem = nil
    }

    // MARK: - Test mode

    /// Test mode runs a real arm-and-trigger cycle with the monitoring centre
    /// told to stand down, so nobody is dispatched to your door.
    func enableTestMode(_ enable: Bool) -> IVPublisher<ProMonitoringTestModeModel> {
        service.enableTestMode(spaceId: spaceId, request: .init(enable: enable))
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                if case .success = state { _ = self?.loadProfile() }
            })
            .eraseToAnyPublisher()
    }

    // MARK: - Logs

    func loadSecurityLogs(limit: Int = 50) -> IVPublisher<ListDataModel<SecurityLogsModel>> {
        let publisher = service.securityLogs(
            spaceId: spaceId,
            queryItems: [.init(key: .limit, value: .equal(value: "\(limit)"))],
            sortItem: SortItem(descending: [.createdAt])
        )
        .receive(on: DispatchQueue.main)
        .handleEvents(receiveOutput: { [weak self] state in
            if case let .success(page) = state {
                self?.securityLogs = page.items
            }
        })
        .eraseToAnyPublisher()

        logsCancellable = publisher.sink { _ in }
        return publisher
    }

    // MARK: - Schedules

    func loadSchedules() -> IVPublisher<ScheduledAlarmModelResponse> {
        guard let profileId = profile?.copsId, !profileId.isEmpty else {
            return Just(.success(data: ScheduledAlarmModelResponse(items: []))).eraseToAnyPublisher()
        }
        let publisher = service.getScheduledAlarms(spaceId: spaceId, securityProfileId: profileId)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                if case let .success(response) = state {
                    self?.scheduledAlarms = response.items
                }
            })
            .eraseToAnyPublisher()
        scheduleCancellable = publisher.sink { _ in }
        return publisher
    }

    func addSchedule(_ request: ScheduledAlarmRequest) -> IVPublisher<Void> {
        guard let profileId = profile?.copsId else {
            return Just(.error(error: IVError.customError(Message: "Security profile is not ready yet."))).eraseToAnyPublisher()
        }
        return service.scheduleAlarm(spaceId: spaceId, securityProfileId: profileId, request: request)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func updateSchedule(id: String, request: ScheduledAlarmRequest) -> IVPublisher<Void> {
        guard let profileId = profile?.copsId else {
            return Just(.error(error: IVError.customError(Message: "Security profile is not ready yet."))).eraseToAnyPublisher()
        }
        return service.updateScheduledAlarm(spaceId: spaceId,
                                            securityProfileId: profileId,
                                            scheduleId: id,
                                            request: request)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func deleteSchedules(ids: [String]) -> IVPublisher<Void> {
        guard let profileId = profile?.copsId else {
            return Just(.error(error: IVError.customError(Message: "Security profile is not ready yet."))).eraseToAnyPublisher()
        }
        return service.deleteScheduledAlarm(spaceId: spaceId,
                                            securityProfileId: profileId,
                                            request: .init(scheduleIds: ids))
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                if case .success = state {
                    self?.scheduledAlarms.removeAll { ids.contains($0.id) }
                }
            })
            .eraseToAnyPublisher()
    }

    // MARK: - Responding parties

    /// The monitoring centre calls these people, in order, before dispatching.
    func sendOtp(phone: PhoneNumber) -> IVPublisher<Void> {
        service.sendOtp(request: phone)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func updateRespondingParty(_ request: RespondingPartyPhoneNumberRequest) -> IVPublisher<Void> {
        service.updateInviteePhoneNumber(spaceId: spaceId, request: request)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                if case .success = state { _ = self?.loadProfile() }
            })
            .eraseToAnyPublisher()
    }
}
