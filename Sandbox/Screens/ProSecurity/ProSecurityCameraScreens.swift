//
//  ProSecurityCameraScreens.swift
//  Sandbox
//
//  Step 2: which cameras take part, and how they behave once armed.
//
//  Enrolling a camera changes what its motion events mean. Outside the
//  security system a detection is a notification; inside it, a detection on an
//  armed camera starts a countdown that ends with a dispatcher on the phone.
//  The intro pages exist because that difference has to be understood before
//  it is switched on.
//

import SwiftUI
import Combine
import IVSDK

// MARK: - How it works

struct SecurityCameraIntroScreen: View {
    let page: Int
    let screenFrom: ScreenFrom
    @EnvironmentObject private var pilot: UIPilot<Destination>

    private struct IntroPage {
        let icon: String
        let title: String
        let body: String
        let tint: Color
    }

    private static let pages: [IntroPage] = [
        IntroPage(icon: "video.badge.checkmark",
                  title: "Your cameras become sensors",
                  body: "Cameras you add here keep working normally. The difference is that when the system is armed, what they see can raise an alarm.",
                  tint: AppColors.primary),
        IntroPage(icon: "timer",
                  title: "You get a chance to cancel",
                  body: "A detection starts a countdown. Disarm from the app during that window and nothing else happens — the monitoring centre is never told.",
                  tint: AppColors.warning),
        IntroPage(icon: "phone.badge.waveform",
                  title: "Then an agent steps in",
                  body: "If the countdown runs out, an agent reviews the clip, calls you, and asks for your safe word. Only then can they dispatch help.",
                  tint: AppColors.error)
    ]

    private var current: IntroPage { Self.pages[min(max(page, 1), Self.pages.count) - 1] }
    private var isLast: Bool { page >= Self.pages.count }

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                NavBar(title: SecuritySetupStep.cameraSetup.title) { pilot.pop() }

