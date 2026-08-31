# Sandbox — architecture

How the app is built and why it is built that way. For getting it running, see
[README.md](README.md).

A slim, working sample app on the same architecture as the Guardian iOS app.
One target, one partner, one purpose: show the whole path from a cold install to
a configured camera.

```
Onboarding → Sign in / Sign up → Email verification gate
   → Space (create one if the account owns none)
   → Home (devices) + Events → Event player
   → Camera pairing (Wi-Fi QR · BLE · 4G/SIM · doorbell)
   → Live view (watch, listen, talk, snapshot, record)
   → Camera settings
   → Professional monitoring (8-step setup, arm/disarm, settings)
```

## How it is put together

| Layer | Where | What it does |
| --- | --- | --- |
| Entry | `SandboxApp.swift`, `Core/AppDelegate.swift` | Configures Firebase and `InstaSDK`, registers for push |
| Navigation | `Core/Destination.swift`, `Core/Pilot.swift`, `ContentView.swift` | Every screen is one enum case; `ContentView` is the only place a case becomes a view |
| State | `Stores/` | `SharedDataStore` (current space, devices, clusters), `SpaceDataStore`, `EventsDataStore` |
| Screens | `Screens/` | A `View` plus an `ObservableObject` view model per screen |
| Theme | `Theme/` | Palette, type scale, and the controls every screen is built from |

### Navigation

SwiftUI's `NavigationStack` cannot express "pop three screens and push one" as
a single animation, which the pairing flow needs constantly. `UIPilot` keeps the
route stack as a plain array and mirrors it into a `UINavigationController`, so
`popTo(_:inclusive:andPush:)` is one call and one animation.

Routes are compared by a `key` string rather than by their payloads. That lets a
case carry a `DeviceModel` or a `SpaceModel` — neither of which is `Equatable`
in a useful way — while the enum stays `Equatable` for `popTo`.

### The onboarding gate

Three checks decide where a signed-in user lands, and every sign-in path runs
all three:

1. **Email verified?** If not → `EmailVerifyScreen`, which polls `getUser()`
   every three seconds until the flag flips. Verification happens off-device in
   a mail client, so polling is the only way to notice.
2. **Owns a space?** If not → `SpaceScreen`. A space is the container devices
   and events hang off; an account without one has no home screen to show.
3. Otherwise → the tab bar.

`isLoggedIn` is only set once all three pass, so a half-finished signup resumes
at onboarding rather than a blank home screen.

### Pairing

Pairing is a three-way handshake, and the app never talks to the camera
directly:

1. The app asks the backend for a short-lived **session key** (three minutes).
2. The key, plus Wi-Fi credentials, reaches the camera — either as a QR code it
   reads with its own lens, or written over BLE.
3. The camera calls home with that key, which is what binds it to this account.

Because there is no channel back from the camera, every stage is discovered by
polling `getPairingSessionStatus`. `PairingSessionViewModel` owns that loop; the
individual screens only decide what to show while it runs.

**The user is never asked what kind of camera they have.** They would often not
know, so the flow discovers it instead. One path in — power on, then let the app
look for the camera over BLE. If nothing is found, "Set up with a QR code"
switches to scanning the code printed on the camera body. That code encodes the
device id, `deviceModelInfo` resolves it into the model's published features,
and a model declaring `fourGProps.enabled` branches into SIM setup while
everything else goes to Wi-Fi credentials.

Note that scan runs the opposite way to the handshake later on: here the *phone*
reads a code on the camera; later the phone *displays* one for the camera's own
lens.

From there:

- **BLE** — pick the camera, ask *it* to scan for Wi-Fi, push credentials over
  the link. The network list comes from the camera because what it can see and
  what the phone can see are often different.
- **Wi-Fi over QR** — enter credentials, show the code, hold it up to the lens.
- **Cellular** — fit the SIM, power-cycle, double-tap reset to bring it online,
  then wait for it to call home. Registering a SIM by hand (`bootstrapSim`) is a
  recovery path off the insert-SIM screen, since SIMs shipped with a camera are
  already provisioned.

  A cellular session is **not the same shape** as a Wi-Fi one. There is no code
  for the camera to read, so the backend cannot learn which device a session
  belongs to from the handshake — it has to be told up front, which is what
  `SessionType.fourG(deviceId:)` is for. That device id is the one resolved by
  the scan, and it is carried through the whole cellular branch for exactly this
  reason. Opening the session as `.other` leaves one no camera can ever claim.

### Push notifications

Getting a token from APNs is only half of it — the backend has to be told about
it or nothing is ever delivered, and that registration needs an authenticated
session. So the token is published from the app delegate and registered from the
home screen, once the signed-in shell is up:

