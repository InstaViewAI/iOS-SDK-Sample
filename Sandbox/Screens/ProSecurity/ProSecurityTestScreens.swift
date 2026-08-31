//
//  ProSecurityTestScreens.swift
//  Sandbox
//
//  Steps 6 and 7: prove the system works, then invite the people who will use
//  it. Both are optional, but skipping the test means the first time anyone
//  finds out whether arming actually works is during a real break-in.
//

import SwiftUI
import Combine
import UserNotifications
import IVSDK

// MARK: - Critical alerts

/// Security alerts are the one case where a notification must break through
/// silent mode and Focus, so they need a separate permission from ordinary
/// push. iOS grants it only to entitled apps, and only if the user agrees.
final class SecurityCriticalAlertsViewModel: SecurityStepViewModel {
    @Published var granted = false
    @Published var asked = false

    func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.granted = settings.criticalAlertSetting == .enabled
            }
        }
    }

    func request() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, _ in
                DispatchQueue.main.async {
                    self.granted = granted
                    self.asked = true
                    if granted { UIApplication.shared.registerForRemoteNotifications() }
                }
            }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct SecurityCriticalAlertsScreen: View {
    @StateObject var viewModel: SecurityCriticalAlertsViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .testSystem,
                title: "Let alarms reach you",
                subtitle: "Critical alerts sound even when your phone is silenced or in Focus. Without them an alarm at 3am may go unheard.",
                primaryTitle: viewModel.granted ? "Continue" : "Allow critical alerts",
                onPrimary: {
                    if viewModel.granted {
                        pilot.push(.securitySystemTest(screenFrom: viewModel.screenFrom))
                    } else if viewModel.asked {
                        // The system prompt only ever appears once; after a
                        // refusal the only route is iOS Settings.
                        viewModel.openSettings()
                    } else {
                        viewModel.request()
                    }
                },
                onSkip: {
                    pilot.push(.securitySystemTest(screenFrom: viewModel.screenFrom))
                }
            ) {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.granted ? "checkmark.circle.fill" : "bell.badge.fill")
                            .font(.system(size: 20))
                            .foregroundColor(viewModel.granted ? AppColors.success : AppColors.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.granted ? "Critical alerts are on" : "Critical alerts are off")
                                .font(AppFont.medium(15))
                                .foregroundColor(AppColors.textPrimary)
                            Text(viewModel.granted
                                 ? "Alarms will sound through silent mode."
                                 : "Alarms will follow your normal notification settings.")
                                .font(AppFont.caption(12))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(AppColors.surface)
                    .cornerRadius(14)

                    if viewModel.asked && !viewModel.granted {
                        InfoNote(text: "iOS only asks once. Turn this on under Settings → Notifications → Sandbox → Critical Alerts.",
                                 icon: "gear",
                                 tint: AppColors.warning)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.refresh() }
    }
}

// MARK: - System test

/// Test mode runs a genuine arm-and-trigger cycle with the monitoring centre
/// told to stand down, so the whole chain is exercised without anyone being
/// dispatched to the door.
final class SecuritySystemTestViewModel: SecurityStepViewModel {

    enum Phase {
        case idle, enabling, armed, done

        var title: String {
            switch self {
            case .idle:     return "Ready to test"
            case .enabling: return "Turning on test mode…"
            case .armed:    return "Test mode is live"
            case .done:     return "Test complete"
            }
        }
    }

    @Published var phase: Phase = .idle
    private var testCancellable: AnyCancellable?

    func startTest() {
        phase = .enabling
        result.update(data: .loading)
        testCancellable = store.enableTestMode(true)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.phase = .armed
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.phase = .idle
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    func finishTest() {
        result.update(data: .loading)
        // Leaving test mode on would silently neuter the real system, so it is
        // turned off before the step is marked complete.
        testCancellable = store.enableTestMode(false)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success, .error:
                    self?.phase = .done
                    self?.completeStep(.testSystem)
                @unknown default:
                    break
                }
            }
    }
}

struct SecuritySystemTestScreen: View {
    @StateObject var viewModel: SecuritySystemTestViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    private let steps = [
        "Arm the system from the security screen.",
        "Walk in front of one of your armed cameras.",
        "Watch the alarm countdown start on your phone.",
        "Disarm before it runs out, then come back here."
    ]

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .testSystem,
                title: "Test run",
                subtitle: "A full rehearsal with the monitoring centre standing down. Nobody is called and nobody is dispatched.",
                primaryTitle: viewModel.phase == .armed ? "I finished the test" : "Turn on test mode",
                onPrimary: {
                    viewModel.phase == .armed ? viewModel.finishTest() : viewModel.startTest()
                },
                onSkip: {
                    // Skipping still closes the step — otherwise "next" is
                    // this screen again and the flow loops.
                    viewModel.completeStep(.testSystem)
                }
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.phase == .armed
                              ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                            .font(.system(size: 20))
                            .foregroundColor(viewModel.phase == .armed ? AppColors.success : AppColors.primary)
                        Text(viewModel.phase.title)
                            .font(AppFont.medium(15))
                            .foregroundColor(AppColors.textPrimary)
                        Spacer(minLength: 0)
                        if viewModel.phase == .armed {
                            StatusPill(text: "Test mode", color: AppColors.warning)
                        }
                    }
                    .padding(16)
                    .background(AppColors.surface)
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(AppFont.caption(11))
                                    .foregroundColor(AppColors.primary)
                                    .frame(width: 20, height: 20)
                                    .background(AppColors.primarySoft)
                                    .clipShape(Circle())
                                Text(step)
                                    .font(AppFont.body(14))
                                    .foregroundColor(AppColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    InfoNote(text: "Test mode switches itself off when you finish, so the system goes back to live monitoring.",
                             icon: "arrow.uturn.backward",
                             tint: AppColors.accent)
                }
            }
        }, result: $viewModel.result)
        .onChange(of: viewModel.advanced) { advanced in
            guard advanced else { return }
            pilot.finishSecurityStep(screenFrom: viewModel.screenFrom,
                                     andPush: viewModel.nextDestination)
        }
    }
}

