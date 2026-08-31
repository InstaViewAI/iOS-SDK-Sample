//
//  FourGScreens.swift
//  Sandbox
//
//  The cellular branch of pairing. Reached automatically: scanning the code on
//  the camera resolves its model, and a model declaring 4G properties comes
//  here instead of to Wi-Fi credentials.
//
//  There are no network credentials to collect — the SIM provides connectivity.
//  Fit it, register it if it is not already, then power-cycle and wait for the
//  camera to call home against the pairing session.
//

import SwiftUI
import Combine
import IVSDK

// MARK: - Insert SIM

struct InsertSimCardScreen: View {
    /// Resolved from the code on the camera. The cellular pairing session is
    /// opened against it.
    let deviceId: String
    let screenFrom: ScreenFrom
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        PairingStepScreen(
            step: 3,
            total: 5,
            title: "Insert the SIM card",
            subtitle: "This is a cellular camera, so it connects over the mobile network rather than Wi-Fi.",
            bullets: [
                "Open the camera's battery or SIM hatch.",
                "Slide the SIM in with the gold contacts facing the camera body, notch first.",
                "Close the hatch firmly — a loose cover will stop the camera weatherproofing."
            ],
            primaryTitle: "SIM is fitted",
            secondaryTitle: "My SIM needs registering",
            onPrimary: {
                pilot.push(.reset4gCamera(deviceId: deviceId, screenFrom: screenFrom))
            },
            onSecondary: {
                pilot.push(.simNumber(code: "", deviceId: deviceId, screenFrom: screenFrom))
            },
            illustration: { PairingIllustration(systemName: "simcard") },
            screenFrom: screenFrom
        )
    }
}

// MARK: - Restart and wait

/// The camera already knows how to reach the service through its SIM, so this
/// step only opens a pairing session and waits for it to call home.
///
/// A cellular session is not the same shape as a Wi-Fi one. There is no code
/// for the camera to read, so the backend cannot learn which device the session
/// belongs to from the handshake — it has to be told up front, which is what
/// `SessionType.fourG(deviceId:)` is for. Opening it as `.other` would leave a
/// session no camera can ever claim.
final class Reset4GCameraViewModel: PairingSessionViewModel {
    @Published var sessionReady = false

    private let deviceId: String

    init(deviceId: String, sharedData: SharedDataStore) {
        self.deviceId = deviceId
        super.init(sharedData: sharedData)
        // Device polling can start against a known id rather than waiting for
        // the session status to report one.
        self.pairedDeviceId = deviceId
    }

    func beginSession() {
        createSessionKey(sessionType: .fourG(deviceId: deviceId)) { [weak self] _ in
            self?.sessionReady = true
        }
    }
}

struct Reset4GCameraScreen: View {
    let deviceId: String
    let screenFrom: ScreenFrom
    @StateObject private var viewModel: Reset4GCameraViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    init(deviceId: String, screenFrom: ScreenFrom, sharedData: SharedDataStore) {
        self.deviceId = deviceId
        self.screenFrom = screenFrom
        _viewModel = StateObject(wrappedValue: Reset4GCameraViewModel(deviceId: deviceId,
                                                                      sharedData: sharedData))
    }

    var body: some View {
        BaseView(content: {
            PairingStepScreen(
                step: 4,
                total: 5,
                title: "Power on and connect",
                subtitle: "A cellular camera does not go online by itself — a double tap on the reset button is what tells it to connect.",
                bullets: [
                    "Switch the camera off, wait five seconds, then switch it back on.",
                    "Once it has finished starting up, double-tap the reset button.",
                    "Leave it outdoors or near a window while it connects."
                ],
                primaryTitle: "I double-tapped reset",
                secondaryTitle: "It is not connecting",
                onPrimary: {
                    viewModel.beginSession()
                },
                onSecondary: {
                    pilot.push(.troubleshootCamera(screenFrom: screenFrom))
                },
                illustration: { PairingIllustration(systemName: "hand.tap.fill") },
                screenFrom: screenFrom
            )
        }, result: $viewModel.result)
        .onChange(of: viewModel.sessionReady) { ready in
            guard ready, let sessionKey = viewModel.sessionKeyModel?.sessionKey else { return }
            pilot.push(.retrievePairingStatus(sessionKey: sessionKey,
                                              deviceId: deviceId,
                                              screenFrom: screenFrom))
        }
    }
}

// MARK: - Register a SIM

/// A recovery path, not part of the main flow: SIMs shipped with a camera are
/// already provisioned, and only a replacement or a failed activation needs
/// `bootstrapSim`.
final class SimNumberViewModel: PairingSessionViewModel {

    @Published var iccid: String
    @Published var bootstrapped = false

    let deviceId: String
    private var bootstrapCancellable: AnyCancellable?

    init(sharedData: SharedDataStore, code: String, deviceId: String) {
        self.iccid = code.filter(\.isNumber)
        self.deviceId = deviceId
        super.init(sharedData: sharedData)
    }

    /// ICCIDs are 19 or 20 digits.
    var canSubmit: Bool {
        let digits = iccid.filter(\.isNumber)
        return digits.count >= 18 && digits.count <= 20
    }

    func bootstrap() {
        result.update(data: .loading)
        bootstrapCancellable = spaceService
            .bootstrapSim(spaceId: spaceId, request: .init(simNumber: iccid.filter(\.isNumber)))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.result.update(data: .success)
                    self?.bootstrapped = true
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}

struct SimNumberScreen: View {
    @StateObject var viewModel: SimNumberViewModel
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @State private var showQuitConfirm = false

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    PairingNavBar(screenFrom: screenFrom, showQuitConfirm: $showQuitConfirm)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            StepHeader(step: 3, total: 5,
                                       title: "Register the SIM",
                                       subtitle: "Only needed for a replacement SIM, or one that never activated. The ICCID is the long number printed on the SIM holder.")

                            AppTextField(placeholder: "ICCID",
                                         text: $viewModel.iccid,
                                         keyboard: .numberPad)

                            InfoNote(text: "Registration can take a minute. Leave the camera powered on and within cellular coverage.")
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }

                    PrimaryButton(title: "Register SIM", enabled: viewModel.canSubmit) {
                        viewModel.bootstrap()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }, result: $viewModel.result)
        .onChange(of: viewModel.bootstrapped) { done in
            guard done else { return }
            pilot.pop(andPush: .reset4gCamera(deviceId: viewModel.deviceId, screenFrom: screenFrom))
        }
        .overlay {
            if showQuitConfirm {
                AppAlertView(shown: $showQuitConfirm,
                             title: "Stop setting up?",
                             okTitle: "Stop setup",
                             cancelTitle: "Keep going",
                             onOk: { pilot.quitPairing(screenFrom: screenFrom) })
            }
        }
    }
}
