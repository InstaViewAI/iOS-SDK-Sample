//
//  ProSecurityModels.swift
//  Sandbox
//
//  Vocabulary for professional monitoring — the setup ladder, the delay
//  options, and how the SDK's status strings read on screen.
//

import SwiftUI
import IVSDK

/// The onboarding ladder. The backend stores progress as `setupStep`, so these
/// raw values are a contract with it, not a local convenience — a client that
/// invents its own names loses the ability to resume a half-finished setup.
enum SecuritySetupStep: String, CaseIterable, Comparable {
    case started            = "Started"
    case contactInformation = "ContactInformation"
    case cameraSetup        = "CameraSetup"
    case armSettings        = "ArmSettings"
    case disarmSettings     = "DisarmSettings"
    case scheduleSystem     = "ScheduleSystem"
    case testSystem         = "TestSystem"
    case inviteHousehold    = "InviteHouseholds"
    case completed          = "Completed"

    var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static func < (lhs: SecuritySetupStep, rhs: SecuritySetupStep) -> Bool {
        lhs.order < rhs.order
    }

    /// Steps shown as rows on the setup hub. `started` and `completed` are
    /// bookends the backend uses, not things the user does.
    static var visibleSteps: [SecuritySetupStep] {
        allCases.filter { $0 != .started && $0 != .completed }
    }

    var title: String {
        switch self {
        case .started:            return "Started"
        case .contactInformation: return "Contact information"
        case .cameraSetup:        return "Camera setup"
        case .armSettings:        return "Arm settings"
        case .disarmSettings:     return "Disarm settings"
        case .scheduleSystem:     return "Schedule"
        case .testSystem:         return "Test the system"
        case .inviteHousehold:    return "Invite your household"
        case .completed:          return "Completed"
        }
    }

    var subtitle: String {
        switch self {
        case .contactInformation: return "Address, phone number, alarm permit"
        case .cameraSetup:        return "Choose cameras and set security zones"
        case .armSettings:        return "How long you get to leave"
        case .disarmSettings:     return "Disarm methods and your safe word"
        case .scheduleSystem:     return "Arm and disarm automatically"
        case .testSystem:         return "A live run without calling anyone"
        case .inviteHousehold:    return "Let others disarm the system"
        default:                  return ""
        }
    }

    var icon: String {
        switch self {
        case .contactInformation: return "mappin.and.ellipse"
        case .cameraSetup:        return "video.badge.checkmark"
        case .armSettings:        return "lock.shield"
        case .disarmSettings:     return "key.horizontal"
        case .scheduleSystem:     return "calendar.badge.clock"
        case .testSystem:         return "checkmark.shield"
        case .inviteHousehold:    return "person.2"
        default:                  return "circle"
        }
    }

    /// Monitoring cannot begin without these, so their screens have no skip.
    var canSkip: Bool {
        switch self {
        case .scheduleSystem, .testSystem, .inviteHousehold: return true
        default: return false
        }
    }

    /// Where tapping this row goes.
    func destination(screenFrom: ScreenFrom) -> Destination {
        switch self {
        case .contactInformation: return .securityContactInfo(screenFrom: screenFrom)
        case .cameraSetup:        return .securityCameraIntro(page: 1, screenFrom: screenFrom)
        case .armSettings:        return .securityArmSettings(screenFrom: screenFrom)
        case .disarmSettings:     return .securityDisarmMethod(screenFrom: screenFrom)
        case .scheduleSystem:     return .securitySchedule(screenFrom: screenFrom)
        case .testSystem:         return .securityCriticalAlerts(screenFrom: screenFrom)
        case .inviteHousehold:    return .securityInviteHousehold(screenFrom: screenFrom)
        default:                  return .securitySetup(screenFrom: screenFrom)
        }
    }
}

/// Seconds between arming and the system going live — long enough to get out
/// of the door without tripping your own alarm.
enum DelayTime: Int, CaseIterable, Identifiable {
    case sec30 = 30, sec45 = 45, sec60 = 60, sec90 = 90, sec120 = 120

    var id: Int { rawValue }
    var title: String { "\(rawValue) seconds" }

    init(value: Int?) {
        self = DelayTime(rawValue: value ?? 30) ?? .sec30
    }
}

/// How long you get to cancel an alarm before the monitoring centre is told.
enum DismissAlarmTime: Int, CaseIterable, Identifiable {
    case sec30 = 30, sec45 = 45, sec60 = 60