// MARK: - Invite household

/// Responding parties are the people an agent phones, in order, before
/// dispatching. Adding a second contact matters most when the owner cannot be
/// reached — which is exactly when an alarm is most likely to be real.
final class SecurityInviteHouseholdViewModel: SecurityStepViewModel {
    @Published var name = ""
    @Published var phoneNumber = ""
    @Published var country = CountryOption.current

    private var inviteCancellable: AnyCancellable?

    var respondingParties: [RespondingParty] { profile?.respondingParties ?? [] }
    var canSubmit: Bool { name.isNotEmpty && phoneNumber.trim.count >= 7 }

    func invite() {
        result.update(data: .loading)
        inviteCancellable = store.updateRespondingParty(
            .init(code: country.dialCode, number: phoneNumber.trim, name: name.trim)
        )
        .sink { [weak self] state in
            switch state {
            case .loading:
                break
            case .success:
                self?.name = ""
                self?.phoneNumber = ""
                self?.result.update(data: .success)
            case let .error(error):
                self?.result.update(data: .error(error: error))
            @unknown default:
                break
            }
        }
    }

    func finishStep() {
        // The call list is written by its own endpoint as each contact is
        // added, so this only closes the step.
        completeStep(.inviteHousehold)
    }
}

struct SecurityInviteHouseholdScreen: View {
    @StateObject var viewModel: SecurityInviteHouseholdViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    private var isSetup: Bool { viewModel.advancesSetup }

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .inviteHousehold,
                title: "Who else should we call?",
                subtitle: "An agent works down this list before dispatching anyone. Everyone on it needs to know the safe word.",
                primaryTitle: isSetup ? "Finish setup" : "Done",
                onPrimary: {
                    isSetup ? viewModel.finishStep() : pilot.pop()
                },
                onSkip: isSetup ? { viewModel.finishStep() } : nil
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    if !viewModel.respondingParties.isEmpty {
                        SectionCard(title: "Call list") {
                            ForEach(Array(viewModel.respondingParties.enumerated()), id: \.element.id) { index, party in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(AppFont.caption(11))
                                        .foregroundColor(AppColors.primary)
                                        .frame(width: 22, height: 22)
                                        .background(AppColors.primarySoft)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(party.name ?? "Contact")
                                            .font(AppFont.body(15))
                                            .foregroundColor(AppColors.textPrimary)
                                        if let phone = party.phoneNumber {
                                            Text("\(phone.code) \(phone.number)")
                                                .font(AppFont.caption(11))
                                                .foregroundColor(AppColors.textSecondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 56)
                                if index < viewModel.respondingParties.count - 1 { RowDivider() }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("ADD SOMEONE")
                            .font(AppFont.caption(11))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.leading, 4)

                        AppTextField(placeholder: "Name",
                                     text: $viewModel.name,
                                     autocapitalization: .words)

                        HStack(spacing: 12) {
                            Menu {
                                ForEach(CountryOption.all) { option in
                                    Button("\(option.name) (\(option.dialCode))") { viewModel.country = option }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(viewModel.country.dialCode)
                                        .font(AppFont.body(16))
                                        .foregroundColor(AppColors.textPrimary)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 52)
                                .background(AppColors.surface)
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
                            }
                            AppTextField(placeholder: "Phone number",
                                         text: $viewModel.phoneNumber,
                                         keyboard: .phonePad)
                        }

                        SecondaryButton(title: "Add to call list") {
                            viewModel.invite()
                        }
                        .disabled(!viewModel.canSubmit)
                        .opacity(viewModel.canSubmit ? 1 : 0.5)
                    }

                    InfoNote(text: "The account owner is always called first. Everyone else is contacted in the order shown.")
                }
            }
        }, result: $viewModel.result)
        .onChange(of: viewModel.advanced) { advanced in
            guard advanced else { return }
            pilot.finishSecurityStep(screenFrom: viewModel.screenFrom,
                                     andPush: viewModel.nextDestination)
        }
    }
}

// MARK: - Finish

struct SecuritySetupFinishScreen: View {
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(AppColors.success.opacity(0.14))
                            .frame(width: 132, height: 132)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 56, weight: .light))
                            .foregroundColor(AppColors.success)
                    }

                    VStack(spacing: 12) {
                        Text("You are protected")
                            .font(AppFont.title(30))
                            .foregroundColor(AppColors.textPrimary)
                        Text("Professional monitoring is live. Arm the system whenever you leave, and an agent is watching for alarms around the clock.")
                            .font(AppFont.body(15))
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 28)
                }

                Spacer()

                PrimaryButton(title: "Go to security") {
                    pilot.popTo(.appTabBar)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}
