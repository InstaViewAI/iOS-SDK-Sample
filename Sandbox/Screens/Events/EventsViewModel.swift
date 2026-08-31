//
//  EventsViewModel.swift
//  Sandbox
//

import SwiftUI
import Combine
import IVSDK

final class EventsViewModel: ObservableObject {

    @Published var result = ResultWrapper()
    @Published var selectedIds: Set<String> = []
    @Published var isSelecting = false
    @Published var showDeleteConfirm = false

    let eventsDataStore: EventsDataStore
    private let sharedData: SharedDataStore

    private var cancellable: AnyCancellable?
    private var deleteCancellable: AnyCancellable?
    private var storeCancellables = Set<AnyCancellable>()

    init(sharedData: SharedDataStore, eventsDataStore: EventsDataStore) {
        self.sharedData = sharedData
        self.eventsDataStore = eventsDataStore

        // Republish the stores' changes as our own — a nested ObservableObject
        // does not propagate to the view observing this one.
        eventsDataStore.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        sharedData.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
    }

    var events: [EventModel] { eventsDataStore.events }
    var devices: [DeviceModel] { sharedData.devices }
    var hasMore: Bool { eventsDataStore.hasMore }
    var isLoadingPage: Bool { eventsDataStore.isLoadingPage }

    var deviceFilter: String? {
        get { eventsDataStore.deviceFilter }
        set { eventsDataStore.deviceFilter = newValue; load(refresh: true) }
    }

    var tagFilter: EventTag? {
        get { eventsDataStore.tagFilter }
        set { eventsDataStore.tagFilter = newValue; load(refresh: true) }
    }

    /// Events grouped into day sections, newest day first.
    var sections: [(title: String, events: [EventModel])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.startDate) }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (title: sectionTitle(for: $0.key), events: $0.value.sorted { $0.startTime > $1.startTime }) }
    }

    private func sectionTitle(for day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: day)
    }

    func load(refresh: Bool = false) {
        cancellable = eventsDataStore.fetchEvents(refresh: refresh)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    // Paging must not raise the full-screen loader — the list
                    // is already on screen and shows its own footer spinner.
                    if refresh, self?.events.isEmpty == true {
                        self?.result.update(data: .loading)
                    }
                case .success:
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    /// Called as the last row appears.
    func loadNextPageIfNeeded(currentEvent: EventModel) {
        guard hasMore, !isLoadingPage, currentEvent.id == events.last?.id else { return }
        load()
    }

    // MARK: - Selection

    func toggleSelection(_ event: EventModel) {
        if selectedIds.contains(event.id) {
            selectedIds.remove(event.id)
        } else {
            selectedIds.insert(event.id)
        }
    }

    func endSelection() {
        isSelecting = false
        selectedIds = []
    }

    func deleteSelected() {
        let ids = Array(selectedIds)
        guard !ids.isEmpty else { return }
        result.update(data: .loading)

        deleteCancellable = eventsDataStore.deleteEvents(ids: ids)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.endSelection()
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}
