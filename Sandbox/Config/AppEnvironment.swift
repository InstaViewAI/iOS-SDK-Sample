//
//  AppEnvironment.swift
//  Sandbox
//
//  Reads the values the .xcconfig files stamp into Info.plist.
//

import Foundation
import IVSDK

enum AppEnvironment {
    enum Environment: String {
        case dev = "Dev"
        case staging = "Staging"
        case prod = "Prod"

        /// Maps onto the SDK's own environment enum.
        var sdkEnvironment: IVSDK.Environment {
            switch self {
            case .dev: return .dev
            case .staging: return .staging
            case .prod: return .production
            }
        }
    }

    private enum Keys: String {
        case appEnvironment = "AppEnvironment"
        case partner = "Partner"
    }

    static let environment: Environment = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: Keys.appEnvironment.rawValue) as? String,
              let environment = Environment(rawValue: raw) else {
            fatalError("AppEnvironment missing from Info.plist — check the active .xcconfig")
        }
        return environment
    }()

    /// This app ships a single partner. The value is here rather than hardcoded
    /// so the build configuration stays the one place brand identity is decided.
    static let partner: String = {
        Bundle.main.object(forInfoDictionaryKey: Keys.partner.rawValue) as? String ?? "Sandbox"
    }()
}
