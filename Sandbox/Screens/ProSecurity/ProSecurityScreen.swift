//
//  ProSecurityScreen.swift
//  Sandbox
//
//  The security dashboard. Three states live here: no subscription (upsell),
//  subscribed but setup unfinished (resume the ladder), and a running system
//  (arm, disarm, and watch).
//

import SwiftUI
import Combine
import IVSDK

final class ProSecurityViewModel: ObservableObject {

    @Published var result = ResultWrapper()
    @Published var loaded = false
    @Published var showLowBatteryWarning = false
    @Published var showAllOfflineWarning = false

    let store: ProSecurityStore
    private var profileCancellable: AnyCancellable?
    private var actionCancellable: AnyCancellable?
    private var logsCancellable: AnyCancellable?
    private var storeCancellable: AnyCancellable?

    init(store: ProSecurityStore) {
        self.store = store
        storeCancellable = store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    var profile: ProMonitoringModel? { store.profile }
    var status: ProMonitoringStatus { store.status }
    /// No plan on the space — the only case that should show an upsell.
    var notSubscribed: Bool { !store.hasPlan }
    var isViewer: Bool { store.isViewer }
    var setupFinished: Bool { store.setupFinished }
    var securedDevices: [DeviceModel] { store.securedDevices }
    var recentLogs: [SecurityLogsModel] { Array(store.securityLogs.prefix(4)) }

    var isArmed: Bool { status == .armedAll }
    var isBusy: Bool { status.isTransitioning }

    func load() {
        if store.profile == nil { result.update(data: .loading) }
        profileCancellable = store.loadProfile()
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case .success:
                    self.loaded = true
                    self.result.update(data: .success)
                    _ = self.store.sharedDataDevices()
                    self.logsCancellable = self.store.loadSecurityLogs(limit: 20).sink { _ in }
                case let .error(error):
                    self.loaded = true
                    // A subscribed space that has not started setup has no
                    // profile yet; that is the setup flow's cue, not an error.
                    if ProSecurityStore.isProfileNotFound(error) || !self.store.hasPlan {
                        self.result.update(data: .success)
                    } else {
                        self.result.update(data: .error(error: error))
                    }
                @unknown default:
                    break
                }
            }
    }

    func stopPolling() {
        store.stopStatusPolling()
    }

    // MARK: - Arm / disarm

    /// Arming with nothing that can see is worse than not arming — the user
    /// believes they are protected when they are not.
    func attemptArm() {
        guard !securedDevices.isEmpty else { return }
        guard securedDevices.contains(where: \.isOnline) else {
            showAllOfflineWarning = true
            return
        }
        let lowBattery = securedDevices.contains {
            $0.isBatteryPowered && ($0.deviceState.batteryPercentage ?? 100) < 20
        }
        if lowBattery {
            showLowBatteryWarning = true
        } else {
            arm()
        }
    }

    func arm() {
        result.update(data: .loading)
        actionCancellable = store.arm()
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    func disarm() {
        result.update(data: .loading)
        actionCancellable = store.disarm()
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}

struct ProSecurityScreen: View {
    @StateObject var viewModel: ProSecurityViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 20) {
                        if viewModel.notSubscribed {
                            upsell
                        } else if viewModel.isViewer {
                            notOwner
                        } else if !viewModel.setupFinished {
                            resumeSetup
                        } else {
                            armControl
                            if viewModel.store.isTestMode { testModeBanner }
                            devicesSection
                            logsSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .refreshable { viewModel.load() }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stopPolling() }
        .overlay {
            if viewModel.showAllOfflineWarning {
                AppAlertView(shown: $viewModel.showAllOfflineWarning,
                             title: "All cameras are offline",
                             message: "At least one camera has to be online before the system can be armed.",
                             okTitle: "OK")
            }
            if viewModel.showLowBatteryWarning {
                AppAlertView(shown: $viewModel.showLowBatteryWarning,
                             title: "Battery is low",
                             message: "One of your cameras is below 20%. It may fail to arm or drop out during the night.",
                             okTitle: "Arm anyway",
                             cancelTitle: "Cancel",
                             onOk: { viewModel.arm() })
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Security")
                    .font(AppFont.heading(20))
                    .foregroundColor(AppColors.textPrimary)
                if let address = viewModel.profile?.address, address.lineOne.isNotEmpty {
                    Text(address.displayAddress)
                        .font(AppFont.caption(12))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if viewModel.setupFinished, !viewModel.isViewer {
                Button {
                    pilot.push(.securitySettings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(AppColors.surface)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: States

    private var upsell: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppColors.primarySoft)
                    .frame(width: 112, height: 112)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 46, weight: .light))
                    .foregroundColor(AppColors.primary)
            }
            .padding(.top, 32)

            VStack(spacing: 10) {
                Text("Professional monitoring")
                    .font(AppFont.title(26))
                    .foregroundColor(AppColors.textPrimary)
                Text("Your cameras already alert you. Monitoring adds people who act when you cannot.")
                    .font(AppFont.body(15))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                benefit(icon: "person.badge.clock", title: "Agents on watch 24/7",
                        body: "Every alarm is reviewed by a person, not just a phone.")
                benefit(icon: "phone.badge.waveform", title: "They call you first",
                        body: "An agent confirms with your safe word before doing anything else.")
                benefit(icon: "shield.lefthalf.filled", title: "Dispatch when it counts",
                        body: "If you cannot be reached, they can send police or fire.")
            }
        }
    }

    private func benefit(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(AppColors.primary)
                .frame(width: 42, height: 42)
                .background(AppColors.primarySoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppFont.medium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(body)
                    .font(AppFont.caption(12))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
    }

    /// Shared spaces put a viewer here. Configuring monitoring means changing
    /// the address a dispatcher is sent to and the people they call, so it
    /// stays with the owner.
    private var notOwner: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppColors.surfaceRaised)
                    .frame(width: 112, height: 112)
                Image(systemName: "person.badge.key")
                    .font(.system(size: 42, weight: .light))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.top, 32)

            VStack(spacing: 10) {
                Text("You are not the owner")
                    .font(AppFont.title(26))
                    .foregroundColor(AppColors.textPrimary)
                Text("This space was shared with you, so its professional monitoring is set up and managed by the owner.")
                    .font(AppFont.body(15))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var resumeSetup: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppColors.warning.opacity(0.14))
                    .frame(width: 112, height: 112)
                Image(systemName: "shield.slash")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(AppColors.warning)
            }
            .padding(.top, 32)

            VStack(spacing: 10) {
                Text("Setup is not finished")
                    .font(AppFont.title(26))
                    .foregroundColor(AppColors.textPrimary)
                Text("Monitoring cannot start until the remaining steps are done. Your progress is saved.")
                    .font(AppFont.body(15))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(title: "Continue setup") {
                pilot.push(.securitySetup(screenFrom: .security))
            }
        }
    }

    // MARK: Arm control

    private var armControl: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(viewModel.status.color.opacity(0.12))
                    .frame(width: 168, height: 168)
                Circle()
                    .stroke(viewModel.status.color.opacity(0.35), lineWidth: 2)
                    .frame(width: 196, height: 196)
                VStack(spacing: 8) {
                    Image(systemName: viewModel.status.icon)
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(viewModel.status.color)
                    Text(viewModel.status.title)
                        .font(AppFont.heading(18))
                        .foregroundColor(AppColors.textPrimary)
                }
            }
            .frame(height: 210)

            Text(statusDetail)
                .font(AppFont.body(14))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            SlideToConfirm(title: viewModel.isArmed ? "Slide to disarm" : "Slide to arm",
                           tint: viewModel.isArmed ? AppColors.success : AppColors.error,
                           enabled: !viewModel.isBusy) {
                viewModel.isArmed ? viewModel.disarm() : viewModel.attemptArm()
            }
        }
    }

    private var statusDetail: String {
        switch viewModel.status {
        case .armedAll:
            return "\(viewModel.securedDevices.count) camera\(viewModel.securedDevices.count == 1 ? "" : "s") are watching."
        case .arming:
            let delay = viewModel.profile?.exitDelay ?? 60
            return "You have \(delay) seconds to leave."
        case .disarming:
            return "Standing the system down…"
        case .disarmed:
            return "Nothing is being monitored right now."
        @unknown default:
            return ""
        }
    }

    private var testModeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Test mode is on")
                    .font(AppFont.medium(14))
                    .foregroundColor(AppColors.textPrimary)
                Text("Alarms are not passed to the monitoring centre.")
                    .font(AppFont.caption(11))
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColors.warning.opacity(0.1))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.warning.opacity(0.35), lineWidth: 1))
    }

    // MARK: Sections

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SECURITY CAMERAS")
                    .font(AppFont.caption(11))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                LinkButton(title: "Edit") {
                    pilot.push(.securityCameraSelection(screenFrom: .securitySettings))
                }
            }

            if viewModel.securedDevices.isEmpty {
                Text("No cameras added to the security system.")
                    .font(AppFont.body(14))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surface)
                    .cornerRadius(14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.securedDevices.enumerated()), id: \.element.id) { index, device in
                        let state = viewModel.profile?.state(for: device.id) ?? .disarmed
                        Button {
                            pilot.push(.liveView(device: device))
                        } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: device.snapshotURL)
                                .frame(width: 52, height: 40)
                                .cornerRadius(8)
                                .opacity(device.isOnline ? 1 : 0.4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.displayName)
                                    .font(AppFont.medium(14))
                                    .foregroundColor(AppColors.textPrimary)
                                Text(device.statusText)
                                    .font(AppFont.caption(11))
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            Spacer()
                            StatusPill(text: state.title, color: state.color)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        }
                        if index < viewModel.securedDevices.count - 1 { RowDivider() }
                    }
                }
                .background(AppColors.surface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            }
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SECURITY LOG")
                    .font(AppFont.caption(11))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                LinkButton(title: "See all") { pilot.push(.securityLogs) }
            }

            if viewModel.recentLogs.isEmpty {
                Text("Nothing has happened yet.")
                    .font(AppFont.body(14))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surface)
                    .cornerRadius(14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.recentLogs.enumerated()), id: \.element.id) { index, log in
                        SecurityLogRow(log: log)
                        if index < viewModel.recentLogs.count - 1 { RowDivider() }
                    }
                }
                .background(AppColors.surface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            }
        }
    }
}

