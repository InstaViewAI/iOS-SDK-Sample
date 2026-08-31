//
//  BaseView.swift
//  Sandbox
//
//  Wraps a screen so a bound ResultWrapper drives the shared loader and the
//  error dialog. Screens then only describe their content.
//

import SwiftUI
import Combine
import IVSDK

private var activeLoaderId = UUID().uuidString

struct BaseView<Content: View>: View {
    private let content: Content
    @Binding var result: ResultWrapper
    var errorTapped: (() -> Void)?

    @EnvironmentObject private var appWindowManager: AppWindowManager
    @State private var viewId = UUID().uuidString

    init(@ViewBuilder content: () -> Content,
         result: Binding<ResultWrapper>,
         errorTapped: (() -> Void)? = nil) {
        self.content = content()
        self._result = result
        self.errorTapped = errorTapped
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .center) {
                // A cancelled request is the app's own doing — never surface it.
                if let error = result.error as? IVError, case .requestCancelled = error {
                    EmptyView()
                } else if result.isError {
                    AppAlertView(shown: $result.isError,
                                 title: "Something went wrong",
                                 message: result.error?.localizedDescription,
                                 okTitle: "OK", onOk: {
                        errorTapped?()
                    })
                }
            }
            .onChange(of: result.isLoading) { isLoading in
                // Track which screen raised the loader so a screen that
                // disappears mid-flight cannot dismiss someone else's spinner.
                if isLoading {
                    viewId = UUID().uuidString
                    activeLoaderId = viewId
                }
                appWindowManager.isLoading = isLoading
            }
            .onDisappear {
                if viewId == activeLoaderId {
                    appWindowManager.isLoading = false
                    result.isLoading = false
                }
            }
    }
}
