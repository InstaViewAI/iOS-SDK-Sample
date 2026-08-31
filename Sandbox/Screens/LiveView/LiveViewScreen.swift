//
//  LiveViewScreen.swift
//  Sandbox
//
//  Full-screen live video with the controls that sit around it.
//

import SwiftUI
import IVSDK

/// Bridges the SDK's UIKit video surface into SwiftUI. The view is created and
/// owned by the SDK's LiveViewModel, so this only mounts it — never rebuilds
/// it, which would tear down the render target mid-stream.
struct WebRTCVideoView: UIViewRepresentable {
    let view: IVVideoView

    func makeUIView(context: Context) -> IVVideoView { view }
    func updateUIView(_ uiView: IVVideoView, context: Context) {}
}

struct LiveViewScreen: View {
    @StateObject var viewModel: CameraLiveViewModel

    @EnvironmentObject private var pilot: UIPilot<Destination>
    @SwiftUI.Environment(\.scenePhase) private var scenePhase
    @State private var controlsVisible = true
    @State private var hideControlsTask: DispatchWorkItem?
    /// Whether this screen is the one on screen. A pushed screen sits above it
    /// but still receives scene-phase changes, and returning to the foreground
    /// must not reconnect a stream nobody is looking at.
    @State private var isOnScreen = false