```
didRegisterForRemoteNotifications → .apnsTokenReceived → SharedDataStore.apnsToken
                                                       → HomeViewModel
                                                       → updatePushNotificationToken(token:provider:.apns)
                                                       → saveAPNSToken (only after the backend accepts)
```

`@Published` replays its current value on subscribe, so a token that arrived
before the home screen existed is still picked up. The last registered token is
remembered so a redraw does not re-send it.

**Critical alerts** — the ones that sound through silent mode and Focus — are a
separate permission, requested only when the current space has a professional
monitoring plan. That is the case where a missed notification matters enough to
justify breaking through, and iOS only ever presents the prompt once, so
spending it at launch would waste it.

> **This needs an Apple entitlement.** Critical alerts require
> `com.apple.developer.usernotifications.critical-alerts`, which Apple grants
> per app ID on request. The sample deliberately ships no `.entitlements` file:
> adding the key without the matching provisioning profile fails code signing.
> Until the entitlement is granted the request simply will not be honoured, and
> alerts fall back to normal notification behaviour.

Push *handling* — routing a tapped notification to the camera or event it refers
to — is not implemented here; see Known gaps.

### Professional monitoring

The **Security** tab has three states, and which one shows is decided entirely
by what the backend says — not by local flags:

- **No subscription.** `getProfile` answers "not subscribed", which is an
  ordinary state for a space that never bought monitoring, so the store records
  it as `notSubscribed` rather than surfacing an error. The tab shows an upsell.
- **Subscribed, setup unfinished.** The tab offers to resume the ladder.
- **Running.** Arm, disarm, per-camera state, and the security log.

**The setup ladder** is eight steps, stored server-side as `setupStep`:

| Step | What it collects | Skippable |
| --- | --- | --- |
| Contact information | Address, verified phone, alarm permit | No |
| Camera setup | Which cameras, and the dismissal window | No |
| Arm settings | Exit delay | No |
| Disarm settings | Disarm methods, safe word | No |
| Schedule | Repeating arm/disarm entries | Yes |
| Test the system | Critical alerts, a live test run | Yes |
| Invite household | The agent's call list | Yes |

`SecuritySetupStep`'s raw values are a contract with the backend, not a local
convenience. Progress lives on the server, so setup can be abandoned on one
device and resumed on another — and the hub reads where things stand rather
than tracking it locally. Steps unlock in order, because a profile with a safe
word but no address is one a dispatcher cannot act on.

Every step writes through `SecurityStepViewModel.submit(_:completingStep:)`,
which picks `setupProfile` during onboarding and `updateProfile` when the same
screen is reached from settings — so editing your address later never rewinds
the ladder.

Which endpoint a save uses depends on where the screen was opened from, because
the backend treats first-run setup and later editing as different operations:

| Situation | Call | Advances the ladder? |
| --- | --- | --- |
| No profile loaded | `createProfile` | no — carries the data, then the record is re-read |
| Onboarding | `setupProfile` | yes — data and `setupStep` in one request |
| Settings | `updateProfile` (PATCH) | no |

Creating is gated on **nothing being loaded** (`profile == nil`), not on
`ProMonitoringModel.profileCreated` — that flag can be false or absent on a
profile that genuinely exists, and keying off it makes the app POST forever and
strand the user on the first screen.

`createProfile` already carries the address and timezone, so no further write
follows it; the profile is re-read with `getProfile` instead.

Several screens make up one ladder step — address, phone and permit are all
*Contact information* — so only the last of them passes a `completingStep`; the
rest save without advancing. The optional steps at the end collect nothing of
their own, and call `completeStep(_:)` to advance without a pointless save.
Editing from settings never advances anything, so correcting an address cannot
rewind a finished profile.

Loading a profile that does not exist yet fails with the API code
`SecurityProfile_NotFound`. That is suppressed rather than surfaced: it is the
setup flow's cue, not an error. Whether a space is subscribed at all is decided
by `SpaceModel.hasProMonitoringPlan()`, never by inspecting how `getProfile`
failed.

**Arming** is a slide, not a tap: `SlideToConfirm` requires a deliberate drag
in both directions, and anything short of the far end springs back. Before
arming, the dashboard refuses if every enrolled camera is offline and warns if
one is below 20% battery — arming a system that cannot see is worse than not
arming, because the user believes they are protected. Arm and disarm are not
instant, so the store polls `getProfile` until the status leaves `arming` or
`disarming`.

