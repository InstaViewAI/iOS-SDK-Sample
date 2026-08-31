//
//  EventPlayerViewModel.swift
//  Sandbox
//
//  Playback for a recorded event.
//
//  Playback goes through IJKPlayer (FFmpeg), not AVPlayer, and it has to.
//  These cameras record HEVC inside MPEG-TS segments. Apple's HLS spec requires
//  HEVC to be carried in fMP4, so AVFoundation cannot decode this combination —
//  it does not error, it simply stalls, which looks like a spinner that never
//  resolves. FFmpeg handles it, which is why the production app made the same
//  choice.
//
//  Not every event has video. Snapshot events carry only a still, so the screen
//  has to handle "there is nothing to play" as a normal case.
//
//  Clips are served as HLS. That matters more than it sounds: the playlist can
//  be fetched with a bucket token in its query string, but the segment URIs
//  inside it are relative, so the player requests them unsigned and the bucket
//  answers 401 (NSURLErrorUserAuthenticationRequired, -1013). The playlist has
//  to be fetched, rewritten with a signed absolute URL per segment, and handed
//  to the player as a local file. The production app does the same thing.
//

import SwiftUI
import Combine
import AVFoundation
import Photos
import IJKMediaFrameworkWithSSL
import IVSDK

final class EventPlayerViewModel: ObservableObject {

    enum PlaybackStatus: Equatable {
        case loading
        case snapshotOnly
        case ready
        case failed(reason: String)
    }

    @Published private(set) var status: PlaybackStatus = .loading
    @Published private(set) var event: EventModel

    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    /// True while the user drags the scrubber, so time observations do not
    /// fight the thumb for control of the position.
    @Published var isScrubbing = false

    @Published var snapshotURL: URL?
    @Published var toastMessage: String?
    @Published var showDeleteConfirm = false
    @Published var deleted = false
    @Published var feedbackGiven: Bool?
    @Published var result = ResultWrapper()

    private(set) var player: IJKFFMoviePlayerController?

    private let eventsDataStore: EventsDataStore
    private let tokenStore: B2TokenStore
    private let spaceService: SpaceServiceContract
    private let systemService: SystemServiceContract

    private var progressTimer: Timer?
    private var feedbackCancellable: AnyCancellable?
    private var deleteCancellable: AnyCancellable?
    private var playlistCancellable: AnyCancellable?

    /// Kept so the temporary rewritten playlist can be cleaned up.
    private var localPlaylistURL: URL?
    /// Kept so the same token can be sent as an HTTP header.
    private var currentToken: String?

    init(event: EventModel,
         eventsDataStore: EventsDataStore,
         tokenStore: B2TokenStore,
         spaceService: SpaceServiceContract = Factory.spaceService,
         systemService: SystemServiceContract = Factory.systemService) {
        self.event = event
        self.eventsDataStore = eventsDataStore
        self.tokenStore = tokenStore
        self.spaceService = spaceService
        self.systemService = systemService
        self.feedbackGiven = event.accurate
    }

    deinit {
        teardown()
    }

    // MARK: - Neighbours

    /// The player can walk the same list the events screen is showing.
    private var siblings: [EventModel] { eventsDataStore.events }

    private var index: Int? { siblings.firstIndex { $0.id == event.id } }

    var hasPrevious: Bool {
        guard let index else { return false }
        return index > 0
    }

    var hasNext: Bool {
        guard let index else { return false }
        return index < siblings.count - 1
    }

    func goToPrevious() {
        guard let index, index > 0 else { return }
        switchTo(siblings[index - 1])
    }

    func goToNext() {
        guard let index, index < siblings.count - 1 else { return }
        switchTo(siblings[index + 1])
    }

    private func switchTo(_ event: EventModel) {
        teardown()
        self.event = event
        self.feedbackGiven = event.accurate
        currentTime = 0
        duration = 0
        snapshotURL = nil
        status = .loading
        load()
    }

    // MARK: - Loading

