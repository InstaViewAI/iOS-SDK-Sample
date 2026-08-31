# Sandbox

Sample iOS app for the InstaView home-security SDK: sign-in, spaces, cameras,
events, live view, camera pairing and professional monitoring.

This file covers **getting it running**. For how it is put together and why, see
[ARCHITECTURE.md](ARCHITECTURE.md).

---

## Before you start

| Requirement | Notes |
| --- | --- |
| Xcode 15 or later | |
| CocoaPods | `sudo gem install cocoapods` |
| A **physical iPhone** | the SDK ships `arm64` only  |
| Apple Developer team with this App ID | needed for signing and push |

---

## 1. Install the pods

```sh
cd iOS-SDK-Sample
pod install
```

This fetches five dependencies:

- `IVSDK` — the home-security SDK, over HTTPS from
  `https://github.com/InstaViewAI/IVSDK-iOS` (tag `3.0.1`)
- `Firebase`, `FirebaseAuth`, `GoogleSignIn` — back the SDK's email, Google and
  Apple sign-in
- `IJKMediaFrameworkWithSSL` — FFmpeg-based player for playing events          

Everything except `IVSDK` comes from CocoaPods trunk; `IVSDK` is pinned to a
git tag.

---

## 2. Get a `GoogleService-Info.plist`

Firebase backs sign-in, so the app cannot start without this file. It is
**gitignored** (`**/GoogleService-Info.plist`), so a fresh clone will not have
one — you have to be given it.

Provide a bundle identifier to Instavision team and get a `GoogleService-Info.plist` registered to this bundle identifier.
The file must match that identifier exactly. A plist issued for a different bundle id will let the app launch and then fail every sign-in attempt, which is
an unhelpful way to find out.

### Put it in place

Add the file at:

```
Sandbox/Resources/GoogleService-Info.plist
```

Keep the same path and filename — the project references it there.

### Copy the client id across

Google sign-in returns to the app through a custom URL scheme, which lives in
the build configuration rather than the plist. Read the REVERSED_CLIENT_ID value out of your new plist file and replacee in below files

- `Sandbox/Config/Debug.xcconfig`
- `Sandbox/Config/Release.xcconfig`

```
REVERSED_CLIENT_ID = com.googleusercontent.apps.<your value>
```

Miss this and Google sign-in opens Safari and never comes back.

---

## 3. Signing

Open `Sandbox.xcworkspace`, select the **Sandbox** target → *Signing &
Capabilities*, and choose your team.

The bundle identifier is set from the xcconfigs, replace your bundle identifier in below files
- Sandbox/Config/Debug.xcconfig
- `Sandbox/Config/Release.xcconfig`

```
PRODUCT_BUNDLE_IDENTIFIER = <your value>
```

**The App ID needs the Push Notifications capability enabled**, because the
target ships an entitlements file requesting `aps-environment`
(`Sandbox.entitlements` for Debug, `SandboxRelease.entitlements` for Release).
Without it the build fails at code signing with a missing-entitlement error.

Critical alerts — notifications that sound through silent mode — additionally
need `com.apple.developer.usernotifications.critical-alerts`, which Apple grants
per App ID on request. That key is deliberately **not** in the entitlements
file, so nothing breaks without it; the feature simply degrades to normal
notifications.

---

## 4. Build and run

1. Open **`Sandbox.xcworkspace`** — not `Sandbox.xcodeproj`. The pods are only
   wired up in the workspace.
2. Select the **Sandbox** scheme.
3. Select a connected iPhone as the destination.
4. Run.

--

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Unable to resolve module dependency: 'IVSDK'` after a `clean` | CocoaPods integration was lost — run `pod install` again |
| Code signing fails on a missing entitlement | Push Notifications is not enabled on the App ID |
| Every sign-in fails | `GoogleService-Info.plist` does not match `ai.instaview.guardian.sandbox` |
| Google sign-in never returns from Safari | `REVERSED_CLIENT_ID` not copied into both xcconfigs |
| Crash on launch in `FirebaseApp.configure()` | no `GoogleService-Info.plist` in `Sandbox/Resources/` |