// MARK: - Slide to confirm

/// Arming and disarming are consequential enough that a tap is too easy —
/// a deliberate drag prevents pocket presses either way.
struct SlideToConfirm: View {
    let title: String
    let tint: Color
    var enabled: Bool = true
    let onConfirm: () -> Void

    @State private var offset: CGFloat = 0
    private let knobSize: CGFloat = 54

    var body: some View {
        GeometryReader { geometry in
            let travel = geometry.size.width - knobSize - 8

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.surface)
                    .overlay(Capsule().stroke(AppColors.border, lineWidth: 1))

                Text(title)
                    .font(AppFont.medium(15))
                    .foregroundColor(enabled ? AppColors.textSecondary : AppColors.textDisabled)
                    .frame(maxWidth: .infinity)
                    // Fade the label out as the knob covers it.
                    .opacity(1 - Double(offset / max(travel, 1)))

                Circle()
                    .fill(enabled ? tint : AppColors.surfaceRaised)
                    .frame(width: knobSize, height: knobSize)
                    .overlay(
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: offset + 4)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard enabled else { return }
                                offset = min(max(0, value.translation.width), travel)
                            }
                            .onEnded { _ in
                                guard enabled else { return }
                                // Only the far end counts; anything short
                                // springs back rather than half-committing.
                                if offset >= travel - 8 {
                                    onConfirm()
                                }
                                withAnimation(.spring(response: 0.3)) { offset = 0 }
                            }
                    )
            }
        }
        .frame(height: 62)
        .opacity(enabled ? 1 : 0.6)
    }
}

