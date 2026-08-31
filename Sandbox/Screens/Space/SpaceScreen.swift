//
//  SpaceScreen.swift
//  Sandbox
//

import SwiftUI

struct SpaceScreen: View {
    @StateObject var viewModel: SpaceViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    // Creating the first space is not skippable, so no back
                    // button — editing one is reached from settings and is.
                    NavBar(title: viewModel.isEditing ? "Edit space" : "") {
                        viewModel.isEditing ? pilot.pop() : ()
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if !viewModel.isEditing {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Name your space")
                                        .font(AppFont.title(30))
                                        .foregroundColor(AppColors.textPrimary)
                                    Text("A space groups the cameras in one place — a home, an office, a cabin. You can add more later.")
                                        .font(AppFont.body(15))
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }

                            AppTextField(placeholder: "Space name",
                                         text: $viewModel.name,
                                         autocapitalization: .words)

                            VStack(alignment: .leading, spacing: 12) {
                                Text("ADDRESS (OPTIONAL)")
                                    .font(AppFont.caption(11))
                                    .foregroundColor(AppColors.textSecondary)

                                AppTextField(placeholder: "Street",
                                             text: $viewModel.street,
                                             autocapitalization: .words)
                                HStack(spacing: 12) {
                                    AppTextField(placeholder: "City",
                                                 text: $viewModel.city,
                                                 autocapitalization: .words)
                                    AppTextField(placeholder: "State",
                                                 text: $viewModel.state,
                                                 autocapitalization: .words)
                                }
                                HStack(spacing: 12) {
                                    AppTextField(placeholder: "ZIP",
                                                 text: $viewModel.postalCode,
                                                 keyboard: .numbersAndPunctuation)
                                    Menu {
                                        ForEach(CountryOption.all) { option in
                                            Button(option.name) { viewModel.country = option }
                                        }
                                    } label: {
                                        HStack {
                                            Text(viewModel.country.name)
                                                .font(AppFont.body(15))
                                                .foregroundColor(AppColors.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
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
                                }
                            }

                            PrimaryButton(title: viewModel.isEditing ? "Save changes" : "Continue",
                                          enabled: viewModel.canSubmit) {
                                viewModel.save()
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
        }, result: $viewModel.result)
        .onChange(of: viewModel.destination) { destination in
            guard destination != nil else { return }
            pilot.changeRoot(.appTabBar)
            viewModel.destination = nil
        }
        .onChange(of: viewModel.finished) { finished in
            if finished { pilot.pop() }
        }
    }
}
