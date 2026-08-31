//
//  ScanCameraCodeScreen.swift
//  Sandbox
//
//  The single entry into QR-based pairing, for either kind of camera.
//
//  The user is never asked whether they have a Wi-Fi or a cellular camera —
//  they would often not know, and the label on the box is not always right.
//  Instead the code printed on the camera body encodes its device id, which
//  `deviceModelInfo` resolves into the model's capabilities. If that model
//  declares 4G properties the flow continues into SIM setup; otherwise it goes
//  to Wi-Fi credentials.
//
//  Note this scan runs the opposite way to the handshake later in the flow:
//  here the phone reads a code on the camera, rather than displaying one for
//  the camera's own lens.
//

import SwiftUI
import Combine
import IVSDK

extension DeviceModelInfo {
    /// Cellular models declare this in their published feature set.
    var is4GCamera: Bool {
        modelDetails?.properties?.fourGProps?.enabled ?? false
    }
}

final class ScanCameraCodeViewModel: PairingSessionViewModel {

    enum Outcome: Equatable {
        case fourG(deviceId: String)
        case wifi(deviceId: String)
    }

    @Published var outcome: Outcome?
    @Published var lookupFailed = false

    private var modelCancellable: AnyCancellable?
    /// The scanner keeps firing while a code is in frame; one lookup is enough.
    private var isResolving = false

    /// The label may encode a bare device id or a URL carrying one, so take the
    /// last path component and drop any query.
    static func deviceId(from scanned: String) -> String? {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains("://") || trimmed.contains("/") else { return trimmed }
        return URL(string: trimmed)?.deletingPathExtension().lastPathComponent
            ?? trimmed.components(separatedBy: "/").last
    }

    func resolve(scanned: String) {
        guard !isResolving else { return }
        guard let deviceId = Self.deviceId(from: scanned), !deviceId.isEmpty else {
            lookupFailed = true
            return
        }
        isResolving = true
        result.update(data: .loading)

        modelCancellable = Factory.deviceService
            .deviceModelInfo(spaceId: spaceId, deviceId: deviceId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(info):
                    self.result.update(data: .success)
                    self.outcome = info.is4GCamera
                        ? .fourG(deviceId: info.did)
                        : .wifi(deviceId: info.did)
                case .error:
                    // An unrecognised code is far more likely than a broken
                    // backend, so this reads as a scan problem.
                    self.result.update(data: .success)
                    self.isResolving = false
                    self.lookupFailed = true
                @unknown default:
                    break
                }
            }
    }

    func reset() {
        isResolving = false
        lookupFailed = false
        outcome = nil
    }
}

struct ScanCameraCodeScreen: View {
    @StateObject var viewModel: ScanCameraCodeViewModel
    let screenFrom: ScreenFrom

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @State private var showQuitConfirm = false

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    PairingNavBar(screenFrom: screenFrom, showQuitConfirm: $showQuitConfirm)

                    VStack(alignment: .leading, spacing: 16) {
                        StepHeader(step: 2, total: 5,
                                   title: "Scan the code on your camera",
                                   subtitle: "There is a QR code on the camera body, usually under the battery hatch or on the back label.")
                            .padding(.horizontal, 24)

                        ZStack {
                            QRCodeScannerView { code in
                                viewModel.resolve(scanned: code)
                            }
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(AppColors.primary, lineWidth: 3)
                                .frame(width: 230, height: 230)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 340)
                        .cornerRadius(20)
                        .padding(.horizontal, 24)

                        InfoNote(text: "This tells us which camera you have, so the rest of setup matches it.")
                            .padding(.horizontal, 24)

                        Spacer()
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.reset() }
        .onChange(of: viewModel.outcome) { outcome in
            guard let outcome else { return }
            switch outcome {
            case let .fourG(deviceId):
                // The cellular pairing session is opened against this device
                // id, so it has to travel with the rest of the flow.
                pilot.pop(andPush: .insertSimCard(deviceId: deviceId, screenFrom: screenFrom))
            case .wifi:
                pilot.pop(andPush: .selectWiFi(mode: .qrCode, ssid: nil, screenFrom: screenFrom))
            }
        }
        .overlay {
            if viewModel.lookupFailed {
                AppAlertView(shown: $viewModel.lookupFailed,
                             title: "Could not read that code",
                             message: "Make sure you are scanning the QR code on the camera body, and that the label is clean and well lit.",
                             okTitle: "Try again",
                             onOk: { viewModel.reset() })
            }
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
