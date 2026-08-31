//
//  VMSScreen.swift
//  Sandbox
//
//  Desktop access: the same cameras, watched in a browser on a bigger screen.
//
//  Signing in on the desktop is done by emailed link rather than by typing a
//  password into another device, so the whole feature from the app's side is
//  one request plus the cooldown the backend hands back.
//

import SwiftUI
import Combine
import IVSDK

final class VMSViewModel: ObservableObject {

    @Published var result = ResultWrapper()
    @Published var sentToEmail: String?
    /// The backend decides how long before another link may be requested.
    @Published var resendCooldown = 0

    @AppStorage(AppStorageKey.userDetails.rawValue) var user: UserModel?

    private let sharedData: SharedDataStore
    private let userService: UserServiceContract
    private var cancellable: AnyCancellable?
    private var timer: Timer?

    init(sharedData: SharedDataStore,
         userService: UserServiceContract = Factory.userService) {
        self.sharedData = sharedData
        self.userService = userService
    }

    deinit { timer?.invalidate() }

    /// Desktop access shows the cameras in a space, so an account with none has
    /// nothing to open. Saying so is more useful than sending a link to an
    /// empty dashboard.
    var hasCameras: Bool { !sharedData.devices.isEmpty }

    var email: String { user?.email ?? "" }
    var canSend: Bool { hasCameras && resendCooldown == 0 }

    func sendLink() {
        result.update(data: .loading)
        cancellable = userService.sendDesktopAccessEmail()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(response):
                    self.result.update(data: .success)
                    self.sentToEmail = response.email ?? self.email
                    self.startCooldown(seconds: response.resendAvailableInSeconds ?? 60)
                case let .error(error):
                    self.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    private func startCooldown(seconds: Int) {
        resendCooldown = max(0, seconds)
        timer?.invalidate()
        guard resendCooldown > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if self.resendCooldown > 0 { self.resendCooldown -= 1 } else { timer.invalidate() }
        }
    }

    func openInBrowser() {
        guard let url = URL(string: AppConfig.vmsAccessUrl) else { return }
        UIApplication.shared.open(url)
    }
}

struct VMSScreen: View {
    @StateObject var viewModel: VMSViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Desktop access") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 20) {
                            hero

                            if viewModel.hasCameras {
                                addressCard
                                sendCard
                            } else {
                                noCamerasCard
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.primarySoft)
                    .frame(width: 96, height: 96)
                Image(systemName: "display")
                    .font(.system(size: 38, weight: .light))
                    .foregroundColor(AppColors.primary)
            }
            .padding(.top, 12)

            VStack(spacing: 8) {
                Text("Watch on a bigger screen")
                    .font(AppFont.title(24))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Open your cameras in a desktop browser, with several live views side by side.")
                    .font(AppFont.body(15))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var addressCard: some View {
        SectionCard(title: "Web address") {
            Button {
                viewModel.openInBrowser()
            } label: {
                HStack {
                    Text(AppConfig.vmsAccessUrl)
                        .font(AppFont.body(14))
                        .foregroundColor(AppColors.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
            }
        }
    }

    private var sendCard: some View {
        VStack(spacing: 12) {
            if let sentToEmail = viewModel.sentToEmail {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.success)
                    Text("Sign-in link sent to \(sentToEmail). It is good for a single use.")
                        .font(AppFont.body(14))
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(AppColors.success.opacity(0.1))
                .cornerRadius(12)
            } else {
                InfoNote(text: "We will email a sign-in link to \(viewModel.email) so you do not have to type your password on another device.")
            }

            PrimaryButton(title: viewModel.resendCooldown > 0
                          ? "Send again in \(viewModel.resendCooldown)s"
                          : (viewModel.sentToEmail == nil ? "Email me a sign-in link" : "Send another link"),
                          enabled: viewModel.canSend) {
                viewModel.sendLink()
            }
        }
    }

    private var noCamerasCard: some View {
        VStack(spacing: 16) {
            EmptyStateView(icon: "video.slash",
                           title: "No cameras yet",
                           message: "You need at least one camera in your account before you can use desktop access.",
                           actionTitle: "Add a camera") {
                pilot.push(.cameraPermission(screenFrom: .home))
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
    }
}
