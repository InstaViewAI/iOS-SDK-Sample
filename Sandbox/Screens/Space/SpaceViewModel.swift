//
//  SpaceViewModel.swift
//  Sandbox
//
//  A space is the container everything else hangs off — devices, events,
//  subscriptions. An account with none cannot show a home screen, which is why
//  this sits between verification and the tab bar.
//

import SwiftUI
import Combine
import IVSDK

final class SpaceViewModel: ObservableObject {

    @Published var name = ""
    @Published var street = ""
    @Published var city = ""
    @Published var state = ""
    @Published var postalCode = ""
    @Published var country = CountryOption.current

    @Published var result = ResultWrapper()
    @Published var destination: Destination?
    @Published var finished = false

    @AppStorage(AppStorageKey.userDetails.rawValue) var user: UserModel?
    @AppStorage(AppStorageKey.isLoggedIn.rawValue) var isLoggedIn: Bool?

    /// nil when creating, populated when editing from settings.
    let existingSpace: SpaceModel?

    private let sharedData: SharedDataStore
    private let spaceDataStore: SpaceDataStore
    private var saveCancellable: AnyCancellable?
    private var spaceCancellable: AnyCancellable?

    init(space: SpaceModel?, sharedData: SharedDataStore, spaceDataStore: SpaceDataStore) {
        self.existingSpace = space
        self.sharedData = sharedData
        self.spaceDataStore = spaceDataStore
        applyInitialValues()
    }

    var isEditing: Bool { existingSpace != nil }

    private func applyInitialValues() {
        name = existingSpace?.name ?? ""
        street = existingSpace?.address.street ?? ""
        city = existingSpace?.address.city ?? ""
        state = existingSpace?.address.state ?? ""
        postalCode = existingSpace?.address.postalCode ?? ""
        if let code = existingSpace?.address.country,
           let match = CountryOption.all.first(where: { $0.code == code }) {
            country = match
        }
    }

    /// Address is optional when creating — the only thing a new space really
    /// needs is somewhere to put cameras. Renaming an existing one does
    /// require a name.
    var canSubmit: Bool {
        isEditing ? name.isNotEmpty : true
    }

    private var address: AddressModel {
        AddressModel(street: street.trim,
                     city: city.trim,
                     state: state.trim,
                     country: country.code,
                     postalCode: postalCode.trim)
    }

    func save() {
        // Fall back to a friendly default rather than blocking on a name the
        // user did not care to give.
        let spaceName = name.isNotEmpty ? name.trim : "\(user?.name.first ?? "My") Home"
        result.update(data: .loading)

        let publisher = isEditing
            ? spaceDataStore.updateSpace(id: existingSpace?.id ?? "", name: spaceName, address: address)
            : spaceDataStore.createSpace(name: spaceName, address: address)

        saveCancellable = publisher.sink { [weak self] state in
            switch state {
            case .loading:
                break
            case .success:
                // Keep the loader up: creating returns no body, so the space
                // list has to be re-read before there is anything to show.
                self?.result.update(data: .success, hideLoader: false)
                self?.reloadSpaces()
            case let .error(error):
                self?.result.update(data: .error(error: error))
            @unknown default:
                break
            }
        }
    }

    private func reloadSpaces() {
        spaceCancellable = spaceDataStore.fetchSpaces()
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loading:
                    break
                case let .success(spaces):
                    if let created = spaces.first(where: { SpaceRoleType(rawValue: $0.role ?? "") == .owner }) {
                        self.sharedData.select(space: created)
                    }
                    self.isLoggedIn = true
                    self.result.update(data: .success)
                    if self.isEditing {
                        self.finished = true
                    } else {
                        self.destination = .appTabBar
                    }
                case let .error(error):
                    self.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}
