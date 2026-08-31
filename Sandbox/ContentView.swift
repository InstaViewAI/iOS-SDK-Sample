//
//  ContentView.swift
//  Sandbox
//
//  The single place a Destination becomes a view. Adding a screen means one
//  case here and one in Destination.
//

import SwiftUI
import IVSDK

struct ContentView: View {
    @EnvironmentObject private var appWindowManager: AppWindowManager
    @ObservedObject var sharedData: SharedDataStore
    @ObservedObject var spaceDataStore: SpaceDataStore
    @ObservedObject var eventsDataStore: EventsDataStore
    @ObservedObject var proSecurityStore: ProSecurityStore
    @ObservedObject var tokenStore: B2TokenStore

    @StateObject private var pilot = UIPilot<Destination>()

    var body: some View {
        UIPilotHost(pilot) { route in
            view(for: route)
        }
        .onAppear { applyRoot(appWindowManager.rootWindow) }
        .onChange(of: appWindowManager.rootWindow) { applyRoot($0) }
    }

    private func applyRoot(_ root: AppWindowManager.RootWindow) {
        switch root {
        case .onboarding:
            pilot.changeRoot(.onboarding)
        case .appTabBar:
            pilot.changeRoot(.appTabBar)
        }
    }

    @ViewBuilder
    private func view(for route: Destination) -> some View {
        switch route {

        // MARK: Onboarding
        case .onboarding:
            OnboardingScreen()

        case .login:
            LoginScreen(viewModel: .init(sharedData: sharedData, spaceDataStore: spaceDataStore))

        case .signUp:
            SignUpScreen(viewModel: .init(sharedData: sharedData, spaceDataStore: spaceDataStore))

        case .forgotPassword:
            ForgotPasswordScreen(viewModel: .init())

        case let .emailVerify(autoTriggerEmail):
            EmailVerifyScreen(viewModel: .init(spaceDataStore: spaceDataStore),
                              autoTriggerEmail: autoTriggerEmail)

        // MARK: Space
        case let .spaceScreen(space):
            SpaceScreen(viewModel: .init(space: space,
                                         sharedData: sharedData,
                                         spaceDataStore: spaceDataStore))

        // MARK: Main
        case .appTabBar:
            AppTabBarView(sharedData: sharedData,
                          spaceDataStore: spaceDataStore,
                          eventsDataStore: eventsDataStore,
                          proSecurityStore: proSecurityStore)

        // MARK: Pairing — entry
        case let .cameraPermission(screenFrom):
            CameraPermissionScreen(screenFrom: screenFrom)

        case let .turnOnCamera(device, screenFrom):
            TurnOnCameraScreen(device: device, screenFrom: screenFrom)

        case let .cameraReset(device, screenFrom):
            CameraResetScreen(device: device, screenFrom: screenFrom)

        case let .troubleshootCamera(screenFrom):
            TroubleshootCameraScreen(screenFrom: screenFrom)

        // MARK: Pairing — BLE
        case let .cameraSearch(screenFrom):
            CameraSearchScreen(viewModel: .init(), screenFrom: screenFrom)

        case let .cameraSearchFail(screenFrom):
            CameraSearchFailScreen(screenFrom: screenFrom)

        case let .bleCameraList(screenFrom):
            BLECameraListScreen(viewModel: .init(), screenFrom: screenFrom)

        case let .bleCameraWiFiSearching(camera, screenFrom):
            BleCameraWiFiSearchingScreen(viewModel: .init(camera: camera), screenFrom: screenFrom)

        case let .bleWiFiScanFail(screenFrom):
            BleWiFiScanFailScreen(screenFrom: screenFrom)

        case let .cameraWiFiList(screenFrom):
            CameraWiFiListScreen(viewModel: .init(), screenFrom: screenFrom)

        // MARK: Pairing — credentials and handshake
        case let .selectWiFi(mode, ssid, screenFrom):
            SelectWiFiScreen(viewModel: .init(sharedData: sharedData, mode: mode, presetSSID: ssid),
                             screenFrom: screenFrom)

        case let .scanWiFiQRCode(payload, screenFrom):
            ScanWiFiQRCodeScreen(viewModel: .init(sharedData: sharedData, payload: payload),
                                 screenFrom: screenFrom)

        case let .retrievePairingStatus(sessionKey, deviceId, screenFrom):
            RetrievePairingStatusScreen(viewModel: .init(sharedData: sharedData,
                                                         sessionKey: sessionKey,
                                                         deviceId: deviceId),
                                        screenFrom: screenFrom)

        case let .cameraAuthEmail(deviceId, screenFrom):
            CameraAuthEmailScreen(viewModel: .init(sharedData: sharedData, deviceId: deviceId),
                                  screenFrom: screenFrom)

        case let .pairCameraError(reason, screenFrom):
            PairCameraErrorScreen(reason: reason, screenFrom: screenFrom)

        // MARK: Pairing — 4G / SIM
        case let .insertSimCard(deviceId, screenFrom):
            InsertSimCardScreen(deviceId: deviceId, screenFrom: screenFrom)

        case let .scanCameraCode(screenFrom):
            ScanCameraCodeScreen(viewModel: .init(sharedData: sharedData), screenFrom: screenFrom)

        case let .simNumber(code, deviceId, screenFrom):
            SimNumberScreen(viewModel: .init(sharedData: sharedData, code: code, deviceId: deviceId),
                            screenFrom: screenFrom)

        case let .reset4gCamera(deviceId, screenFrom):
            Reset4GCameraScreen(deviceId: deviceId, screenFrom: screenFrom, sharedData: sharedData)

        // MARK: Playback
        case let .liveView(device):
            LiveViewScreen(viewModel: .init(device: device, sharedData: sharedData))

        case let .eventPlayer(event):
            EventPlayerScreen(viewModel: .init(event: event,
                                               eventsDataStore: eventsDataStore,
                                               tokenStore: tokenStore))

        // MARK: Camera settings
        case let .cameraSettings(device):
            CameraSettingsScreen(viewModel: .init(device: device, sharedData: sharedData))

        case let .cameraInfo(device):
            CameraInfoScreen(viewModel: .init(device: device, sharedData: sharedData))

        case let .eventSettings(device):
            EventSettingsScreen(viewModel: .init(device: device, sharedData: sharedData))

        case let .notificationSettings(device):
            NotificationSettingsScreen(viewModel: .init(device: device, sharedData: sharedData))

        case let .audioSettings(device):
            AudioSettingsScreen(viewModel: .init(device: device, sharedData: sharedData))

        case let .liveViewSettings(device):
            LiveViewSettingsScreen(viewModel: .init(device: device, sharedData: sharedData))

        case let .updateFirmware(device):
            UpdateFirmwareScreen(viewModel: .init(device: device, sharedData: sharedData))

        // MARK: Pro security — setup ladder
        case let .securitySetup(screenFrom):
            ProSecuritySetupScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securityContactInfo(screenFrom):
            SecurityContactInfoScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securityPhoneNumber(screenFrom):
            SecurityPhoneNumberScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securityVerifyPhone(phone, dialCode, screenFrom):
            SecurityVerifyPhoneScreen(viewModel: .init(store: proSecurityStore,
                                                       screenFrom: screenFrom,
                                                       phone: phone,
                                                       dialCode: dialCode))

        case let .securityAlarmPermit(screenFrom):
            SecurityAlarmPermitScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securityCameraIntro(page, screenFrom):
            SecurityCameraIntroScreen(page: page, screenFrom: screenFrom)

        case let .securityCameraSelection(screenFrom):
            SecurityCameraSelectionScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securityZoneSettings(screenFrom):
            SecurityZoneScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securityArmSettings(screenFrom):
            SecurityArmSettingsScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securityDisarmMethod(screenFrom):
            SecurityDisarmMethodScreen(screenFrom: screenFrom)

        case let .securitySafeWord(screenFrom):
            SecuritySafeWordScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securitySchedule(screenFrom):
            SecurityScheduleScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securityEditSchedule(schedule, screenFrom):
            SecurityEditScheduleScreen(viewModel: .init(store: proSecurityStore,
                                                        screenFrom: screenFrom,
                                                        schedule: schedule))

        case let .securityCriticalAlerts(screenFrom):
            SecurityCriticalAlertsScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securitySystemTest(screenFrom):
            SecuritySystemTestScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case let .securityInviteHousehold(screenFrom):
            SecurityInviteHouseholdScreen(viewModel: .init(store: proSecurityStore, screenFrom: screenFrom))

        case .securitySetupFinish:
            SecuritySetupFinishScreen()

        // MARK: Pro security — running system
        case .securityLogs:
            SecurityLogsScreen(viewModel: .init(store: proSecurityStore))

        case .securitySettings:
            ProSecuritySettingsScreen(viewModel: .init(store: proSecurityStore))

        case .securityUpdatePersonalInfo:
            SecurityPersonalInfoScreen(viewModel: .init(store: proSecurityStore,
                                                        screenFrom: .securitySettings))

        case .securityUpdateSafeWord:
            SecurityUpdateSafeWordScreen(viewModel: .init(store: proSecurityStore,
                                                          screenFrom: .securitySettings))

        case .securityTeam:
            SecurityTeamScreen(viewModel: .init(store: proSecurityStore,
                                                screenFrom: .securitySettings))

        // MARK: Account
        case .vms:
            VMSScreen(viewModel: .init(sharedData: sharedData))

        case .myAccount:
            MyAccountScreen(viewModel: .init())

        case .changePassword:
            ChangePasswordScreen(viewModel: .init())
        }
    }
}
