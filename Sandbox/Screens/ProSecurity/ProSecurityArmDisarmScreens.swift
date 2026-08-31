//
//  ProSecurityArmDisarmScreens.swift
//  Sandbox
//
//  Steps 3 and 4: the exit delay, and how the system can be turned off again.
//

import SwiftUI
import Combine
import IVSDK

// MARK: - Arm settings

final class SecurityArmSettingsViewModel: SecurityStepViewModel {
    /// Grace period between arming and the system going live.
    @Published var exitDelay: DelayTime = .sec60

    func prefill() {
        exitDelay = DelayTime(value: profile?.exitDelay)
    }

    func save() {
        submit(.init(exitDelay: exitDelay.rawValue), completingStep: .armSettings)
    }
}

struct SecurityArmSettingsScreen: View {
    @StateObject var viewModel: SecurityArmSettingsViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .armSettings,
                title: "Time to leave",
                subtitle: "After you arm the system, this is how long you have before it starts watching.",
                onPrimary: { viewModel.save() }
            ) {
                SectionCard(title: "Exit delay") {
                    ForEach(Array(DelayTime.allCases.enumerated()), id: \.element.id) { index, option in
                        Button {
                            viewModel.exitDelay = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .font(AppFont.body(15))
                                    .foregroundColor(AppColors.textPrimary)
                                Spacer()
                                Image(systemName: viewModel.exitDelay == option
                                      ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(viewModel.exitDelay == option
                                                     ? AppColors.primary : AppColors.textDisabled)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                        }
                        if index < DelayTime.allCases.count - 1 { RowDivider() }
                    }
                }

                InfoNote(text: "Pick long enough to get out of the door and past every armed camera. Walking through your own driveway camera at 30 seconds is the most common false alarm.")
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

// MARK: - Disarm methods

/// Disarming from the app is always available; the safe word is what proves
/// identity to an agent on the phone, when the app is not to hand.
struct SecurityDisarmMethodScreen: View {
    let screenFrom: ScreenFrom
    @EnvironmentObject private var pilot: UIPilot<Destination>

    private struct Method {
        let icon: String
        let title: String
        let body: String
        let always: Bool
    }

    private let methods: [Method] = [
        Method(icon: "iphone",
               title: "From this app",
               body: "Slide to disarm on the security screen. Anyone you invite to your household can do the same.",
               always: true),
        Method(icon: "calendar.badge.clock",
               title: "On a schedule",
               body: "Disarm automatically at set times — every weekday morning, for instance.",
               always: false),
        Method(icon: "key.horizontal",
               title: "With your safe word",
               body: "Tell an agent your safe word when they call and they will stand the alarm down.",
               always: true)
    ]

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                NavBar(title: SecuritySetupStep.disarmSettings.title) { pilot.pop() }

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How you turn it off")
                                .font(AppFont.title(26))
                                .foregroundColor(AppColors.textPrimary)
                            Text("Three ways to disarm. The next screen sets the safe word.")
                                .font(AppFont.body(15))
                                .foregroundColor(AppColors.textSecondary)
                        }

                        VStack(spacing: 12) {
                            ForEach(Array(methods.enumerated()), id: \.offset) { _, method in
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: method.icon)
                                        .font(.system(size: 19))
                                        .foregroundColor(AppColors.primary)
                                        .frame(width: 44, height: 44)
                                        .background(AppColors.primarySoft)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(method.title)
                                                .font(AppFont.medium(15))
                                                .foregroundColor(AppColors.textPrimary)
                                            if method.always {
                                                StatusPill(text: "Always on", color: AppColors.success)
                                            }
                                        }
                                        Text(method.body)
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
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                PrimaryButton(title: "Set a safe word") {
                    pilot.push(.securitySafeWord(screenFrom: screenFrom))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Safe word

final class SecuritySafeWordViewModel: SecurityStepViewModel {
    @Published var safeWord = ""
    @Published var confirmWord = ""
    @Published var confirmError: String?

    /// Short or obvious words are easy for someone standing over you to guess,
    /// which defeats the point of the check.
    private static let banned = ["password", "safeword", "help", "1234", "0000"]

    var canSubmit: Bool {
        safeWord.trim.count >= 4 && safeWord.trim == confirmWord.trim
    }

    func save() {
        let word = safeWord.trim
        guard word == confirmWord.trim else {
            confirmError = "Safe words do not match"
            return
        }
        guard !Self.banned.contains(word.lowercased()) else {
            confirmError = "Choose something less guessable"
            return
        }
        confirmError = nil
        submit(.init(safeword: word), completingStep: .disarmSettings)
    }
}

struct SecuritySafeWordScreen: View {
    @StateObject var viewModel: SecuritySafeWordViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            SecurityStepScaffold(
                step: .disarmSettings,
                title: "Choose a safe word",
                subtitle: "An agent asks for this when they call. It proves the person answering is really you.",
                primaryTitle: "Save safe word",
                primaryEnabled: viewModel.canSubmit,
                onPrimary: { viewModel.save() }
            ) {
                VStack(spacing: 14) {
                    AppTextField(placeholder: "Safe word", text: $viewModel.safeWord)
                    AppTextField(placeholder: "Confirm safe word",
                                 text: $viewModel.confirmWord,
                                 errorText: viewModel.confirmError)

                    InfoNote(text: "Pick something memorable that a stranger could not guess from looking around your home. Share it with everyone in your household.",
                             icon: "lock.shield",
                             tint: AppColors.primary)

                    InfoNote(text: "If you are ever forced to disarm under duress, give a wrong safe word. The agent will treat it as a real emergency and send help anyway.",
                             icon: "exclamationmark.triangle.fill",
                             tint: AppColors.warning)
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