    var body: some View {
        BaseView(content: {
            ZStack {
                Color.black.ignoresSafeArea()

                videoLayer
                    .onTapGesture { toggleControls() }

                if !viewModel.status.isConnected {
                    overlay
                }

                if controlsVisible || !viewModel.status.isConnected {
                    chrome
                }

                if let message = viewModel.toastMessage {
                    toast(message)
                }
            }
        }, result: $viewModel.result)
        .onAppear {
            isOnScreen = true
            AppDelegate.orientation = .all
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.connect()
            scheduleHideControls()
        }
        .onDisappear {
            isOnScreen = false
            AppDelegate.orientation = .portrait
            UIApplication.shared.isIdleTimerDisabled = false
            hideControlsTask?.cancel()
            viewModel.disconnect()
        }
        .onChange(of: scenePhase) { phase in
            // Backgrounding drops the WebRTC session anyway; disconnecting
            // deliberately stops the camera holding a session slot open.
            if phase == .background { viewModel.disconnect() }
            if phase == .active, isOnScreen, viewModel.status == .idle {
                viewModel.connect()
            }
        }
        .onChange(of: viewModel.toastMessage) { message in
            guard message != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                viewModel.toastMessage = nil
            }
        }
    }

    // MARK: - Video

    @ViewBuilder
    private var videoLayer: some View {
        // A multi-lens camera returns one view per lens; stack them so the
        // whole field of view is visible rather than only the first.
        let views = viewModel.videoViews
        if views.isEmpty {
            Color.black
        } else if views.count == 1 {
            WebRTCVideoView(view: views[0])
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
        } else {
            VStack(spacing: 2) {
                ForEach(views, id: \.viewId) { view in
                    WebRTCVideoView(view: view)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
            }
        }
    }

    // MARK: - Connection overlay

    @ViewBuilder
    private var overlay: some View {
        switch viewModel.status {
        case .connecting:
            VStack(spacing: 14) {
                ProgressView().tint(.white).scaleEffect(1.3)
                Text("Connecting to \(viewModel.device.displayName)…")
                    .font(AppFont.body(14))
                    .foregroundColor(.white.opacity(0.85))
                if viewModel.device.isBatteryPowered {
                    Text("Battery cameras take a few seconds to wake up.")
                        .font(AppFont.caption(11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

        case .failed:
            VStack(spacing: 16) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.white.opacity(0.7))
                Text("Could not reach the camera")
                    .font(AppFont.heading(17))
                    .foregroundColor(.white)
                Text("Check that it still has power and a good connection.")
                    .font(AppFont.body(13))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                SecondaryButton(title: "Try again") { viewModel.retry() }
                    .frame(maxWidth: 200)
            }
            .padding(28)

        case let .unavailable(reason):
            VStack(spacing: 16) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.white.opacity(0.7))
                Text(reason)
                    .font(AppFont.body(15))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                SecondaryButton(title: "Camera settings") {
                    isOnScreen = false
                    viewModel.disconnect()
                    pilot.push(.cameraSettings(device: viewModel.device))
                }
                .frame(maxWidth: 220)
            }
            .padding(28)

        case .idle, .connected:
            EmptyView()
        }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack {
            topBar
            Spacer()
            if viewModel.supportsPTZ && viewModel.status.isConnected {
                ptzPad
            }
            bottomBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                isOnScreen = false
                viewModel.disconnect()
                pilot.pop()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.device.displayName)
                    .font(AppFont.medium(15))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.status.isConnected ? AppColors.success : AppColors.warning)
                        .frame(width: 6, height: 6)
                    Text(viewModel.status.isConnected ? "Live" : "Connecting")
                        .font(AppFont.caption(10))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.45))
            .cornerRadius(10)

            Spacer()

            if viewModel.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(AppColors.error).frame(width: 7, height: 7)
                    Text(viewModel.recordingText)
                        .font(AppFont.caption(11))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
            }

            Button {
                // Pushing covers this screen without reliably disappearing it,
                // so the stream is stopped here rather than hoping onDisappear
                // runs.
                isOnScreen = false
                viewModel.disconnect()
                pilot.push(.cameraSettings(device: viewModel.device))
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            controlButton(icon: viewModel.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                          active: viewModel.audioEnabled) {
                viewModel.toggleAudio()
            }

            controlButton(icon: "camera.fill") {
                viewModel.captureSnapshot()
            }

            controlButton(icon: viewModel.isRecording ? "stop.circle.fill" : "record.circle",
                          active: viewModel.isRecording,
                          tint: AppColors.error) {
                viewModel.toggleRecording()
            }

            controlButton(icon: viewModel.micEnabled ? "mic.fill" : "mic.slash.fill",
                          active: viewModel.micEnabled,
                          tint: AppColors.error) {
                viewModel.toggleMic()
            }

        }
        .disabled(!viewModel.status.isConnected)
        .opacity(viewModel.status.isConnected ? 1 : 0.4)
    }

    private func controlButton(icon: String,
                               active: Bool = false,
                               tint: Color = AppColors.primary,
                               action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            scheduleHideControls()
        }) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(active ? tint : Color.black.opacity(0.45))
                .clipShape(Circle())
        }
    }

    private var ptzPad: some View {
        VStack(spacing: 6) {
            ptzButton(.up, icon: "chevron.up")
            HStack(spacing: 6) {
                ptzButton(.left, icon: "chevron.left")
                Button {
                    viewModel.resetPosition()
                    scheduleHideControls()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
                ptzButton(.right, icon: "chevron.right")
            }
            ptzButton(.down, icon: "chevron.down")
        }
        .padding(.bottom, 14)
    }

    private func ptzButton(_ direction: CameraLiveViewModel.PTZDirection, icon: String) -> some View {
        Button {
            viewModel.move(direction)
            scheduleHideControls()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(Color.black.opacity(0.45))
                .clipShape(Circle())
        }
    }

    private func toast(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(AppFont.body(13))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
                .padding(.bottom, 110)
        }
        .transition(.opacity)
    }

    // MARK: - Auto-hiding controls

    private func toggleControls() {
        withAnimation { controlsVisible.toggle() }
        if controlsVisible { scheduleHideControls() }
    }

    /// Controls fade out so they do not sit on top of the footage. Any
    /// interaction restarts the clock.
    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        guard viewModel.status.isConnected else { return }
        let task = DispatchWorkItem {
            withAnimation { controlsVisible = false }
        }
        hideControlsTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
    }
}
