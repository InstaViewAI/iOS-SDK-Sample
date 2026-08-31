//
//  ProSecuritySetupScreen.swift
//  Sandbox
//
//  The hub of security onboarding: a checklist the user works down, with
//  progress read from the backend rather than tracked locally. Setup can be
//  abandoned and resumed on another device, so the server is the only
//  trustworthy record of where things stand.
//

import SwiftUI
import Combine
import IVSDK

final class ProSecuritySetupViewModel: ObservableObject {

    @Published var result = ResultWrapper()
    @Published var loaded = false

    let store: ProSecurityStore
    let screenFrom: ScreenFrom
    private var cancellable: AnyCancellable?
    private var storeCancellable: AnyCancellable?

    init(store: ProSecurityStore, screenFrom: ScreenFrom) {
        self.store = store
        self.screenFrom = screenFrom
        storeCancellable = store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    var profile: ProMonitoringModel? { store.profile }

    /// Furthest step done, from the server or from what the app has marked.
    var currentStep: SecuritySetupStep { store.completedStep }

    func isComplete(_ step: SecuritySetupStep) -> Bool { store.isComplete(step) }

    var completedCount: Int {
        SecuritySetupStep.visibleSteps.filter { store.isComplete($0) }.count
    }

    var totalCount: Int { SecuritySetupStep.visibleSteps.count }

    var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    /// The step the user should do next — the first incomplete one.
    var nextStep: SecuritySetupStep? {
        SecuritySetupStep.visibleSteps.first { !store.isComplete($0) }
    }

    /// Steps unlock in order. Letting someone set a safe word before naming an
    /// address would produce a profile the monitoring centre cannot act on.
    /// Only the outstanding step is open. A finished one is not re-entered
    /// here — it is changed from Settings once setup is over, which keeps the
    /// ladder moving in one direction.
    func isUnlocked(_ step: SecuritySetupStep) -> Bool {
        step.order == store.completedStep.order + 1
    }

    func load() {
        if store.profile == nil { result.update(data: .loading) }
        cancellable = store.loadProfile()
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.loaded = true
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.loaded = true
                    // No profile yet simply means setup has not begun: show the
                    // ladder from the top rather than an error dialog. A space
                    // with no plan at all is the dashboard's problem, not this
                    // screen's.
                    if ProSecurityStore.isProfileNotFound(error) || self?.store.hasPlan == false {
                        self?.result.update(data: .success)
                    } else {
                        self?.result.update(data: .error(error: error))
                    }
                @unknown default:
                    break
                }
            }
    }
}

struct ProSecuritySetupScreen: View {
    @StateObject var viewModel: ProSecuritySetupViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Set up security") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 20) {
                            if viewModel.store.isViewer {
                                InfoNote(text: "This space was shared with you. Its professional monitoring is set up by the owner.",
                                         icon: "person.badge.key",
                                         tint: AppColors.warning)
                            }
                            progressCard

                            VStack(spacing: 10) {
                                ForEach(SecuritySetupStep.visibleSteps, id: \.rawValue) { step in
                                    stepRow(step)
                                }
                            }

                            InfoNote(text: "Finished steps can be changed later in Security settings.")

                            if viewModel.nextStep == nil {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(AppColors.success)
                                    Text("Setup is complete. Your system is ready to arm.")
                                        .font(AppFont.body(14))
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity)
                                .background(AppColors.success.opacity(0.1))
                                .cornerRadius(14)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }

                    if let next = viewModel.nextStep, !viewModel.store.isViewer {
                        PrimaryButton(title: viewModel.completedCount == 0
                                      ? "Start setup" : "Continue — \(next.title)") {
                            pilot.push(next.destination(screenFrom: viewModel.screenFrom))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Professional monitoring")
                        .font(AppFont.heading(18))
                        .foregroundColor(AppColors.textPrimary)
                    Text("A monitoring centre watches your alarms around the clock and can dispatch help.")
                        .font(AppFont.caption(12))
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                ZStack {
                    Circle()
                        .stroke(AppColors.border, lineWidth: 5)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: viewModel.progress)
                        .stroke(AppColors.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-90))
                    Text("\(viewModel.completedCount)/\(viewModel.totalCount)")
                        .font(AppFont.caption(11))
                        .foregroundColor(AppColors.textPrimary)
                }
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
    }

    private func stepRow(_ step: SecuritySetupStep) -> some View {
        let done = viewModel.isComplete(step)
        let unlocked = viewModel.isUnlocked(step) && !viewModel.store.isViewer

        return Button {
            guard unlocked else { return }
            pilot.push(step.destination(screenFrom: viewModel.screenFrom))
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(done ? AppColors.success.opacity(0.16)
                              : (unlocked ? AppColors.primarySoft : AppColors.surfaceRaised))
                        .frame(width: 42, height: 42)
                    Image(systemName: done ? "checkmark" : step.icon)
                        .font(.system(size: 16, weight: done ? .bold : .regular))
                        .foregroundColor(done ? AppColors.success
                                         : (unlocked ? AppColors.primary : AppColors.textDisabled))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                        .font(AppFont.medium(15))
                        .foregroundColor(unlocked ? AppColors.textPrimary : AppColors.textDisabled)
                    Text(step.subtitle)
                        .font(AppFont.caption(11))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if step.canSkip && !done {
                    StatusPill(text: "Optional", color: AppColors.textSecondary)
                }
                if done {
                    // Finished, and not editable from here.
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.success)
                } else {
                    Image(systemName: unlocked ? "chevron.right" : "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textDisabled)
                }
            }
            .padding(14)
            .background(AppColors.surface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(step == viewModel.nextStep ? AppColors.primary : AppColors.border,
                        lineWidth: step == viewModel.nextStep ? 1.5 : 1))
        }
        .disabled(!unlocked)
    }
}

extension UIPilot<Destination> {
    /// Where a finished setup step goes back to. Walking the ladder returns to
    /// the hub; editing the same screen from settings returns to settings,
    /// where the hub is not on the stack at all.
    func finishSecurityStep(screenFrom: ScreenFrom, andPush next: Destination? = nil) {
        if screenFrom == .securitySettings {
            pop(andPush: next)
        } else {
            popTo(.securitySetup(screenFrom: screenFrom), andPush: next)
        }
    }
}

// MARK: - Shared scaffold

/// Layout every setup step shares: a titled header, its content, and a
/// primary action pinned to the bottom.
struct SecurityStepScaffold<Content: View>: View {
    let step: SecuritySetupStep
    let title: String
    let subtitle: String
    var primaryTitle: String = "Continue"
    var primaryEnabled: Bool = true
    var onPrimary: () -> Void
    var onSkip: (() -> Void)?
    @ViewBuilder var content: Content

    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                NavBar(title: step.title) { pilot.pop() }

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(AppFont.title(26))
                                .foregroundColor(AppColors.textPrimary)
                            Text(subtitle)
                                .font(AppFont.body(15))
                                .foregroundColor(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: primaryTitle, enabled: primaryEnabled, action: onPrimary)
                    if let onSkip {
                        LinkButton(title: "Skip for now", action: onSkip)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}
