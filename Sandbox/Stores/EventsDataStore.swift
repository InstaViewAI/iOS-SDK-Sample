//
//  EventsDataStore.swift
//  Sandbox
//
//  Paged event history for the current space, with optional device and tag
//  filters. The backend sorts by start time descending.
//

import Foundation
import Combine
import IVSDK

final class EventsDataStore: ObservableObject {
    static let pageSize = 25

    @Published private(set) var events: [EventModel] = []
    @Published private(set) var totalCount = 0
    @Published var isLoadingPage = false

    /// Filter state the events screen binds to directly.
    @Published var deviceFilter: String? { didSet { resetPaging() } }
    @Published var tagFilter: EventTag? { didSet { resetPaging() } }

    private let spaceService: SpaceServiceContract
    private let sharedData: SharedDataStore
    private var cancellable: AnyCancellable?

    init(sharedData: SharedDataStore, spaceService: SpaceServiceContract = Factory.spaceService) {
        self.sharedData = sharedData
        self.spaceService = spaceService

        NotificationCenter.default.addObserver(forName: .userLogout, object: nil, queue: .main) { [weak self] _ in
            self?.events = []
            self?.totalCount = 0
        }
    }

    var hasMore: Bool { events.count < totalCount }

    private func resetPaging() {
        events = []
        totalCount = 0
    }

    /// `refresh` starts from the top; otherwise the next page is appended.
    @discardableResult
    func fetchEvents(refresh: Bool = false) -> IVPublisher<[EventModel]> {
        let spaceId = sharedData.currentSpaceId
        guard !spaceId.isEmpty else {
            return Just(.success(data: [])).eraseToAnyPublisher()
        }
        if refresh { resetPaging() }

        var queryItems: [QueryItem] = [
            .init(key: .skip, value: .equal(value: "\(refresh ? 0 : events.count)")),
            .init(key: .limit, value: .equal(value: "\(Self.pageSize)"))
        ]
        if let deviceFilter {
            queryItems.append(.init(key: .deviceId, value: .equal(value: deviceFilter)))
        }
        if let tagFilter {
            queryItems.append(.init(key: .tags, value: .in(value: [tagFilter.rawValue])))
        }

        isLoadingPage = true

        let publisher = spaceService
            .events(spaceId: spaceId,
                    queryItems: queryItems,
                    sortItem: SortItem(descending: [.startTime]))
            .receive(on: DispatchQueue.main)
            .map { [weak self] state -> ResourceState<[EventModel]> in
                switch state {
                case .loading:
                    return .loading
                case let .success(page):
                    guard let self else { return .success(data: page.items) }
                    self.isLoadingPage = false
                    self.totalCount = page.totalCount
                    // Guard against a page arriving twice — a pull-to-refresh
                    // landing on top of an in-flight next-page request.
                    let known = Set(self.events.map(\.id))
                    self.events += page.items.filter { !known.contains($0.id) }
                    return .success(data: self.events)
                case let .error(error):
                    self?.isLoadingPage = false
                    return .error(error: error)
                @unknown default:
                    return .success(data: [])
                }
            }
            .eraseToAnyPublisher()

        cancellable = publisher.sink { _ in }
        return publisher
    }

    func deleteEvents(ids: [String]) -> IVPublisher<Void> {
        let spaceId = sharedData.currentSpaceId
        return spaceService.deleteEvents(spaceId: spaceId, request: .init(eventId: ids))
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] state in
                if case .success = state {
                    self?.events.removeAll { ids.contains($0.id) }
                    self?.totalCount -= ids.count
                }
            })
            .eraseToAnyPublisher()
    }
}
