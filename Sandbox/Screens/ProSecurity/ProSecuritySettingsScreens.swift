//
//  ProSecuritySettingsScreens.swift
//  Sandbox
//
//  Settings for a running system. Everything here was set once during
//  onboarding; these screens reuse the same requests but go through
//  `updateProfile` rather than `setupProfile`, so editing never rewinds the
//  setup ladder.
//

import SwiftUI
import Combine
import IVSDK

// MARK: - Settings index

final class ProSecuritySettingsViewModel: ObservableObject {

    @Published var result = ResultWrapper()
    @Published var showDisarmFirstAlert = false

    let store: ProSecurityStore
    private var cancellable: AnyCancellable?
    private var actionCancellable: AnyCancellable?
    private var storeCancellable: AnyCancellable?

    init(store: ProSecurityStore) {
        self.store = store
        storeCancellable = store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    var profile: ProMonitoringModel? { store.profile }
    var isArmed: Bool { store.status == .armedAll }

    var exitDelay: DelayTime { DelayTime(value: profile?.exitDelay) }
    var dismissWindow: DismissAlarmTime { DismissAlarmTime(value: profile?.dismissalWindow) }
    var cameraCount: Int { store.securedDevices.count }
    var respondingPartyCount: Int { profile?.respondingParties?.count ?? 0 }

    var testMode: Binding<Bool> {
        Binding(
            get: { self.store.isTestMode },
            set: { self.setTestMode($0) }
        )
    }

    func load() {
        cancellable = store.loadProfile().sink { _ in }
    }

    private func setTestMode(_ enable: Bool) {
        result.update(data: .loading)
        actionCancellable = store.enableTestMode(enable)
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

    /// Changing which cameras are enrolled while the system is armed would
    /// leave the backend and the hardware disagreeing about what is watching.
    func guardArmed(_ action: () -> Void) {
        if isArmed {
            showDisarmFirstAlert = true
        } else {
            action()
        }
    }

    func disarm() {
        actionCancellable = store.disarm().sink { _ in }
    }
}

struct ProSecuritySettingsScreen: View {
    @StateObject var viewModel: ProSecuritySettingsViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Security settings") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 18) {
                            SectionCard(title: "Monitoring") {
                                SettingsRow(title: "Personal information",
                                            value: viewModel.profile?.address.city,
                                            icon: "mappin.and.ellipse") {
                                    pilot.push(.securityUpdatePersonalInfo)
                                }
                                RowDivider()
                                SettingsRow(title: "Safe word",
                                            value: "Set",
                                            icon: "key.horizontal") {
                                    pilot.push(.securityUpdateSafeWord)
                                }
                                RowDivider()
                                SettingsRow(title: "Call list",
                                            value: "\(viewModel.respondingPartyCount) contact\(viewModel.respondingPartyCount == 1 ? "" : "s")",
                                            icon: "person.2") {
                                    pilot.push(.securityTeam)
                                }
                            }

                            SectionCard(title: "System") {
                                SettingsRow(title: "Security cameras",
                                            value: "\(viewModel.cameraCount)",
                                            icon: "video") {
                                    viewModel.guardArmed {
                                        pilot.push(.securityCameraSelection(screenFrom: .securitySettings))
                                    }
                                }
                                RowDivider()
                                SettingsRow(title: "Exit delay",
                                            value: viewModel.exitDelay.title,
                                            icon: "timer") {
                                    pilot.push(.securityArmSettings(screenFrom: .securitySettings))
                                }
                                RowDivider()
                                SettingsRow(title: "Time to cancel an alarm",
                                            value: viewModel.dismissWindow.title,
                                            icon: "hourglass") {
                                    pilot.push(.securityZoneSettings(screenFrom: .securitySettings))
                                }
                                RowDivider()
                                SettingsRow(title: "Schedule",
                                            icon: "calendar.badge.clock") {
                                    pilot.push(.securitySchedule(screenFrom: .securitySettings))
                                }
                            }

                            SectionCard(title: "Activity") {
                                SettingsRow(title: "Security log", icon: "list.bullet.rectangle") {
                                    pilot.push(.securityLogs)
                                }
                            }

                            SectionCard(title: "Testing") {
                                SettingsToggleRow(title: "Test mode",
                                                  subtitle: "Run alarms without alerting the monitoring centre",
                                                  icon: "shield.lefthalf.filled",
                                                  isOn: viewModel.testMode)
                            }

                            if viewModel.store.isTestMode {
                                InfoNote(text: "While test mode is on, nothing you trigger reaches the monitoring centre. Remember to switch it back off.",
                                         icon: "exclamationmark.triangle.fill",
                                         tint: AppColors.warning)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
        .overlay {
            if viewModel.showDisarmFirstAlert {
                AppAlertView(shown: $viewModel.showDisarmFirstAlert,
                             title: "Disarm first",
                             message: "The security system has to be disarmed before its cameras can be changed.",
                             okTitle: "Disarm",
                             cancelTitle: "Cancel",
                             onOk: { viewModel.disarm() })
            }
        }
    }
}

// MARK: - Personal information

final class SecurityPersonalInfoViewModel: SecurityStepViewModel {
    @Published var lineOne = ""
    @Published var crossStreet = ""
    @Published var city = ""
    @Published var state = ""
    @Published var zipCode = ""
    @Published var licenseNumber = ""

    /// Same constraint as setup — the protected address is always in the US.
    let country = CountryOption.unitedStates

    func prefill() {
        guard let profile else { return }
        lineOne = profile.address.lineOne
        crossStreet = profile.address.crossStreet ?? ""
        city = profile.address.city
        state = profile.address.state
        zipCode = profile.address.zipCode
        licenseNumber = profile.licenseNumber
    }

    var canSubmit: Bool {
        lineOne.isNotEmpty && city.isNotEmpty && state.isNotEmpty && zipCode.isNotEmpty
    }

    func save() {
        let address = ProMonitoringAddressModel(lineOne: lineOne.trim,
                                                crossStreet: crossStreet.trim,
                                                city: city.trim,
                                                state: state.trim,
                                                country: country.code,
                                                zipCode: zipCode.trim)
        submit(.init(address: address,
                     timezone: profile?.timezone ?? TimeZone.current.identifier,
                     licenseNumber: licenseNumber.trim),
               completingStep: nil)
    }
}

struct SecurityPersonalInfoScreen: View {
    @StateObject var viewModel: SecurityPersonalInfoViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Personal information") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 14) {
                            InfoNote(text: "Changing your address updates what a dispatcher is given. It takes a few minutes to reach the monitoring centre.",
                                     icon: "exclamationmark.triangle",
                                     tint: AppColors.warning)

                            AppTextField(placeholder: "Street address",
                                         text: $viewModel.lineOne,
                                         autocapitalization: .words)
                            AppTextField(placeholder: "Cross street (optional)",
                                         text: $viewModel.crossStreet,
                                         autocapitalization: .words)
                            AppTextField(placeholder: "City",
                                         text: $viewModel.city,
                                         autocapitalization: .words)
                            HStack(spacing: 12) {
                                AppTextField(placeholder: "State",
                                             text: $viewModel.state,
                                             autocapitalization: .characters)
                                AppTextField(placeholder: "ZIP",
                                             text: $viewModel.zipCode,
                                             keyboard: .numbersAndPunctuation)
                            }
                            AppTextField(placeholder: "Alarm permit number",
                                         text: $viewModel.licenseNumber,
                                         autocapitalization: .characters)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }

                    PrimaryButton(title: "Save changes", enabled: viewModel.canSubmit) {
                        viewModel.save()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.prefill() }
        .onChange(of: viewModel.advanced) { advanced in
            if advanced { pilot.pop() }
        }
    }
}

