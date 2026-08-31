//
//  Destination.swift
//  Sandbox
//
//  Every screen in the app, in one enum. ContentView is the only place that
//  maps a case onto a view, so the navigation graph stays readable.
//

import Foundation
import IVSDK

/// Where a pairing flow was entered from. Decides where "done" and "quit"
/// return to, since the same screens are reachable from onboarding, the home
/// screen, and camera settings.
enum ScreenFrom: String {
    case onboarding
    case home
    case cameraSettings
    /// Reached from the security dashboard or its settings, rather than from
    /// the first run through setup — decides where "done" returns to.
    case security
    case securitySettings
}

/// Which transport carries the Wi-Fi credentials to the camera.
enum CameraPairingMode: String {
    case qrCode      // camera scans a QR code shown on the phone
    case bluetooth   // credentials pushed over BLE
    case fourG       // no Wi-Fi at all; SIM bootstrap
}

enum Destination: Equatable {

    // MARK: Onboarding
    case onboarding
    case login
    case signUp
    case forgotPassword
    case emailVerify(autoTriggerEmail: Bool)

    // MARK: Space
    /// `space == nil` creates a first space; non-nil edits an existing one.
    case spaceScreen(space: SpaceModel? = nil)

    // MARK: Main
    case appTabBar

    // MARK: Pairing — entry
    case cameraPermission(screenFrom: ScreenFrom)
    case turnOnCamera(device: DeviceModel?, screenFrom: ScreenFrom)
    case cameraReset(device: DeviceModel?, screenFrom: ScreenFrom)
    case troubleshootCamera(screenFrom: ScreenFrom)

    // MARK: Pairing — BLE discovery
    case cameraSearch(screenFrom: ScreenFrom)
    case cameraSearchFail(screenFrom: ScreenFrom)
    case bleCameraList(screenFrom: ScreenFrom)
    case bleCameraWiFiSearching(camera: BLECamera, screenFrom: ScreenFrom)
    case bleWiFiScanFail(screenFrom: ScreenFrom)
    case cameraWiFiList(screenFrom: ScreenFrom)

    // MARK: Pairing — credentials and handshake
    case selectWiFi(mode: CameraPairingMode, ssid: String?, screenFrom: ScreenFrom)
    case scanWiFiQRCode(payload: PairingPayload, screenFrom: ScreenFrom)
    case retrievePairingStatus(sessionKey: String, deviceId: String, screenFrom: ScreenFrom)
    case cameraAuthEmail(deviceId: String, screenFrom: ScreenFrom)
    case pairCameraError(reason: PairFailureReason, screenFrom: ScreenFrom)

    // MARK: Pairing — 4G / SIM
    case insertSimCard(deviceId: String, screenFrom: ScreenFrom)
    case scanCameraCode(screenFrom: ScreenFrom)
    case simNumber(code: String, deviceId: String, screenFrom: ScreenFrom)
    case reset4gCamera(deviceId: String, screenFrom: ScreenFrom)

    // MARK: Playback
    case liveView(device: DeviceModel)
    case eventPlayer(event: EventModel)

    // MARK: Camera settings
    case cameraSettings(device: DeviceModel)
    case cameraInfo(device: DeviceModel)
    case eventSettings(device: DeviceModel)
    case notificationSettings(device: DeviceModel)
    case audioSettings(device: DeviceModel)
    case liveViewSettings(device: DeviceModel)
    case updateFirmware(device: DeviceModel)

    // MARK: Pro security — setup ladder
    case securitySetup(screenFrom: ScreenFrom)
    case securityContactInfo(screenFrom: ScreenFrom)
    case securityPhoneNumber(screenFrom: ScreenFrom)
    case securityVerifyPhone(phone: String, dialCode: String, screenFrom: ScreenFrom)
    case securityAlarmPermit(screenFrom: ScreenFrom)
    case securityCameraIntro(page: Int, screenFrom: ScreenFrom)
    case securityCameraSelection(screenFrom: ScreenFrom)
    case securityZoneSettings(screenFrom: ScreenFrom)
    case securityArmSettings(screenFrom: ScreenFrom)
    case securityDisarmMethod(screenFrom: ScreenFrom)
    case securitySafeWord(screenFrom: ScreenFrom)
    case securitySchedule(screenFrom: ScreenFrom)
    case securityEditSchedule(schedule: ScheduledAlarmModel?, screenFrom: ScreenFrom)
    case securityCriticalAlerts(screenFrom: ScreenFrom)
    case securitySystemTest(screenFrom: ScreenFrom)
    case securityInviteHousehold(screenFrom: ScreenFrom)
    case securitySetupFinish

    // MARK: Pro security — running system
    case securityLogs
    case securitySettings
    case securityUpdatePersonalInfo
    case securityUpdateSafeWord
    case securityTeam

    // MARK: Account
    case vms
    case myAccount
    case changePassword

