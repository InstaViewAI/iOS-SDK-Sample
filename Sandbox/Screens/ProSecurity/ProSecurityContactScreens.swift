//
//  ProSecurityContactScreens.swift
//  Sandbox
//
//  Step 1 of the ladder: address, phone number, alarm permit.
//
//  This is the only data a dispatcher actually acts on — it is what tells them
//  where to send help and who to call first. The backend validates it against
//  the monitoring centre before letting setup move on.
//

import SwiftUI
import Combine
import IVSDK

// MARK: - Shared view model

class SecurityStepViewModel: ObservableObject {
    @Published var result = ResultWrapper()
    @Published var advanced = false

    let store: ProSecurityStore
    let screenFrom: ScreenFrom
    private var cancellable: AnyCancellable?
    private var createCancellable: AnyCancellable?
    private var stepCancellable: AnyCancellable?

    init(store: ProSecurityStore, screenFrom: ScreenFrom) {
        self.store = store
        self.screenFrom = screenFrom
    }

    var profile: ProMonitoringModel? { store.profile }

    /// Where finishing this screen leads.
    ///
    /// Walking the ladder goes straight into whatever is still outstanding —
    /// there is no reason to send the user back to a checklist to tap the very
    /// next row. Editing from settings goes back to settings instead.
    var nextDestination: Destination? {
        guard advancesSetup else { return nil }
        guard let next = store.nextSetupStep else { return .securitySetupFinish }
        return next.destination(screenFrom: screenFrom)
    }

    /// True whenever the user is walking the setup ladder, whichever entry
    /// point brought them here — the dashboard's "Continue setup" arrives as
    /// `.security`, not `.onboarding`. Only the settings screens edit a
    /// finished profile, and those must not advance anything.
    var advancesSetup: Bool { screenFrom != .securitySettings }

    /// Saves one screen's worth of the profile.
    ///
    /// Which endpoint depends on where the screen was opened from, because the
    /// backend treats first-run setup and later editing as different things:
    ///
    /// - **No profile loaded** — `createProfile`. It carries this screen's data
    ///   itself, so no further write follows; the record is re-read instead.
    /// - **Walking the ladder** — `setupProfile`, carrying the data *and*
    ///   `setupStep` in one call. That is what advances setup.
    /// - **Settings** — `updateProfile` (PATCH), data only. A finished profile
    ///   must never be rewound by someone correcting their address.
    func submit(_ request: ProMonitoringRequest, completingStep step: SecuritySetupStep?) {
        var request = request
        if let step, advancesSetup {
            request.setupStep = step.rawValue
        }
        result.update(data: .loading)

        guard !store.needsProfileCreation else {
            create(request)
            return
        }

        let publisher = advancesSetup ? store.setupProfile(request) : store.updateProfile(request)
        cancellable = publisher.sink { [weak self] state in
            switch state {
            case .loading:
                break
            case .success:
                // Record it here rather than waiting for the hub to re-read the
                // profile: the server may not report it back immediately.
                if let step, self?.advancesSetup == true {
                    self?.store.markStepCompleted(step)
                }
                self?.finish()
            case let .error(error):
                self?.result.update(data: .error(error: error))
            @unknown default:
                break
            }
        }
    }

