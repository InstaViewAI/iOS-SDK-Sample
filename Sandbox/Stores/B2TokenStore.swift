//
//  B2TokenStore.swift
//  Sandbox
//
//  Event clips and snapshots live in per-device storage buckets that are not
//  publicly readable. Playing one means appending a short-lived bucket token to
//  its URL as an `Authorization` query parameter.
//
//  Tokens come back for the whole space at once and are keyed by device and
//  bucket, so they are fetched once and cached rather than re-requested per
//  event — an event list can hold dozens of clips from the same camera.
//

import Foundation
import Combine
import IVSDK

final class B2TokenStore: ObservableObject {

    /// The backend issues these with a 24-hour life. Refreshing a little early
    /// avoids handing AVPlayer a URL that expires mid-playback.
    private static let tokenLifetime: TimeInterval = 23 * 60 * 60

    private var tokensBySpace: [String: [B2AuthTokenModel]] = [:]
    private var fetchedAt: [String: TimeInterval] = [:]

    private let spaceService: SpaceServiceContract
    private var cancellable: AnyCancellable?
    private var pending: [(Bool) -> Void] = []
    private var isFetching = false

    init(spaceService: SpaceServiceContract = Factory.spaceService) {
        self.spaceService = spaceService

        NotificationCenter.default.addObserver(forName: .userLogout, object: nil, queue: .main) { [weak self] _ in
            self?.tokensBySpace = [:]
            self?.fetchedAt = [:]
        }
    }

    private func isFresh(_ spaceId: String) -> Bool {
        guard let time = fetchedAt[spaceId] else { return false }
        return Date().timeIntervalSince1970 - time < Self.tokenLifetime
    }

    /// Resolves a playable URL for an event's video or snapshot. Returns nil
    /// when the event has no media of that kind, or no token can be obtained.
    func authorizedURL(for event: EventModel,
                       snapshot: Bool = false,
                       completion: @escaping (URL?) -> Void) {
        let raw = snapshot ? event.snapshotUrl : event.videoUrl
        guard let raw, !raw.isEmpty else {
            completion(nil)
            return
        }

        token(spaceId: event.spaceId, deviceId: event.deviceId, bucketName: event.bucketName) { token in
            guard let token else {
                completion(nil)
                return
            }
            completion(Self.applying(token: token, to: raw))
        }
    }

    /// The bucket token on its own, for callers that need to sign more than
    /// one URL — an HLS playlist has to sign each of its segments too.
    func token(for event: EventModel, completion: @escaping (String?) -> Void) {
        token(spaceId: event.spaceId,
              deviceId: event.deviceId,
              bucketName: event.bucketName,
              completion: completion)
    }

    /// Replaces any existing Authorization parameter rather than appending a
    /// second one — a re-authorised URL is built from a URL that may already
    /// carry a stale token.
    static func applying(token: String, to urlString: String) -> URL? {
        guard var components = URLComponents(string: urlString) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "Authorization" }
        items.append(URLQueryItem(name: "Authorization", value: token))
        components.queryItems = items
        return components.url
    }

    private func token(spaceId: String,
                       deviceId: String,
                       bucketName: String,
                       completion: @escaping (String?) -> Void) {
        if isFresh(spaceId), let match = match(spaceId, deviceId, bucketName) {
            completion(match)
            return
        }
        fetch(spaceId: spaceId) { [weak self] success in
            completion(success ? self?.match(spaceId, deviceId, bucketName) : nil)
        }
    }

    private func match(_ spaceId: String, _ deviceId: String, _ bucketName: String) -> String? {
        let tokens = tokensBySpace[spaceId] ?? []
        // Prefer the token issued for this exact device and bucket; fall back
        // to a bucket-only match, which is what a space-wide token looks like.
        return tokens.first { $0.deviceId == deviceId && $0.bucketName == bucketName }?.authToken
            ?? tokens.first { $0.bucketName == bucketName }?.authToken
    }

    /// Concurrent callers share one request — opening a list of events would
    /// otherwise fire a token fetch per row.
    private func fetch(spaceId: String, completion: @escaping (Bool) -> Void) {
        pending.append(completion)
        guard !isFetching else { return }
        isFetching = true

        cancellable = spaceService.getB2AuthToken(spaceId: spaceId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(tokens):
                    self.tokensBySpace[spaceId] = tokens
                    self.fetchedAt[spaceId] = Date().timeIntervalSince1970
                    self.flush(true)
                case let .error(error):
                    Logger.debugLog("B2 token fetch failed:", error.localizedDescription)
                    self.flush(false)
                @unknown default:
                    break
                }
            }
    }

    private func flush(_ success: Bool) {
        isFetching = false
        let callbacks = pending
        pending = []
        callbacks.forEach { $0(success) }
    }
}
