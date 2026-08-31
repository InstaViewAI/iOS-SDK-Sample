//
//  AppConfig.swift
//  Sandbox
//

import Foundation
import UIKit

enum AppConfig {
    /// Partner id the SDK is configured with. One partner, one target.
    static let partnerId = "iv_sandbox"

    /// How often the pairing and email-verification flows re-poll the backend.
    static var pollingDuration: DispatchTime { .now() + 3 }

    /// A pairing session key stays valid for three minutes.
    static let pairingSessionTimeout: TimeInterval = 180

    /// A device reporting this cluster group version has no cluster document
    /// and must be configured through the legacy device-settings API.
    static let legacyClusterGroupVersion = "v0"

    /// Model ids that take the 4G/SIM branch of the pairing flow instead of Wi-Fi.
    static let fourGModelIds: Set<String> = ["IV4G01", "IV4G02", "TRAIL4G01"]

    /// Model ids that run the doorbell installation sequence after pairing.
    static let doorbellModelIds: Set<String> = ["IVDB01", "IVDB02", "AONIDB01"]

    /// Where the browser-based viewer lives. One partner, so this only varies
    /// by environment.
    static var vmsAccessUrl: String {
        switch AppEnvironment.environment {
        case .prod:    return "https://sandbox-vms.instavision.ai"
        case .staging: return "https://stg-vms.instaview.ai"
        case .dev:     return "https://dev-vms.instaview.ai"
        }
    }

    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }
}

let ScreenSize = UIScreen.main.bounds