    func load() {
        // The snapshot doubles as the poster frame while the video loads, so
        // it is resolved for every event, not only stills.
        tokenStore.authorizedURL(for: event, snapshot: true) { [weak self] url in
            self?.snapshotURL = url
        }

        guard let videoUrl = event.videoUrl, !videoUrl.isEmpty else {
            status = .snapshotOnly
            return
        }

        status = .loading
        resolvePlayableURL(videoUrl: videoUrl) { [weak self] url in
            guard let self else { return }
            guard let url else {
                self.status = .failed(reason: "Could not get permission to play this clip.")
                return
            }
            self.startPlayback(url: url)
        }
    }

    // MARK: - HLS

    private var isHLS: Bool {
        (event.videoUrl ?? "").components(separatedBy: "?").first?.hasSuffix(".m3u8") ?? false
    }

    /// Plain files can be played straight from a signed URL. HLS needs the
    /// playlist rewritten first.
    private func resolvePlayableURL(videoUrl: String, completion: @escaping (URL?) -> Void) {
        tokenStore.token(for: event) { [weak self] token in
            guard let self, let token else {
                completion(nil)
                return
            }
            self.currentToken = token
            guard self.isHLS else {
                completion(B2TokenStore.applying(token: token, to: videoUrl))
                return
            }
            self.buildLocalPlaylist(videoUrl: videoUrl, token: token, completion: completion)
        }
    }