    /// Stable identity for a route. Two routes are the same screen when their
    /// keys match — which is what `popTo` needs, and what lets the enum stay
    /// Equatable while carrying models that are not.
    var key: String {
        switch self {
        case .onboarding:                   return "onboarding"
        case .login:                        return "login"
        case .signUp:                       return "signUp"
        case .forgotPassword:               return "forgotPassword"
        case .emailVerify:                  return "emailVerify"
        case let .spaceScreen(space):       return "spaceScreen_\(space?.id ?? "new")"
        case .appTabBar:                    return "appTabBar"

        case .cameraPermission:             return "cameraPermission"
        case let .turnOnCamera(device, _):  return "turnOnCamera_\(device?.id ?? "")"
        case let .cameraReset(device, _):   return "cameraReset_\(device?.id ?? "")"
        case .troubleshootCamera:           return "troubleshootCamera"

        case .cameraSearch:                 return "cameraSearch"
        case .cameraSearchFail:             return "cameraSearchFail"
        case .bleCameraList:                return "bleCameraList"
        case let .bleCameraWiFiSearching(camera, _): return "bleCameraWiFiSearching_\(camera.identifier)"
        case .bleWiFiScanFail:              return "bleWiFiScanFail"
        case .cameraWiFiList:               return "cameraWiFiList"

        case let .selectWiFi(mode, _, _):   return "selectWiFi_\(mode.rawValue)"
        case .scanWiFiQRCode:               return "scanWiFiQRCode"
        case .retrievePairingStatus:        return "retrievePairingStatus"
        case .cameraAuthEmail:              return "cameraAuthEmail"
        case .pairCameraError:              return "pairCameraError"

        case let .insertSimCard(deviceId, _): return "insertSimCard_\(deviceId)"
        case .scanCameraCode:               return "scanCameraCode"
        case .simNumber:                    return "simNumber"
        case let .reset4gCamera(deviceId, _): return "reset4gCamera_\(deviceId)"

        case let .liveView(device):         return "liveView_\(device.id)"
        case let .eventPlayer(event):       return "eventPlayer_\(event.id)"
        case let .cameraSettings(device):   return "cameraSettings_\(device.id)"
        case let .cameraInfo(device):       return "cameraInfo_\(device.id)"
        case let .eventSettings(device):    return "eventSettings_\(device.id)"
        case let .notificationSettings(device): return "notificationSettings_\(device.id)"
        case let .audioSettings(device):    return "audioSettings_\(device.id)"
        case let .liveViewSettings(device): return "liveViewSettings_\(device.id)"
        case let .updateFirmware(device):   return "updateFirmware_\(device.id)"

        case .securitySetup:                return "securitySetup"
        case .securityContactInfo:          return "securityContactInfo"
        case .securityPhoneNumber:          return "securityPhoneNumber"
        case .securityVerifyPhone:          return "securityVerifyPhone"
        case .securityAlarmPermit:          return "securityAlarmPermit"
        case let .securityCameraIntro(page, _): return "securityCameraIntro_\(page)"
        case .securityCameraSelection:      return "securityCameraSelection"
        case .securityZoneSettings:         return "securityZoneSettings"
        case .securityArmSettings:          return "securityArmSettings"
        case .securityDisarmMethod:         return "securityDisarmMethod"
        case .securitySafeWord:             return "securitySafeWord"
        case .securitySchedule:             return "securitySchedule"
        case let .securityEditSchedule(schedule, _): return "securityEditSchedule_\(schedule?.id ?? "new")"
        case .securityCriticalAlerts:       return "securityCriticalAlerts"
        case .securitySystemTest:           return "securitySystemTest"
        case .securityInviteHousehold:      return "securityInviteHousehold"
        case .securitySetupFinish:          return "securitySetupFinish"

        case .securityLogs:                 return "securityLogs"
        case .securitySettings:             return "securitySettings"
        case .securityUpdatePersonalInfo:   return "securityUpdatePersonalInfo"
        case .securityUpdateSafeWord:       return "securityUpdateSafeWord"
        case .securityTeam:                 return "securityTeam"

        case .vms:                          return "vms"
        case .myAccount:                    return "myAccount"
        case .changePassword:               return "changePassword"
        }
    }

    static func == (lhs: Destination, rhs: Destination) -> Bool {
        lhs.key == rhs.key
    }
}

/// Everything the camera needs to join the network and claim itself against
/// this account. Encoded into the QR code, or written over BLE.
struct PairingPayload: Equatable {
    let ssid: String
    let password: String
    let sessionKey: String
    /// Numeric server region the camera should talk to.
    let region: String
    /// Numeric environment: 1 prod, 2 staging, 3 dev.
    let env: String

    /// Newline-separated, in the exact order the camera firmware parses.
    var qrCodeString: String {
        "\(ssid)\n\(password)\n\(sessionKey)\n\(region)\n\(env)"
    }
}

enum PairFailureReason: String {
    case sessionExpired
    case qrNotScanned
    case wifiRejected
    case cameraUnreachable

    var title: String {
        switch self {
        case .sessionExpired:   return "Setup timed out"
        case .qrNotScanned:     return "Camera did not read the code"
        case .wifiRejected:     return "Camera could not join that network"
        case .cameraUnreachable: return "Lost contact with the camera"
        }
    }

    var message: String {
        switch self {
        case .sessionExpired:
            return "The setup code is only valid for three minutes. Start again to get a fresh one."
        case .qrNotScanned:
            return "Hold the code 8–12 inches from the lens and keep it steady until the camera chimes."
        case .wifiRejected:
            return "Double-check the network name and password. Cameras join 2.4 GHz networks only."
        case .cameraUnreachable:
            return "Make sure the camera still has power and is within range of your router."
        }
    }
}