// MARK: - Safe word

final class SecurityUpdateSafeWordViewModel: SecurityStepViewModel {
    @Published var newWord = ""
    @Published var confirmWord = ""
    @Published var confirmError: String?

    var canSubmit: Bool {
        newWord.trim.count >= 4 && newWord.trim == confirmWord.trim
    }

    func save() {
        guard newWord.trim == confirmWord.trim else {
            confirmError = "Safe words do not match"
            return
        }
        confirmError = nil
        submit(.init(safeword: newWord.trim), completingStep: nil)
    }
}

struct SecurityUpdateSafeWordScreen: View {
    @StateObject var viewModel: SecurityUpdateSafeWordViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Safe word") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 14) {
                            InfoNote(text: "For your safety the current safe word is never shown. You can only replace it.",
                                     icon: "eye.slash",
                                     tint: AppColors.primary)

                            AppTextField(placeholder: "New safe word", text: $viewModel.newWord)
                            AppTextField(placeholder: "Confirm safe word",
                                         text: $viewModel.confirmWord,
                                         errorText: viewModel.confirmError)

                            InfoNote(text: "Tell everyone on your call list the new word. An agent will not stand an alarm down without it.")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }

                    PrimaryButton(title: "Update safe word", enabled: viewModel.canSubmit) {
                        viewModel.save()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }, result: $viewModel.result)
        .onChange(of: viewModel.advanced) { advanced in
            if advanced { pilot.pop() }
        }
    }
}

// MARK: - Security team

/// The call list, in the order an agent works down it.
struct SecurityTeamScreen: View {
    @StateObject var viewModel: SecurityInviteHouseholdViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Call list") { pilot.pop() }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            InfoNote(text: "An agent phones these people in order before contacting the authorities. Everyone here needs to know the safe word.")

                            if viewModel.respondingParties.isEmpty {
                                EmptyStateView(icon: "person.2.slash",
                                               title: "Only you",
                                               message: "Add someone else so there is a second person to reach if you cannot answer.")
                            } else {
                                SectionCard(title: "Contacts") {
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
                                        .frame(height: 58)
                                        if index < viewModel.respondingParties.count - 1 { RowDivider() }
                                    }
                                }
                            }

                            SecondaryButton(title: "Add someone") {
                                pilot.push(.securityInviteHousehold(screenFrom: .securitySettings))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
        }, result: $viewModel.result)
    }
}