**When an alarm fires**, `AlarmTriggeringScreen` counts down the dismissal
window. Until it expires this is entirely the user's call and cancelling means
the monitoring centre is never told. After it expires an agent reviews the clip,
calls, and asks for the safe word before anything else can happen. Test mode
runs that whole chain with the centre standing down, and switches itself off
when the step completes so a forgotten toggle cannot silently neuter the real
system.

### Event player

Tap an event — in the Events tab or the recent-activity strip on Home — to play
it back.

Clips are not publicly readable. Each lives in a per-device storage bucket and
needs a short-lived token appended to its URL as an `Authorization` query
parameter. `B2TokenStore` fetches those for the whole space at once, keyed by
device and bucket, and caches them for just under their 24-hour life — an event
list holds dozens of clips from the same camera, so a token fetch per row would
be wasteful. Concurrent callers share one in-flight request.

**Clips are HLS, and that has a sharp edge.** The playlist can be fetched with
the token in its query string, but the segment URIs inside it are relative — so
the player requests them unsigned and the bucket answers 401, surfacing as
`NSURLErrorUserAuthenticationRequired` (-1013). The playlist has to be fetched,
every media URI rewritten to a signed absolute URL, and the result handed to the
player as a local `.m3u8` file. `#EXT-X-ENDLIST` is appended when missing, or
the player treats a finished recording as a live stream: no duration, no
seeking. The production app does the same thing for the same reason.

**Playback uses IJKPlayer, not AVPlayer, and it has to.** These cameras record
**HEVC inside MPEG-TS** segments. Apple's HLS spec requires HEVC to be carried
in fMP4, so AVFoundation cannot decode that combination — and it does not report
an error, it just stalls, which on screen is a spinner that never resolves. The
production app reached the same conclusion, which is why it ships FFmpeg.

It comes from CocoaPods — `pod 'IJKMediaFrameworkWithSSL', '~> 0.0.3'` — rather
than a checked-in binary, so there is nothing to vendor. The build is
self-contained (its own FFmpeg statically linked, only system frameworks
otherwise), so none of the `libav*` companions in the Guardian repo are needed.
It is arm64-only, the same constraint IVSDK already imposes. Hardware decode is
enabled via the `videotoolbox` player option; FFmpeg still demuxes the TS
container, which is the part AVFoundation cannot do.

Two things to know before taking this to production: the pod is a **community
build** (`fionaly89/IJKMediaFrameworkWithSSL`), not an official bilibili
release, and its three published versions all point at the same git tag. The
Guardian repo carries its own vetted `IJKMediaFrameworkWithSSL.xcframework` in
`libs/`; swapping the pod line for a local podspec pointing at that is a
one-line change if you would rather ship a binary you control. The pod's build
was checked for what matters here — HEVC decoder present, SSL present, FFmpeg
self-contained — before being adopted.

Saving is limited by the same shape. A plain file is downloaded and handed to
Photos; an HLS clip cannot be, because it is a playlist plus hundreds of
segments and Photos wants one movie. Remuxing needs an FFmpeg command pipeline
— what the production app uses `EventDownloader` for — so the sample saves the
snapshot instead and says so, rather than writing a broken file.

Not every event has video: snapshot events carry only a still, so "nothing to
play" is a normal state rather than an error, and the snapshot doubles as the
poster frame while a clip loads. The player also offers scrubbing, ±10s skip,
mute, save to photos, delete, and up/down navigation through the same list the
events screen is showing.

Playback sets the audio session to `.playback`, so a clip is audible with the
ring switch on silent — the user deliberately opened it, unlike an incidental
sound — and hands the session back on teardown so other audio can resume.

**Accuracy feedback** (`setEventFeedback`) is surfaced rather than buried: it is
what trains the per-space detection model.

### Live view

Tap any camera tile on the home screen — or an enrolled camera on the security
dashboard — to watch it. The SDK does the hard part: `LiveViewModel` negotiates
a WebRTC session with the camera and hands back `IVVideoView`s to render into.
`CameraLiveViewModel` wraps that with the screen's concerns and turns the SDK's
callback surface into published state.

Connections are **shared, not owned**. `LiveViewObjectStore.objectFor(...)`
returns the same object for a given camera, so opening live view twice reuses
one stream rather than two screens fighting over the camera's single session
slot. That is also why the session is torn down deliberately: on logout
(`LiveViewObjectStore.logout()`), on app termination
(`disconnectOnAppTermination()`), and when the app is backgrounded — otherwise
the camera keeps a slot open for a viewer that has gone away.