                Spacer()

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(current.tint.opacity(0.14))
                            .frame(width: 132, height: 132)
                        Image(systemName: current.icon)
                            .font(.system(size: 52, weight: .light))
                            .foregroundColor(current.tint)
                    }

                    VStack(spacing: 12) {
                        Text(current.title)
                            .font(AppFont.title(26))
                            .foregroundColor(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(current.body)
                            .font(AppFont.body(15))
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 28)

                    HStack(spacing: 7) {
                        ForEach(1...Self.pages.count, id: \.self) { index in
                            Capsule()
                                .fill(index == page ? AppColors.primary : AppColors.border)
                                .frame(width: index == page ? 20 : 7, height: 7)
                        }
                    }
                }

                Spacer()

                PrimaryButton(title: isLast ? "Choose cameras" : "Next") {
                    if isLast {
                        pilot.push(.securityCameraSelection(screenFrom: screenFrom))
                    } else {
                        pilot.push(.securityCameraIntro(page: page + 1, screenFrom: screenFrom))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Camera selection

final class SecurityCameraSelectionViewModel: SecurityStepViewModel {
    @Published var selectedIds: Set<String> = []
    @Published var devicesLoaded = false

    private var deviceCancellable: AnyCancellable?
    private var updateCancellable: AnyCancellable?

    var devices: [DeviceModel] { store.armableDevices }

    var canSubmit: Bool { !selectedIds.isEmpty }

    func load() {
        selectedIds = Set(profile?.securedDeviceIds ?? [])
        result.update(data: .loading)
        deviceCancellable = store.sharedDataDevices()
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.devicesLoaded = true
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.devicesLoaded = true
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    func toggle(_ device: DeviceModel) {
        if selectedIds.contains(device.id) {
            selectedIds.remove(device.id)
        } else {
            selectedIds.insert(device.id)
        }
    }

    func selectAll() { selectedIds = Set(devices.map(\.id)) }
    func clearAll() { selectedIds = [] }

    /// A camera that is offline right now can still be enrolled — it will arm
    /// when it comes back. Only an unactivated camera is genuinely unusable.
    func warning(for device: DeviceModel) -> String? {
        if !device.isOnline { return "Offline — it will arm when it reconnects" }
        if device.isBatteryPowered, let battery = device.deviceState.batteryPercentage, battery < 20 {
            return "Battery low — may fail to arm"
        }
        return nil
    }

    func save() {
        result.update(data: .loading)
        updateCancellable = store.updateDevices(ids: Array(selectedIds))
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.result.update(data: .success)
                    self?.advanced = true
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}

struct SecurityCameraSelectionScreen: View {
    @StateObject var viewModel: SecurityCameraSelectionViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .cameraSetup,
                title: "Which cameras?",
                subtitle: "Pick the cameras that should raise an alarm while the system is armed.",
                primaryTitle: "Save selection",
                primaryEnabled: viewModel.canSubmit,
                onPrimary: { viewModel.save() }
            ) {
                if viewModel.devices.isEmpty && viewModel.devicesLoaded {
                    EmptyStateView(icon: "video.slash",
                                   title: "No cameras to add",
                                   message: "Set up at least one camera before turning on professional monitoring.")
                } else {
                    HStack {
                        Text("\(viewModel.selectedIds.count) of \(viewModel.devices.count) selected")
                            .font(AppFont.caption(12))
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        LinkButton(title: viewModel.selectedIds.count == viewModel.devices.count
                                   ? "Clear all" : "Select all") {
                            viewModel.selectedIds.count == viewModel.devices.count
                                ? viewModel.clearAll() : viewModel.selectAll()
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(viewModel.devices, id: \.id) { device in
                            cameraRow(device)
                        }
                    }

                    InfoNote(text: "Indoor cameras are usually left out of an all-armed system so you can move around at home without tripping it.")
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
        .onChange(of: viewModel.advanced) { advanced in
            guard advanced else { return }
            pilot.push(.securityZoneSettings(screenFrom: viewModel.screenFrom))
        }
    }

    private func cameraRow(_ device: DeviceModel) -> some View {
        let selected = viewModel.selectedIds.contains(device.id)
        return Button {
            viewModel.toggle(device)
        } label: {
            HStack(spacing: 12) {
                RemoteImage(url: device.snapshotURL)
                    .frame(width: 56, height: 42)
                    .cornerRadius(8)
                    .opacity(device.isOnline ? 1 : 0.4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayName)
                        .font(AppFont.medium(15))
                        .foregroundColor(AppColors.textPrimary)
                    if let warning = viewModel.warning(for: device) {
                        Text(warning)
                            .font(AppFont.caption(11))
                            .foregroundColor(AppColors.warning)
                    } else {
                        Text(device.statusText)
                            .font(AppFont.caption(11))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selected ? AppColors.primary : AppColors.textDisabled)
            }
            .padding(12)
            .background(AppColors.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? AppColors.primary : AppColors.border,
                        lineWidth: selected ? 1.5 : 1))
        }
    }
}

// MARK: - Security zone

final class SecurityZoneViewModel: SecurityStepViewModel {
    /// How long a detection waits before the monitoring centre is notified.
    @Published var dismissWindow: DismissAlarmTime = .sec30

    func prefill() {
        dismissWindow = DismissAlarmTime(value: profile?.dismissalWindow)
    }

    func save() {
        submit(.init(dismissalWindow: dismissWindow.rawValue),
               completingStep: .cameraSetup)
    }
}

struct SecurityZoneScreen: View {
    @StateObject var viewModel: SecurityZoneViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .cameraSetup,
                title: "Time to cancel an alarm",
                subtitle: "When an armed camera detects something, you get this long to disarm before an agent is brought in.",
                onPrimary: { viewModel.save() }
            ) {
                SectionCard(title: "Dismissal window") {
                    ForEach(Array(DismissAlarmTime.allCases.enumerated()), id: \.element.id) { index, option in
                        Button {
                            viewModel.dismissWindow = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .font(AppFont.body(15))
                                    .foregroundColor(AppColors.textPrimary)
                                Spacer()
                                Image(systemName: viewModel.dismissWindow == option
                                      ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(viewModel.dismissWindow == option
                                                     ? AppColors.primary : AppColors.textDisabled)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                        }
                        if index < DismissAlarmTime.allCases.count - 1 { RowDivider() }
                    }
                }

                InfoNote(text: "A longer window means fewer false alarms reach the monitoring centre, but a real intruder gets more time.",
                         icon: "exclamationmark.triangle",
                         tint: AppColors.warning)
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.prefill() }
        .onChange(of: viewModel.advanced) { advanced in
            guard advanced else { return }
            pilot.finishSecurityStep(screenFrom: viewModel.screenFrom,
                                     andPush: viewModel.nextDestination)
        }
    }
}
