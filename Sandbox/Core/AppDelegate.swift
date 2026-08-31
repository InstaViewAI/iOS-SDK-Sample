//
//  AppDelegate.swift
//  Sandbox
//
//  SDK and Firebase bootstrap, plus push registration.
//

import UIKit
import SwiftUI
import Firebase
import GoogleSignIn
import IVSDK

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static private(set) var instance: AppDelegate!
    var apnsToken: String?

    /// The app is portrait-only apart from live video, which sets this to
    /// `.all` while it is on screen and restores it on the way out.
    static var orientation: UIInterfaceOrientationMask = .portrait {
        didSet {
            guard orientation != oldValue else { return }
            DispatchQueue.main.async {
                if #available(iOS 16.0, *) {
                    UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .forEach { $0.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) }
                    UIViewController.attemptRotationToDeviceOrientation()
                } else {
                    // Nudging the device orientation is the only pre-iOS 16
                    // way to make the system re-ask for supported masks.
                    let value = (orientation == .portrait)
                        ? UIInterfaceOrientation.portrait.rawValue
                        : UIInterfaceOrientation.unknown.rawValue
                    UIDevice.current.setValue(value, forKey: "orientation")
                    UIViewController.attemptRotationToDeviceOrientation()
                }
            }
        }
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppDelegate.instance = self

        // Firebase backs the SDK's email/password, Google and Apple sign-in.
        FirebaseApp.configure()
        configureIVSDK()
        registerForRemoteNotifications()

        application.applicationIconBadgeNumber = 0
        return true
    }

    private func configureIVSDK() {
        // Region is remembered across launches because it decides which
        // regional backend the account and its cameras live on — pairing a
        // camera against the wrong region silently fails.
        let storedRegion = UserDefaults.standard.string(forKey: AppStorageKey.serverRegion.rawValue)
        let region = ServerRegion(rawValue: storedRegion ?? "") ?? .us

        InstaSDK.shared.configure(partnerId: AppConfig.partnerId,
                                  region: region,
                                  environment: .production)

        Logger.debugLog("IVSDK configured — partner \(AppConfig.partnerId), region \(region.rawValue), env \(AppEnvironment.environment.rawValue)")
    }

    /// Critical alerts pierce silent mode and Focus. iOS only grants them to
    /// entitled apps, and only asks once, so this is requested when it is
    /// actually warranted rather than at launch.
    func registerForCriticalRemoteNotifications(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, _ in
                DispatchQueue.main.async {
                    if granted { UIApplication.shared.registerForRemoteNotifications() }
                    completion(granted)
                }
            }
    }

    private func registerForRemoteNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        apnsToken = token
        // APNs hands the token to the app, but the backend still has to be told
        // about it or nothing is ever delivered. That registration needs an
        // authenticated session, so it is published here and performed once the
        // signed-in shell is up.
        NotificationCenter.default.post(name: .apnsTokenReceived, object: nil, userInfo: ["token": token])
        Logger.debugLog("APNS token received")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Almost always a provisioning problem rather than a runtime one: no
        // aps-environment entitlement, or an App ID without the Push
        // Notifications capability. Nothing downstream can work without a
        // token, so say so plainly.
        Logger.debugLog("APNS registration FAILED — no push token will be issued:",
                        error.localizedDescription)
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientation
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Cameras hold a single session slot open; dropping it on the way out
        // stops the next launch finding the camera busy.
        LiveViewObjectStore.disconnectOnAppTermination()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