    /// Marks a step done when the screen collected nothing of its own — the
    /// optional steps a user can pass straight through. Their data, where there
    /// is any, was written by its own endpoint as it was entered.
    func completeStep(_ step: SecuritySetupStep) {
        guard advancesSetup else {
            finish()
            return
        }
        result.update(data: .loading)
        stepCancellable = store.setupProfile(.init(setupStep: step.rawValue))
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.store.markStepCompleted(step)
                    self?.finish()
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    private func create(_ request: ProMonitoringRequest) {
        createCancellable = store.createProfile(request)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    // The POST already carried this screen's data. Re-read the
                    // newly created record so the rest of the flow has one.
                    _ = self?.store.loadProfile { _ in self?.finish() }
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    private func finish() {
        result.update(data: .success)
        advanced = true
    }
}

// MARK: - Address

final class SecurityContactInfoViewModel: SecurityStepViewModel {
    @Published var lineOne = ""
    @Published var crossStreet = ""
    @Published var city = ""
    @Published var state = ""
    @Published var zipCode = ""

    /// Professional monitoring dispatches through a US monitoring centre, so
    /// the protected address is always in the United States. Offering a picker
    /// would only let the user choose something the service cannot act on.
    let country = CountryOption.unitedStates

    /// Chosen from the backend's own list. Events are recorded against the
    /// property's local time, so this belongs to the address rather than to
    /// the phone.
    @Published var timezone: TimezoneModel?
    @Published var showTimezonePicker = false

    func prefill() {
        guard let address = profile?.address else { return }
        // Only prefill a real saved address; an empty profile returns blanks.
        guard address.lineOne.isNotEmpty else { return }
        lineOne = address.lineOne
        crossStreet = address.crossStreet ?? ""
        city = address.city
        state = address.state
        zipCode = address.zipCode
        if let saved = profile?.timezone, !saved.isEmpty {
            // Only the code is stored; the readable name arrives with the list.
            timezone = TimezoneModel(code: saved, name: saved)
        }
    }

    var canSubmit: Bool {
        lineOne.isNotEmpty && city.isNotEmpty && state.isNotEmpty
            && zipCode.isNotEmpty && timezone != nil
    }

    func save() {
        let address = ProMonitoringAddressModel(lineOne: lineOne.trim,
                                                crossStreet: crossStreet.trim,
                                                city: city.trim,
                                                state: state.trim,
                                                country: country.code,
                                                zipCode: zipCode.trim)
        // Timezone travels with the address so scheduled arming fires at the
        // property's local time, not the phone's.
        submit(.init(address: address, timezone: timezone?.code),
               completingStep: nil)
    }
}

struct SecurityContactInfoScreen: View {
    @StateObject var viewModel: SecurityContactInfoViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .contactInformation,
                title: "Where are we protecting?",
                subtitle: "This is the address a dispatcher is sent to, so it has to be exact.",
                primaryEnabled: viewModel.canSubmit,
                onPrimary: { viewModel.save() }
            ) {
                VStack(spacing: 14) {
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
                    // Fixed, not chosen: shown so the constraint is visible
                    // rather than implied.
                    HStack {
                        Text("Country")
                            .font(AppFont.body(15))
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        Text(viewModel.country.name)
                            .font(AppFont.medium(15))
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(AppColors.surface)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))

                    Button {
                        viewModel.showTimezonePicker = true
                    } label: {
                        HStack {
                            Text(viewModel.timezone?.name ?? "Select a timezone")
                                .font(AppFont.body(15))
                                .foregroundColor(viewModel.timezone == nil
                                                 ? AppColors.textDisabled : AppColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(AppColors.surface)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
                    }

                    InfoNote(text: "Professional monitoring is available for United States addresses only. Alarms and schedules use the timezone of the property, not of your phone.")

                    InfoNote(text: "Cross streets help responders find you faster in rural areas and large complexes.")
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.prefill() }
        .sheet(isPresented: $viewModel.showTimezonePicker) {
            TimezonePickerSheet(viewModel: .init(store: viewModel.store),
                                selected: viewModel.timezone) { zone in
                viewModel.timezone = zone
            }
        }
        .onChange(of: viewModel.advanced) { advanced in
            guard advanced else { return }
            pilot.push(.securityPhoneNumber(screenFrom: viewModel.screenFrom))
        }
    }
}

// MARK: - Phone number

final class SecurityPhoneNumberViewModel: SecurityStepViewModel {
    @Published var phoneNumber = ""
    @Published var country = CountryOption.current
    @Published var otpSent = false

    private var otpCancellable: AnyCancellable?

    func prefill() {
        guard let phone = profile?.phoneNumber, phone.number.isNotEmpty else { return }
        phoneNumber = phone.number
        if let match = CountryOption.all.first(where: { $0.dialCode == phone.code }) {
            country = match
        }
    }

    var canSubmit: Bool { phoneNumber.trim.count >= 7 }

    var phone: PhoneNumber {
        PhoneNumber(code: country.dialCode, number: phoneNumber.trim)
    }

    /// The number has to be proven reachable before the monitoring centre will
    /// rely on it, so it is verified by one-time code rather than just saved.
    func sendCode() {
        result.update(data: .loading)
        otpCancellable = store.sendOtp(phone: phone)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.result.update(data: .success)
                    self?.otpSent = true
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}

struct SecurityPhoneNumberScreen: View {
    @StateObject var viewModel: SecurityPhoneNumberViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .contactInformation,
                title: "How do we reach you?",
                subtitle: "If an alarm goes off, an agent calls this number before dispatching anyone.",
                primaryTitle: "Send code",
                primaryEnabled: viewModel.canSubmit,
                onPrimary: { viewModel.sendCode() }
            ) {
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

                InfoNote(text: "We will text a six-digit code to confirm the number works.")
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.prefill() }
        .onChange(of: viewModel.otpSent) { sent in
            guard sent else { return }
            pilot.push(.securityVerifyPhone(phone: viewModel.phoneNumber.trim,
                                            dialCode: viewModel.country.dialCode,
                                            screenFrom: viewModel.screenFrom))
        }
    }
}

// MARK: - Verify phone

final class SecurityVerifyPhoneViewModel: SecurityStepViewModel {
    @Published var code = ""
    @Published var resendCooldown = 0

    let phoneNumber: String
    let dialCode: String

    private var otpCancellable: AnyCancellable?
    private var timer: Timer?

    init(store: ProSecurityStore, screenFrom: ScreenFrom, phone: String, dialCode: String) {
        self.phoneNumber = phone
        self.dialCode = dialCode
        super.init(store: store, screenFrom: screenFrom)
        startCooldown()
    }

    deinit { timer?.invalidate() }

    var displayNumber: String { "\(dialCode) \(phoneNumber)" }
    var canSubmit: Bool { code.trim.count >= 4 }
    var canResend: Bool { resendCooldown == 0 }

    private func startCooldown() {
        resendCooldown = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if self.resendCooldown > 0 { self.resendCooldown -= 1 } else { timer.invalidate() }
        }
    }

