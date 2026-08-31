//
//  SandboxApp.swift
//  Sandbox
//

import SwiftUI
import Firebase
import GoogleSignIn
@_exported import IVSDK

@main
struct SandboxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var appWindowManager = AppWindowManager()
    @StateObject private var sharedData: SharedDataStore
    @StateObject private var spaceDataStore: SpaceDataStore
    @StateObject private var eventsDataStore: EventsDataStore
    @StateObject private var proSecurityStore: ProSecurityStore
    @StateObject private var tokenStore = B2TokenStore()

    init() {
        let shared = SharedDataStore()
        _sharedData = StateObject(wrappedValue: shared)
        _spaceDataStore = StateObject(wrappedValue: SpaceDataStore(sharedData: shared))
        _eventsDataStore = StateObject(wrappedValue: EventsDataStore(sharedData: shared))
        _proSecurityStore = StateObject(wrappedValue: ProSecurityStore(sharedData: shared))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(sharedData: sharedData,
                            spaceDataStore: spaceDataStore,
                            eventsDataStore: eventsDataStore,
                            proSecurityStore: proSecurityStore,
                            tokenStore: tokenStore)

                Loader(show: $appWindowManager.isLoading, message: appWindowManager.loaderMessage)
                    .zIndex(1)

                if AppEnvironment.environment != .prod {
                    // Small build badge, so a tester can tell dev from prod.
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(AppEnvironment.environment.rawValue) \(AppConfig.appVersion)")
                                .font(AppFont.caption(9))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.error)
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
                }
            }
            .preferredColorScheme(.dark)
            .environmentObject(appWindowManager)
            .environmentObject(sharedData)
            .onAppear {
                // The SDK raises this when the refresh token can no longer be
                // renewed. Everything below the root is torn down.
                NotificationCenter.default.addObserver(forName: .sessionTokenExpired,
                                                       object: nil, queue: .main) { _ in
                    Logger.debugLog("Session expired — returning to onboarding")
                    appWindowManager.hideLoader()
                    guard appWindowManager.rootWindow != .onboarding else { return }
                    appWindowManager.logout()
                }
            }
        }
    }
}