The screen offers listen, push-to-talk (the mic is open only while held),
snapshot and recording — both saved to the photo library after an explicit
permission check, since a denied library grant otherwise fails silently — and,
on pan-tilt models, a PTZ pad gated on the `ptz` cluster. Controls fade after
four seconds so they are not sitting on top of the footage.

Audio always starts **muted**: opening a camera should never suddenly make noise
in a quiet room. The speaker and the mic are independent — holding the talk
button does not switch the speaker on, so talking never unexpectedly starts
playing camera audio out loud.

One wrinkle worth knowing if you extend recording: `stopRecording` hands back a
file **URL string** (`file:///private/var/...`), not a bare path. Passing it to
`URL(fileURLWithPath:)` produces `/file:///private/var/...` — a path that does
not exist — and Photos rejects it with "Unable to issue sandbox extension".
`fileURL(from:)` accepts either form, and the temporary clip is deleted once it
is safely in the library.

Live view is also the one screen that rotates. `AppDelegate.orientation` is
`.portrait` for the whole app and is set to `.all` only while this screen is on
screen.

Before connecting, the model checks whether the camera can stream at all —
unactivated, offline, in privacy mode, or awaiting a required firmware update
each produce a specific explanation rather than a spinner that never resolves.

### Camera settings

Cameras come in two generations and the app speaks to both. Which one is decided
per device by `DeviceModel.clusterGroupVersion`:

| `clusterGroupVersion` | API | Shape |
| --- | --- | --- |
| `v0`, or absent | `getDeviceSettings` / `updateDeviceSettings` | One fixed `DeviceSettingModel` |
| anything else | `getDeviceClusters` / `updateDeviceClustersAttribute` | A self-describing document of typed attributes |

Screens do not branch on that. `DeviceSettingsViewModel` presents a single
vocabulary — `SettingsFeature` — and every accessor dispatches to whichever API
the camera in hand actually speaks:

```swift
if viewModel.supports(.nightVision) {
    SettingOptionPicker(title: "Night vision",
                        options: viewModel.options(.nightVision),
                        selected: viewModel.string(.nightVision)) {
        viewModel.setString(.nightVision, $0)
    }
}
```

Adding a settings screen means asking `supports(_:)` and binding a value. The
generation split lives in one file.

**Capability** is answered differently by each side. A cluster device is asked:
if it does not report an `sdCardSettings` cluster, there is no storage row. A
legacy device has no such document, so support is inferred from the settings
object it returns — `SettingsFeature.existsOnLegacy` marks which fields the
legacy model carries at all, and the three optional ones (`hdrEnabled`,
`alwaysOn`, `eventDuration`) additionally have to come back non-nil. Controls
that only exist on newer hardware — the manual spotlight, floodlight modes, the
night lamp — are simply absent on legacy cameras.

**Enum options** come from the camera on cluster devices, labels included, so
night-vision modes and sensitivity levels are never hardcoded. Legacy firmware
does not describe itself, so a fixed list stands in. Both arrive at the UI as
`[SettingOption]`.

**Writes** differ in shape and the façade hides that too. Cluster writes are
optimistic — the local copy updates first so the control responds immediately,
then reconciles against what the camera stored, or rolls back on failure. Legacy
writes send a sparse `UpdateDeviceSettingRequestModel` carrying only the changed
field, and the endpoint returns the whole settings object, which becomes the new
truth. Battery cameras get `wakeup: true` on both paths — they are asleep
between events and cannot be written to otherwise.

Detection AI and notifications stay on their own cloud endpoints in both
generations, because they are evaluated server-side on the uploaded clip rather
than on the camera.

## Known gaps

This is a sample, not a shipping app. Deliberately left out: deep-linking from a
tapped push notification to the camera or event it refers to, subscriptions and
paywalls, pet/baby profiles,
drawable activity zones, NVR security variants, localisation (English only), and
local persistence — the reference app caches to Realm, this one keeps everything
in memory and refetches.

## Regenerating the project file

If `Sandbox.xcodeproj/project.pbxproj` is ever rewritten from scratch, **run
`pod install` again straight afterwards.** CocoaPods' integration — the
`[CP]` script phases and the linked frameworks — lives inside that file, and a
regenerated project drops it. The build keeps working until the next `clean`,
then fails with `Unable to resolve module dependency: 'IVSDK'`.

## Simulator

The SDK's xcframework ships an **`ios-arm64` slice only** — there is no
simulator build. `Sandbox` therefore compiles and runs on a physical device;
an iOS Simulator build fails at `Unable to resolve module dependency: 'IVSDK'`.
Camera pairing needs real hardware (Bluetooth, the camera, the Wi-Fi network)
in any case.
