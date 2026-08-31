//
//  MyAccountScreen.swift
//  Sandbox
//

import SwiftUI
import Combine
import IVSDK

final class MyAccountViewModel: ObservableObject {

    @Published var firstName = ""
    @Published var lastName = ""
    @Published var phoneNumber = ""
    @Published var country = CountryOption.current
    @Published var result = ResultWrapper()
    @Published var saved = false
    @Published var showDeleteConfirm = false
    @Published var accountDeleted = false

    @AppStorage(AppStorageKey.userDetails.rawValue) var user: UserModel?

    private let userService: UserServiceContract
    private var updateCancellable: AnyCancellable?
    private var deleteCancellable: AnyCancellable?

    init(userService: UserServiceContract = Factory.userService) {
        self.userService = userService
        applyUser()
    }

    private func applyUser() {
        firstName = user?.name.first ?? ""
        lastName = user?.name.last ?? ""
        phoneNumber = user?.phoneNumber.number ?? ""
        if let code = user?.phoneNumber.code,
           let match = CountryOption.all.first(where: { $0.dialCode == code }) {
            country = match
        }
    }

    var email: String { user?.email ?? "" }
    var canSave: Bool { firstName.isNotEmpty }

    func save() {
        result.update(data: .loading)
        let request = UpdateUserRequest(
            name: UserName(firstName: firstName.trim, lastName: lastName.trim),
            phoneNumber: PhoneNumber(code: country.dialCode, number: phoneNumber.trim)
        )

        updateCancellable = userService.updateUser(request: request)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(user):
                    self?.user = user
                    self?.result.update(data: .success)
                    self?.saved = true
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    func deleteAccount() {
        result.update(data: .loading)
        deleteCancellable = userService.deleteUser()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.result.update(data: .success)
                    self?.accountDeleted = true
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}

struct MyAccountScreen: View {
    @StateObject var viewModel: MyAccountViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>
    @EnvironmentObject private var appWindowManager: AppWindowManager

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "My account") { pilot.pop() }

                    ScrollView {
                        VStack(spacing: 18) {
                            SectionCard(title: "Sign-in email") {
                                HStack {
                                    Text(viewModel.email)
                                        .font(AppFont.body(15))
                                        .foregroundColor(AppColors.textPrimary)
                                    Spacer()
                                    StatusPill(text: "Verified", color: AppColors.success)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 54)
                            }

                            VStack(spacing: 14) {
                                HStack(spacing: 12) {
                                    AppTextField(placeholder: "First name",
                                                 text: $viewModel.firstName,
                                                 autocapitalization: .words)
                                    AppTextField(placeholder: "Last name",
                                                 text: $viewModel.lastName,
                                                 autocapitalization: .words)
                                }

                                HStack(spacing: 12) {
                                    Menu {
                                        ForEach(CountryOption.all) { option in
                                            Button("\(option.name) (\(option.dialCode))") {
                                                viewModel.country = option
                                            }
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
                                        .overlay(RoundedRectangle(cornerRadius: 14)
                                            .stroke(AppColors.border, lineWidth: 1))
                                    }

                                    AppTextField(placeholder: "Phone number",
                                                 text: $viewModel.phoneNumber,
                                                 keyboard: .phonePad)
                                }
                            }

                            PrimaryButton(title: "Save changes", enabled: viewModel.canSave) {
                                viewModel.save()
                            }

                            Button {
                                viewModel.showDeleteConfirm = true
                            } label: {
                                Text("Delete my account")
                                    .font(AppFont.medium(15))
                                    .foregroundColor(AppColors.error)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(AppColors.error.opacity(0.1))
                                    .cornerRadius(14)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }, result: $viewModel.result)
        .overlay {
            if viewModel.showDeleteConfirm {
                AppAlertView(shown: $viewModel.showDeleteConfirm,
                             title: "Delete your account?",
                             message: "Your spaces, cameras and recordings will be permanently removed. This cannot be undone.",
                             okTitle: "Delete",
                             cancelTitle: "Cancel", onOk: {
                    viewModel.deleteAccount()
                })
            }
        }
        .onChange(of: viewModel.saved) { saved in
            if saved { pilot.pop() }
        }
        .onChange(of: viewModel.accountDeleted) { deleted in
            if deleted { appWindowManager.accountDeleted() }
        }
    }
}
