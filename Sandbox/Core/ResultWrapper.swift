//
//  ResultWrapper.swift
//  Sandbox
//
//  Collapses the SDK's ResourceState into the three flags a screen actually
//  binds to, so view models never hand raw publisher states to the UI.
//

import SwiftUI
import Combine
import IVSDK

struct ResultWrapper {
    enum State {
        case loading
        case success
        case error(error: Error)
    }

    var isLoading = false
    var isError = false
    var isSuccess = false
    var error: Error?

    /// `hideLoader: false` keeps the spinner up through a success, for screens
    /// that chain straight into another request.
    mutating func update(data: State, hideLoader: Bool = true) {
        switch data {
        case .loading:
            isLoading = true
            isError = false
            isSuccess = false
            error = nil
        case .success:
            isLoading = !hideLoader
            isError = false
            isSuccess = true
            error = nil
        case let .error(error):
            isLoading = false
            isError = true
            isSuccess = false
            self.error = error
        }
    }
}

extension ResourceState {
    var mapBaseResult: ResultWrapper.State {
        switch self {
        case .loading: return .loading
        case .success: return .success
        case let .error(error): return .error(error: error)
        @unknown default: return .success
        }
    }
}
