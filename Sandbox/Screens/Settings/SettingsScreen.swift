//
//  SettingsScreen.swift
//  Sandbox
//
//  The settings tab: account, the current space, and the camera list as a
//  second way into camera settings.
//

import SwiftUI
import IVSDK

struct SettingsScreen: View {
    @ObservedObject var sharedData: SharedDataStore

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @EnvironmentObject private var appWindowManager: AppWindowManager

    @AppStorage(AppStorageKey.userDetails.rawValue) private var user: UserModel?
    @State private var showLogoutConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(AppFont.heading(20))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 18) {
                    accountCard

                    SectionCard(title: "Account") {
                        SettingsRow(title: "Desktop access (VMS)", icon: "display") {
                            pilot.push(.vms)
                        }
                        RowDivider()
                        SettingsRow(title: "My account", icon: "person.circle") {
                            pilot.push(.myAccount)
                        }
                        RowDivider()
                        SettingsRow(title: "Change password", icon: "key") {
                            pilot.push(.changePassword)
                        }
                    }

                    if let space = sharedData.currentSpace {
                        SectionCard(title: "Space") {
                            SettingsRow(title: "Edit space",
                                        value: space.name,
                                        icon: "house") {
                                pilot.push(.spaceScreen(space: space))
                            }
                            RowDivider()
                            SettingsRow(title: "Add a camera", icon: "plus.viewfinder") {
                                pilot.push(.cameraPermission(screenFrom: .home))
                            }
                            RowDivider()
                            SettingsRow(title: "Professional monitoring",
                                        icon: "shield.lefthalf.filled") {
                                sharedData.tabSelection = .security
                            }
                        }
                    }

                    if !sharedData.devices.isEmpty {
                        SectionCard(title: "Cameras") {
                            ForEach(Array(sharedData.devices.enumerated()), id: \.element.id) { index, device in
                                SettingsRow(title: device.displayName,
                                            value: device.statusText,
                                            icon: "video") {
                                    pilot.push(.cameraSettings(device: device))
                                }
                                if index < sharedData.devices.count - 1 { RowDivider() }
                            }
                        }
                    }

                    SectionCard(title: "About") {
                        SettingsRow(title: "Version",
                                    value: AppConfig.appVersion,
                                    showsChevron: false) {}
                        RowDivider()
                        SettingsRow(title: "Environment",
                                    value: AppEnvironment.environment.rawValue,
                                    showsChevron: false) {}
                        RowDivider()
                        SettingsRow(title: "Partner",
                                    value: AppEnvironment.partner,
                                    showsChevron: false) {}
                    }

                    Button {
                        showLogoutConfirm = true
                    } label: {
                        Text("Sign out")
                            .font(AppFont.medium(15))
                            .foregroundColor(AppColors.error)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColors.error.opacity(0.1))
                            .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .overlay {
            if showLogoutConfirm {
                AppAlertView(shown: $showLogoutConfirm,
                             title: "Sign out?",
                             message: "You will need to sign in again to reach your cameras.",
                             okTitle: "Sign out",
                             cancelTitle: "Cancel", onOk: {
                    signOut()
                })
            }
        }
    }

    private var accountCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.primarySoft)
                    .frame(width: 52, height: 52)
                Text(initials)
                    .font(AppFont.heading(18))
                    .foregroundColor(AppColors.primary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(user?.name.fullName ?? "—")
                    .font(AppFont.medium(16))
                    .foregroundColor(AppColors.textPrimary)
                Text(user?.email ?? "")
                    .font(AppFont.caption(12))
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
    }

    private var initials: String {
        let first = user?.name.first.prefix(1) ?? ""
        let last = user?.name.last.prefix(1) ?? ""
        let combined = "\(first)\(last)".uppercased()
        return combined.isEmpty ? "?" : combined
    }

    private func signOut() {
        appWindowManager.signOut()
    }
}
