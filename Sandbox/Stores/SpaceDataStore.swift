//
//  SpaceDataStore.swift
//  Sandbox
//
//  Owns space fetching. Concurrent callers share one in-flight request, which
//  matters because login, signup and the home screen all ask at once.
//

import Foundation
import Combine
import IVSDK

final class SpaceDataStore: ObservableObject {
    private let spaceService: SpaceServiceContract
    private let sharedData: SharedDataStore

    private var pendingCompletions: [([SpaceModel], Error?) -> Void] = []
    private var fetching = false
    private var cancellable: AnyCancellable?

    init(sharedData: SharedDataStore, spaceService: SpaceServiceContract = Factory.spaceService) {
        self.sharedData = sharedData
        self.spaceService = spaceService

        NotificationCenter.default.addObserver(forName: .userLogout, object: nil, queue: .main) { [weak self] _ in
            self?.reset()
        }
    }

    /// A fetch in flight when the account goes away would leave `fetching`
    /// stuck true, and every later request queued behind a completion that
    /// never fires.
    private func reset() {
        cancellable?.cancel()
        cancellable = nil
        fetching = false
        let stranded = pendingCompletions
        pendingCompletions = []
        stranded.forEach { $0([], IVError.requestCancelled) }
    }

    func fetchSpaces() -> IVPublisher<[SpaceModel]> {
        Future<[SpaceModel], Error> { [weak self] promise in
            self?.fetchFromServer { spaces, error in
                if let error {
                    promise(.failure(error))
                } else {
                    promise(.success(spaces))
                }
            }
        }
        .map { ResourceState.success(data: $0) }
        .catch { Just(ResourceState.error(error: $0)) }
        .prepend(.loading)
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    private func fetchFromServer(completion: @escaping ([SpaceModel], Error?) -> Void) {
        pendingCompletions.append(completion)
        guard !fetching else { return }
        fetching = true

        cancellable = spaceService.spaces()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }
                switch result {
                case .loading:
                    break
                case let .success(spaces):
                    self.sharedData.setSpaces(spaces)
                    self.flush(spaces, nil)
                case let .error(error):
                    Logger.debugLog("Space fetch failed:", error.localizedDescription)
                    self.flush([], error)
                @unknown default:
                    break
                }
            }
    }

    private func flush(_ spaces: [SpaceModel], _ error: Error?) {
        fetching = false
        let completions = pendingCompletions
        pendingCompletions = []
        completions.forEach { $0(spaces, error) }
    }

    func createSpace(name: String, address: AddressModel) -> IVPublisher<Void> {
        spaceService.createSpace(request: .init(name: name, address: address))
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func updateSpace(id: String, name: String, address: AddressModel) -> IVPublisher<Void> {
        spaceService.updateSpace(spaceId: id, request: .init(name: name, address: address))
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
