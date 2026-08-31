//
//  EventPlayerScreen.swift
//  Sandbox
//

import SwiftUI
import IJKMediaFrameworkWithSSL
import IVSDK

/// Mounts IJKPlayer's own rendering view. The player owns it, so this only
/// hosts it — rebuilding would tear down the decode surface mid-playback.
struct PlayerLayerView: UIViewRepresentable {
    let player: IJKFFMoviePlayerController

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        guard let playerView = player.view else { return container }
        playerView.frame = container.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(playerView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let playerView = player.view else { return }
        // The player is replaced when moving between events, so re-host its
        // view if the one on screen is stale.
        if playerView.superview !== uiView {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            playerView.frame = uiView.bounds
            playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            uiView.addSubview(playerView)
        }
    }
}

struct EventPlayerScreen: View {
    @StateObject var viewModel: EventPlayerViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(spacing: 18) {
                            playerSurface
                            if viewModel.status == .ready { transport }
                            if let context = viewModel.event.context {
                                contextCard(context)
                            }
                            details
                            feedback
                            actions
                        }
                        .padding(.bottom, 28)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let message = viewModel.toastMessage {
                    Text(message)
                        .font(AppFont.body(13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(12)
                        .padding(.bottom, 28)
                        .transition(.opacity)
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.toastMessage) { message in
            guard message != nil, message != "Saving…" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                viewModel.toastMessage = nil
            }
        }
        .onChange(of: viewModel.deleted) { deleted in
            if deleted { pilot.pop() }
        }
        .overlay {
            if viewModel.showDeleteConfirm {
                AppAlertView(shown: $viewModel.showDeleteConfirm,
                             title: "Delete this event?",
                             message: "The clip and its snapshot will be removed. This cannot be undone.",
                             okTitle: "Delete",
                             cancelTitle: "Cancel",
                             onOk: { viewModel.deleteEvent() })
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { pilot.pop() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(AppColors.surface)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.event.primaryTag?.title ?? "Event")
                    .font(AppFont.heading(17))
                    .foregroundColor(AppColors.textPrimary)
                Text(viewModel.event.deviceName ?? "Camera")
                    .font(AppFont.caption(12))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Walk the same list the events screen is showing.
            HStack(spacing: 6) {
                navButton(icon: "chevron.up", enabled: viewModel.hasPrevious) {
                    viewModel.goToPrevious()
                }
                navButton(icon: "chevron.down", enabled: viewModel.hasNext) {
                    viewModel.goToNext()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func navButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(enabled ? AppColors.textPrimary : AppColors.textDisabled)
                .frame(width: 32, height: 32)
                .background(AppColors.surface)
                .clipShape(Circle())
        }
        .disabled(!enabled)
    }

    // MARK: - Player

    private var playerSurface: some View {
        ZStack {
            Color.black

            switch viewModel.status {
            case .loading:
                // The snapshot stands in as a poster frame while the clip
                // loads, so the screen is never a blank rectangle.
                RemoteImage(url: viewModel.snapshotURL, contentMode: .fit)
                ProgressView().tint(.white)

            case .snapshotOnly:
                RemoteImage(url: viewModel.snapshotURL, contentMode: .fit)
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "photo.fill").font(.system(size: 11))
                        Text("Snapshot only — this event has no video")
                            .font(AppFont.caption(11))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(8)
                    .padding(.bottom, 10)
                }

            case .ready:
                if let player = viewModel.player {
                    PlayerLayerView(player: player)
                        .onTapGesture { viewModel.togglePlayPause() }
                }
                if !viewModel.isPlaying {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 54))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(radius: 6)
                        .allowsHitTesting(false)
                }

            case let .failed(reason):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Cannot play this clip")
                        .font(AppFont.medium(15))
                        .foregroundColor(.white)
                    Text(reason)
                        .font(AppFont.caption(11))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: - Transport

    private var transport: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(get: { viewModel.currentTime },
                               set: { viewModel.currentTime = $0 }),
                in: 0...max(viewModel.duration, 0.1),
                onEditingChanged: { editing in
                    viewModel.isScrubbing = editing
                    if !editing { viewModel.seek(to: viewModel.currentTime) }
                }
            )
            .tint(AppColors.primary)

            HStack {
                Text(viewModel.timeText)
                    .font(AppFont.caption(11))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
            }

            HStack(spacing: 14) {
                Spacer()
                transportButton(icon: "gobackward.10") { viewModel.skip(by: -10) }
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(AppColors.primaryGradient)
                        .clipShape(Circle())
                }
                transportButton(icon: "goforward.10") { viewModel.skip(by: 10) }
                Spacer()
                transportButton(icon: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    viewModel.toggleMute()
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func transportButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.textPrimary)
                .frame(width: 44, height: 44)
                .background(AppColors.surface)
                .clipShape(Circle())
        }
    }

    // MARK: - Context

    /// What the AI made of the clip. Given its own card above the raw facts,
    /// because it is usually the answer to the question the user opened the
    /// event to ask.
    private func contextCard(_ context: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.accent)
                Text("WHAT HAPPENED")
                    .font(AppFont.caption(11))
                    .foregroundColor(AppColors.textSecondary)
            }
            Text(context)
                .font(AppFont.body(15))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    // MARK: - Details

    private var details: some View {
        SectionCard(title: "Event") {
            detailRow("When", viewModel.event.startDate.formatted(date: .abbreviated, time: .shortened))
            if let duration = viewModel.event.durationText {
                RowDivider()
                detailRow("Length", duration)
            }
            RowDivider()
            detailRow("Camera", viewModel.event.deviceName ?? "—")
            if !viewModel.event.tags.isEmpty {
                RowDivider()
                HStack(alignment: .top) {
                    Text("Detected")
                        .font(AppFont.body(15))
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    // One event commonly carries several tags — motion plus
                    // whatever the AI recognised in it.
                    HStack(spacing: 6) {
                        ForEach(viewModel.event.tags.prefix(4), id: \.self) { raw in
                            if let tag = EventTag(rawValue: raw) {
                                StatusPill(text: tag.title, color: tag.color)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            if let reading = viewModel.event.sensorReading,
               reading.temperature != nil || reading.humidity != nil {
                RowDivider()
                detailRow("Conditions", conditionsText(reading))
            }
        }
        .padding(.horizontal, 20)
    }

    private func conditionsText(_ reading: EventSensorReading) -> String {
        var parts: [String] = []
        if let temperature = reading.temperature { parts.append("\(temperature)°") }
        if let humidity = reading.humidity { parts.append("\(humidity)% humidity") }
        return parts.joined(separator: " · ")
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(AppFont.body(15))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.medium(14))
                .foregroundColor(AppColors.textPrimary)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    // MARK: - Feedback

    private var feedback: some View {
        SectionCard(title: "Was this right?") {
            HStack(spacing: 12) {
                Text(feedbackPrompt)
                    .font(AppFont.body(14))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if viewModel.feedbackGiven == nil {
                    Button { viewModel.sendFeedback(accurate: true) } label: {
                        Image(systemName: "hand.thumbsup")
                            .foregroundColor(AppColors.success)
                            .frame(width: 40, height: 40)
                            .background(AppColors.success.opacity(0.12))
                            .clipShape(Circle())
                    }
                    Button { viewModel.sendFeedback(accurate: false) } label: {
                        Image(systemName: "hand.thumbsdown")
                            .foregroundColor(AppColors.error)
                            .frame(width: 40, height: 40)
                            .background(AppColors.error.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 20)
    }

    private var feedbackPrompt: String {
        switch viewModel.feedbackGiven {
        case .some(true):  return "You marked this detection as correct."
        case .some(false): return "You marked this detection as wrong."
        case .none:        return "Telling us helps improve detection for this space."
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            SecondaryButton(title: viewModel.canSaveClip ? "Save clip" : "Save snapshot") {
                viewModel.saveToPhotos()
            }
            Button {
                viewModel.showDeleteConfirm = true
            } label: {
                Text("Delete event")
                    .font(AppFont.medium(15))
                    .foregroundColor(AppColors.error)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColors.error.opacity(0.1))
                    .cornerRadius(14)
            }
        }
        .padding(.horizontal, 20)
    }
}
