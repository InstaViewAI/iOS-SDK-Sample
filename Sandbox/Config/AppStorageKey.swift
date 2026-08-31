//
//  AppStorageKey.swift
//  Sandbox
//
//  Every UserDefaults key the app reads through @AppStorage.
//

import Foundation

enum AppStorageKey: String {
    case userDetails
    case isLoggedIn
    case lastLoggedInUser
    case currentSpace
    case serverRegion
    case loginType
    case rememberedWiFiPassword
}
