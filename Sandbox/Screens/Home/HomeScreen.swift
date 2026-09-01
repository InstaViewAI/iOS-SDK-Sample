//
//  HomeScreen.swift
//  Sandbox
//
//  Cameras in the current space, plus a strip of the latest events.
//

import SwiftUI
import IVSDK

struct HomeScreen: View {
    @StateObject var viewModel: HomeViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        BaseView(content: {
            VStack(spacing: 0) {
                header

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if viewModel.devices.isEmpty && viewModel.devicesLoaded {
                            emptyState
                        } else {
                            if !viewModel.pendingSetupDevices.isEmpty {
                                pendingSetupSection
                            }
                            cameraGrid
                            if !viewModel.recentEvents.isEmpty {
                                recentEventsSection
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .refreshable { viewModel.load(refresh: true) }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
        .overlay {
            if viewModel.showSpacePicker { spacePicker }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.showSpacePicker = true
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.spaceName)
                            .font(AppFont.heading(20))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)
                        Text("\(viewModel.onlineCount) of \(viewModel.devices.count) online")
                            .font(AppFont.caption(12))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    if viewModel.spaces.count > 1 {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }

            Spacer()

            Button {
                pilot.push(viewModel.addCameraDestination)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(AppColors.primaryGradient)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Cameras

    private var cameraGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(viewModel.devices.filter { $0.authStatus == .activated }, id: \.id) { device in
                CameraCard(device: device,
                           onTap: { pilot.push(.liveView(device: device)) },
                           onSettings: { pilot.push(.cameraSettings(device: device)) })
            }
        }
    }

    private var pendingSetupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FINISH SETUP")
                .font(AppFont.caption(11))
                .foregroundColor(AppColors.warning)

            ForEach(viewModel.pendingSetupDevices, id: \.id) { device in
                Button {
                    // Resume where pairing left off rather than restarting.
                    pilot.push(.cameraAuthEmail(deviceId: device.id, screenFrom: .home))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.displayName)
                                .font(AppFont.medium(15))
                                .foregroundColor(AppColors.textPrimary)
                            Text("Waiting to be activated")
                                .font(AppFont.caption(12))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textDisabled)
                    }
                    .padding(14)
                    .background(AppColors.warning.opacity(0.1))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.warning.opacity(0.35), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Events strip

    private var recentEventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT ACTIVITY")
                    .font(AppFont.caption(11))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                LinkButton(title: "See all") {
                    viewModel.sharedData.tabSelection = .events
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.recentEvents.enumerated()), id: \.element.id) { index, event in
                    Button {
                        pilot.push(.eventPlayer(event: event))
                    } label: {
                        EventRow(event: event, compact: true)
                    }
                    if index < viewModel.recentEvents.count - 1 {
                        RowDivider()
                    }
                }
            }
            .background(AppColors.surface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        }
    }

    // MARK: - Empty / picker

    private var emptyState: some View {
        EmptyStateView(icon: "video.badge.plus",
                       title: "No cameras yet",
                       message: "Add your first camera to start seeing live video and events in this space.",
                       actionTitle: "Add a camera") {
            pilot.push(viewModel.addCameraDestination)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var spacePicker: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { viewModel.showSpacePicker = false }

            VStack(spacing: 0) {
                Text("Switch space")
                    .font(AppFont.heading(17))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.vertical, 16)
                RowDivider()

                ForEach(viewModel.spaces, id: \.id) { space in
                    Button {
                        viewModel.select(space: space)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(space.name)
                                    .font(AppFont.body(15))
                                    .foregroundColor(AppColors.textPrimary)
                                if space.address.displayAddress.isNotEmpty {
                                    Text(space.address.displayAddress)
                                        .font(AppFont.caption(12))
                                        .foregroundColor(AppColors.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if space.id == viewModel.sharedData.currentSpaceId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(AppColors.primary)
                            }
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                    }
                    RowDivider()
                }
            }
            .background(AppColors.surfaceRaised)
            .cornerRadius(18)
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Camera card

struct CameraCard: View {
    let device: DeviceModel
    let onTap: () -> Void
    let onSettings: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    RemoteImage(url: device.snapshotURL)
                        .frame(height: 108)
                        .clipped()
                        // Offline cameras show their last snapshot dimmed,
                        // which reads better than an empty tile.
                        .opacity(device.isOnline ? 1 : 0.4)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(device.statusColor)
                            .frame(width: 6, height: 6)
                        Text(device.statusText)
                            .font(AppFont.caption(10))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(6)
                    .padding(8)

                    // A play badge, so it is obvious the tile opens live video
                    // rather than a still.
                    if device.isOnline {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(radius: 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(device.displayName)
                            .font(AppFont.medium(14))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button(action: onSettings) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        if device.isBatteryPowered, let battery = device.deviceState.batteryPercentage {
                            Label("\(Int(battery))%", systemImage: batteryIcon(battery))
                        }
                        if device.is4GCamera {
                            Label("4G", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        if device.hasFirmwareUpdate {
                            Label("Update", systemImage: "arrow.down.circle")
                                .foregroundColor(AppColors.warning)
                        }
                    }
                    .font(AppFont.caption(10))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                }
                .padding(10)
            }
            .background(AppColors.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func batteryIcon(_ percentage: CGFloat) -> String {
        switch percentage {
        case ..<20: return "battery.25"
        case ..<60: return "battery.50"
        default: return "battery.100"
        }
    }
}