    private func buildLocalPlaylist(videoUrl: String,
                                    token: String,
                                    completion: @escaping (URL?) -> Void) {
        // Strip any existing query so the directory used to resolve relative
        // segment names is clean.
        guard var components = URLComponents(string: videoUrl) else {
            completion(nil)
            return
        }
        components.query = nil
        components.fragment = nil
        guard let playlistURL = components.url else {
            completion(nil)
            return
        }

        playlistCancellable = systemService
            .eventM3U8(url: playlistURL.absoluteString + "?Authorization=\(token)")
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(data):
                    guard let text = String(data: data, encoding: .utf8) else {
                        completion(nil)
                        return
                    }
                    let rewritten = Self.rewrite(playlist: text,
                                                 baseURL: playlistURL.deletingLastPathComponent(),
                                                 token: token)
                    completion(self.writePlaylist(rewritten))
                case let .error(error):
                    Logger.debugLog("Playlist fetch failed:", error.localizedDescription)
                    completion(nil)
                @unknown default:
                    break
                }
            }
    }

    /// Signs every media URI in the playlist and makes it absolute. Assumes a
    /// single-level media playlist, which is what these events are — a master
    /// playlist pointing at further playlists would need this applied again to
    /// each child.
    static func rewrite(playlist: String, baseURL: URL, token: String) -> String {
        var lines: [String] = []
        var hasEndList = false

        for line in playlist.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#EXT-X-ENDLIST") { hasEndList = true }

            // Tags and blank lines pass through untouched; everything else is
            // a media URI that needs signing.
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                lines.append(line)
                continue
            }

            let absolute = trimmed.hasPrefix("http")
                ? trimmed
                : baseURL.appendingPathComponent(trimmed).absoluteString
            lines.append(B2TokenStore.applying(token: token, to: absolute)?.absoluteString ?? absolute)
        }

        // Without ENDLIST the player treats the playlist as a live stream: no
        // duration, and no seeking. Every event we can open has finished.
        if !hasEndList {
            lines.append("#EXT-X-ENDLIST")
        }
        return lines.joined(separator: "\n")
    }

    /// The extension matters — AVFoundation picks its parser from it.
    private func writePlaylist(_ contents: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("event-\(event.id).m3u8")
        try? FileManager.default.removeItem(at: url)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            localPlaylistURL = url
            return url
        } catch {
            Logger.debugLog("Could not write playlist:", error.localizedDescription)
            return nil
        }
    }

    /// Playback should be audible with the ring switch on silent — a clip is
    /// something the user deliberately opened, unlike an incidental sound.
    /// Live view is torn down before this screen appears, so there is no
    /// WebRTC session to contend with.
    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Logger.debugLog("Audio session activation failed:", error.localizedDescription)
        }
    }

    private func deactivateAudioSession() {
        // Handing the session back lets other audio resume rather than staying
        // ducked behind an app that is no longer playing anything.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startPlayback(url: URL) {
        activateAudioSession()

        let options = IJKFFOptions.byDefault()
        // The rewritten playlist already signs every segment, but sending the
        // token as a header too covers anything the rewrite did not reach.
        if let token = currentToken {
            options?.setFormatOptionValue("Authorization: \(token)\r\n", forKey: "headers")
        }
        // The playlist is served from a local file while its segments are
        // remote, so both protocol families have to be allowed.
        options?.setFormatOptionValue("file,http,https,tcp,tls,ts,crypto", forKey: "protocol_whitelist")
        // Hardware decode. FFmpeg still handles demuxing the TS container,
        // which is the part AVFoundation cannot do for HEVC.
        options?.setPlayerOptionIntValue(1, forKey: "videotoolbox")

        let controller = IJKFFMoviePlayerController(contentURL: url, with: options)
        controller?.scalingMode = .aspectFit
        controller?.shouldAutoplay = false
        controller?.playbackVolume = isMuted ? 0 : 1
        controller?.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        player = controller

        observePlayerNotifications()
        controller?.prepareToPlay()
    }

    private func observePlayerNotifications() {
        let center = NotificationCenter.default
        for name in [Notification.Name.IJKMPMoviePlayerLoadStateDidChange,
                     .IJKMPMoviePlayerPlaybackStateDidChange,
                     .IJKMPMoviePlayerPlaybackDidFinish] {
            center.removeObserver(self, name: name, object: nil)
        }

        center.addObserver(self,
                           selector: #selector(loadStateChanged),
                           name: .IJKMPMoviePlayerLoadStateDidChange,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(playbackStateChanged),
                           name: .IJKMPMoviePlayerPlaybackStateDidChange,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(playbackFinished),
                           name: .IJKMPMoviePlayerPlaybackDidFinish,
                           object: nil)
    }

    @objc private func loadStateChanged() {
        guard let player else { return }
        // `playthroughOK` means enough is buffered to play without stalling.
        guard player.loadState.contains(.playthroughOK) || player.loadState.contains(.playable) else {
            return
        }
        guard status != .ready else { return }

        duration = player.duration.isFinite && player.duration > 0 ? player.duration : 0
        status = .ready
        player.play()
        isPlaying = true
        startProgressTimer()
    }

    @objc private func playbackStateChanged() {
        guard let player else { return }
        switch player.playbackState {
        case .playing:
            isPlaying = true
        case .paused, .stopped:
            isPlaying = false
        default:
            break
        }
    }

    @objc private func playbackFinished(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[IJKMPMoviePlayerPlaybackDidFinishReasonUserInfoKey] as? NSNumber,
              let reason = IJKMPMovieFinishReason(rawValue: reasonValue.intValue) else { return }

        switch reason {
        case .playbackEnded:
            isPlaying = false
            currentTime = duration
            stopProgressTimer()
        case .playbackError:
            status = .failed(reason: "This clip could not be decoded.")
            isPlaying = false
            stopProgressTimer()
        default:
            break
        }
    }

    /// IJK has no periodic time observer, so position is polled.
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let player = self.player, !self.isScrubbing else { return }
            self.currentTime = player.currentPlaybackTime
            if self.duration == 0, player.duration.isFinite, player.duration > 0 {
                self.duration = player.duration
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func teardown() {
        stopProgressTimer()
        for name in [Notification.Name.IJKMPMoviePlayerLoadStateDidChange,
                     .IJKMPMoviePlayerPlaybackStateDidChange,
                     .IJKMPMoviePlayerPlaybackDidFinish] {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
        }
        player?.shutdown()
        player?.view.removeFromSuperview()
        player = nil
        isPlaying = false
        deactivateAudioSession()

        if let localPlaylistURL {
            try? FileManager.default.removeItem(at: localPlaylistURL)
            self.localPlaylistURL = nil
        }
    }

    func stop() {
        teardown()
    }

    // MARK: - Transport

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            stopProgressTimer()
        } else {
            // Replaying after the end has to rewind first, or playback resumes
            // at the end and immediately finishes again.
            if duration > 0, currentTime >= duration - 0.1 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
            startProgressTimer()
        }
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, min(seconds, duration))
        currentTime = clamped
        player.currentPlaybackTime = clamped
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func toggleMute() {
        isMuted.toggle()
        player?.playbackVolume = isMuted ? 0 : 1
    }

    var timeText: String {
        "\(Self.clock(currentTime)) / \(Self.clock(duration))"
    }

    private static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Actions

    /// What "save" can offer depends on how the clip is served.
    ///
    /// A plain file is downloaded and handed to Photos. An HLS clip cannot be:
    /// it is a playlist plus hundreds of segments, and Photos wants a single
    /// movie. Turning one into an mp4 needs remuxing — the production app
    /// shells out to FFmpeg for exactly this — which is out of scope here, so
    /// the snapshot is saved instead and the difference is stated rather than
    /// silently producing a broken file.
    var canSaveClip: Bool {
        event.videoUrl?.isEmpty == false && !isHLS
    }

    func saveToPhotos() {
        guard canSaveClip else {
            if isHLS {
                toastMessage = "Saved the snapshot — this clip is streamed and cannot be exported."
            }
            saveSnapshotToPhotos()
            return
        }
        tokenStore.authorizedURL(for: event) { [weak self] url in
            guard let url else {
                self?.toastMessage = "Could not get permission to download this clip."
                return
            }
            self?.download(url: url)
        }
    }

    private func download(url: URL) {
        toastMessage = "Saving…"
        URLSession.shared.downloadTask(with: url) { [weak self] location, _, error in
            guard let location else {
                DispatchQueue.main.async {
                    Logger.debugLog("Clip download failed:", error?.localizedDescription ?? "unknown")
                    self?.toastMessage = "Could not download the clip."
                }
                return
            }
            // The temporary file is removed the moment the handler returns, so
            // it has to be moved somewhere durable before Photos reads it.
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(self?.event.id ?? UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                DispatchQueue.main.async { self?.toastMessage = "Could not save the clip." }
                return
            }
            self?.addToLibrary(video: destination)
        }.resume()
    }

    private func addToLibrary(video url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self?.toastMessage = "Allow photo access in Settings to save clips."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { saved, error in
                if let error { Logger.debugLog("Photo library save failed:", error.localizedDescription) }
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    self?.toastMessage = saved ? "Clip saved to your photos." : "Could not save the clip."
                }
            }
        }
    }

    private func saveSnapshotToPhotos() {
        guard let snapshotURL else {
            toastMessage = "There is nothing to save for this event."
            return
        }
        URLSession.shared.dataTask(with: snapshotURL) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { self?.toastMessage = "Could not download the snapshot." }
                return
            }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async {
                    guard status == .authorized || status == .limited else {
                        self?.toastMessage = "Allow photo access in Settings to save snapshots."
                        return
                    }
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    // Leave an HLS explanation in place if one was just set.
                    if self?.toastMessage?.hasPrefix("Saved the snapshot") != true {
                        self?.toastMessage = "Snapshot saved to your photos."
                    }
                }
            }
        }.resume()
    }

    /// Tells the backend whether the detection was right. This is what trains
    /// the per-space detection model, so it is worth surfacing.
    func sendFeedback(accurate: Bool) {
        feedbackGiven = accurate
        feedbackCancellable = spaceService
            .setEventFeedback(eventId: event.id,
                              spaceId: event.spaceId,
                              request: .init(accurate: accurate))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .success:
                    self?.toastMessage = "Thanks — that helps improve detection."
                case let .error(error):
                    self?.feedbackGiven = nil
                    Logger.debugLog("Feedback failed:", error.localizedDescription)
                default:
                    break
                }
            }
    }

    func deleteEvent() {
        result.update(data: .loading)
        deleteCancellable = eventsDataStore.deleteEvents(ids: [event.id])
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.result.update(data: .success)
                    self?.deleted = true
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}