    var id: Int { rawValue }
    var title: String { "\(rawValue) seconds" }

    init(value: Int?) {
        self = DismissAlarmTime(rawValue: value ?? 30) ?? .sec30
    }
}

extension ProMonitoringStatus {
    var title: String {
        switch self {
        case .disarmed:  return "Disarmed"
        case .armedAll:  return "Armed"
        case .arming:    return "Arming…"
        case .disarming: return "Disarming…"
        @unknown default: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .armedAll:            return AppColors.error
        case .arming, .disarming:  return AppColors.warning
        case .disarmed:            return AppColors.success
        @unknown default:          return AppColors.offline
        }
    }

    var icon: String {
        switch self {
        case .armedAll:            return "lock.shield.fill"
        case .arming, .disarming:  return "hourglass"
        case .disarmed:            return "lock.open"
        @unknown default:          return "questionmark.circle"
        }
    }

    /// Arm and disarm both take a few seconds and the backend reports the
    /// transition; the control stays locked out until it settles.
    var isTransitioning: Bool {
        self == .arming || self == .disarming
    }
}

extension ProMonitoringDeviceState {
    var title: String {
        switch self {
        case .disarmed:  return "Disarmed"
        case .armed:     return "Armed"
        case .arming:    return "Arming"
        case .disarming: return "Disarming"
        case .failed:    return "Failed to arm"
        case .notArmed:  return "Not armed"
        @unknown default: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .armed:               return AppColors.error
        case .arming, .disarming:  return AppColors.warning
        case .failed, .notArmed:   return AppColors.warning
        case .disarmed:            return AppColors.textSecondary
        @unknown default:          return AppColors.offline
        }
    }
}

/// Entries in the security log. Raw values match what the backend sends.
enum SecurityLogType: String, CaseIterable {
    case armed     = "Armed"
    case disarmed  = "Disarmed"
    case event     = "Event"
    case sms       = "SMS"
    case agentCall = "AgentCall"
    case dispatch  = "Dispatch"
    case sendHelp  = "SendHelp"
    case none      = ""

    var title: String {
        switch self {
        case .armed:     return "System armed"
        case .disarmed:  return "System disarmed"
        case .sms:       return "Text message sent"
        case .agentCall: return "Agent called you"
        case .dispatch:  return "Authorities dispatched"
        case .sendHelp:  return "Help requested"
        case .event:     return "Alarm event"
        case .none:      return "Activity"
        }
    }

    var icon: String {
        switch self {
        case .armed:     return "lock.shield.fill"
        case .disarmed:  return "lock.open.fill"
        case .sms:       return "message.fill"
        case .agentCall: return "phone.fill"
        case .dispatch:  return "shield.lefthalf.filled"
        case .sendHelp:  return "exclamationmark.triangle.fill"
        case .event:     return "bell.fill"
        case .none:      return "circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .armed:                return AppColors.error
        case .disarmed:             return AppColors.success
        case .dispatch, .sendHelp:  return AppColors.error
        case .agentCall, .sms:      return AppColors.warning
        default:                    return AppColors.textSecondary
        }
    }
}

/// Per-camera outcome of an arm attempt, recorded in the log.
enum SecurityDeviceArmStatus: String {
    case success  = "Success"
    case arming   = "Arming"
    case failure  = "Failure"
    case notArmed = "NotArmed"

    var title: String {
        switch self {
        case .success:  return "Armed"
        case .arming:   return "Arming"
        case .failure:  return "Failed to arm"
        case .notArmed: return "Not armed — battery too low"
        }
    }
}

extension SecurityLogsModel {
    var logType: SecurityLogType { SecurityLogType(rawValue: type) ?? .none }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000) }
}

extension ProMonitoringModel {
    var systemStatus: ProMonitoringStatus {
        ProMonitoringStatus(rawValue: status ?? "") ?? .disarmed
    }

    var currentStep: SecuritySetupStep {
        SecuritySetupStep(rawValue: setupStep) ?? .started
    }

    // Completion lives on ProSecurityStore, which combines what the server
    // recorded with what the app has marked since. Deliberately not duplicated
    // here — two definitions of "complete" is how the two drift apart.

    var securedDeviceIds: [String] {
        deviceList?.map(\.id) ?? []
    }

    func state(for deviceId: String) -> ProMonitoringDeviceState {
        guard let entry = deviceList?.first(where: { $0.id == deviceId }) else { return .disarmed }
        return ProMonitoringDeviceState(rawValue: entry.state) ?? .disarmed
    }
}