    func resend() {
        otpCancellable = store.sendOtp(phone: .init(code: dialCode, number: phoneNumber))
            .sink { [weak self] state in
                if case .success = state { self?.startCooldown() }
            }
    }

    /// The code is submitted as part of the phone number itself — the backend
    /// only stores the number once the pair checks out.
    ///
    /// This completes *Contact information*, not the permit screen that follows
    /// it. Once there is a verified address and phone number a dispatcher has
    /// what they need; the permit is a local formality that many areas do not
    /// require. Marking it here means abandoning setup after the code still
    /// leaves the step banked, and resuming opens the next one.
    func verify() {
        let phone = PhoneNumber(code: dialCode,
                                number: phoneNumber,
                                verified: true,
                                requiredVerification: true,
                                otp: code.trim)
        submit(.init(phoneNumber: phone), completingStep: .contactInformation)
    }
}

struct SecurityVerifyPhoneScreen: View {
    @StateObject var viewModel: SecurityVerifyPhoneViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .contactInformation,
                title: "Enter the code",
                subtitle: "We sent a six-digit code to \(viewModel.displayNumber).",
                primaryTitle: "Verify",
                primaryEnabled: viewModel.canSubmit,
                onPrimary: { viewModel.verify() }
            ) {
                VStack(spacing: 14) {
                    AppTextField(placeholder: "Six-digit code",
                                 text: $viewModel.code,
                                 keyboard: .numberPad)

                    HStack {
                        Text(viewModel.canResend
                             ? "Did not get it?"
                             : "You can ask again in \(viewModel.resendCooldown)s")
                            .font(AppFont.caption(12))
                            .foregroundColor(AppColors.textSecondary)
                        if viewModel.canResend {
                            LinkButton(title: "Resend code") { viewModel.resend() }
                        }
                        Spacer()
                    }
                }
            }
        }, result: $viewModel.result)
        .onChange(of: viewModel.advanced) { advanced in
            guard advanced else { return }
            pilot.finishSecurityStep(screenFrom: viewModel.screenFrom,
                                     andPush: .securityAlarmPermit(screenFrom: viewModel.screenFrom))
        }
    }
}

// MARK: - Alarm permit

final class SecurityAlarmPermitViewModel: SecurityStepViewModel {
    @Published var licenseNumber = ""
    @Published var expiryDate = Date()
    @Published var hasPermit = true

    func prefill() {
        guard let profile, profile.licenseNumber.isNotEmpty else { return }
        licenseNumber = profile.licenseNumber
        if let date = Self.formatter.date(from: profile.licenseExpirationDate) {
            expiryDate = date
        }
    }

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var canSubmit: Bool { !hasPermit || licenseNumber.isNotEmpty }

    /// Many municipalities require a permit before police will respond, and
    /// some fine you for dispatches without one. Where it is not required the
    /// step is still completed, just with empty values.
    /// *Contact information* was completed at phone verification, so this only
    /// saves the permit details and hands on to whatever is outstanding.
    func save() {
        submit(.init(licenseExpirationDate: hasPermit ? Self.formatter.string(from: expiryDate) : "",
                     licenseNumber: hasPermit ? licenseNumber.trim : ""),
               completingStep: nil)
    }
}

struct SecurityAlarmPermitScreen: View {
    @StateObject var viewModel: SecurityAlarmPermitViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .contactInformation,
                title: "Alarm permit",
                subtitle: "Some cities require a permit before police will respond to an alarm.",
                primaryEnabled: viewModel.canSubmit,
                onPrimary: { viewModel.save() }
            ) {
                VStack(spacing: 14) {
                    SectionCard(title: nil) {
                        SettingsToggleRow(title: "I have an alarm permit",
                                          subtitle: "Turn this off if your area does not need one",
                                          icon: "doc.text",
                                          isOn: $viewModel.hasPermit)
                    }

                    if viewModel.hasPermit {
                        AppTextField(placeholder: "Permit number",
                                     text: $viewModel.licenseNumber,
                                     autocapitalization: .characters)

                        SectionCard(title: nil) {
                            DatePicker("Expires",
                                       selection: $viewModel.expiryDate,
                                       in: Date()...,
                                       displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(AppColors.primary)
                                .foregroundColor(AppColors.textPrimary)
                                .padding(.horizontal, 16)
                                .frame(height: 54)
                        }
                    }

                    InfoNote(text: "Check with your local police department. Responding without a permit can carry a fine in some areas.")
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.prefill() }
        .onChange(of: viewModel.advanced) { advanced in
            guard advanced else { return }
            // Contact information is done — back to the hub, which now shows
            // camera setup as the next unlocked step.
            pilot.finishSecurityStep(screenFrom: viewModel.screenFrom,
                                     andPush: viewModel.nextDestination)
        }
    }
}

// MARK: - Shared note

struct InfoNote: View {
    let text: String
    var icon: String = "info.circle"
    var tint: Color = AppColors.accent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(text)
                .font(AppFont.caption(12))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColors.surface)
        .cornerRadius(12)
    }
}