// MARK: - Log row

struct SecurityLogRow: View {
    let log: SecurityLogsModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: log.logType.icon)
                .font(.system(size: 14))
                .foregroundColor(log.logType.color)
                .frame(width: 34, height: 34)
                .background(log.logType.color.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(log.logType.title)
                    .font(AppFont.medium(14))
                    .foregroundColor(AppColors.textPrimary)
                if let detail = detailText {
                    Text(detail)
                        .font(AppFont.caption(11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(log.date.relativeEventLabel)
                .font(AppFont.caption(11))
                .foregroundColor(AppColors.textDisabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Who did it, or which cameras failed to arm — whichever the entry knows.
    private var detailText: String? {
        if let user = log.properties?.user?.name, !user.isEmpty {
            return "by \(user)"
        }
        if let method = log.properties?.disarmedMethod, !method.isEmpty {
            return "via \(method)"
        }
        if log.logType == .armed, let devices = log.properties?.devices {
            let failed = devices.filter {
                SecurityDeviceArmStatus(rawValue: $0.armStatus) != .success
            }
            if !failed.isEmpty {
                return "\(failed.count) camera\(failed.count == 1 ? "" : "s") failed to arm"
            }
        }
        if let deviceName = log.properties?.deviceName, !deviceName.isEmpty {
            return deviceName
        }
        return nil
    }
}
