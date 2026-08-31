//
//  TimezonePickerSheet.swift
//  Sandbox
//
//  The monitoring centre records events against the property's local time, so
//  the timezone is part of the protected address rather than a display
//  preference. The list comes from the backend — it publishes the set it will
//  accept, and the phone's own timezone database is not interchangeable with
//  it.
//

import SwiftUI
import Combine
import IVSDK

final class TimezonePickerViewModel: ObservableObject {

    @Published private(set) var timezones: [TimezoneModel] = []
    @Published var searchText = ""
    @Published var result = ResultWrapper()

    private let store: ProSecurityStore
    private var cancellable: AnyCancellable?

    init(store: ProSecurityStore) {
        self.store = store
    }

    var filtered: [TimezoneModel] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return timezones }
        return timezones.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    func load() {
        guard timezones.isEmpty else { return }
        result.update(data: .loading)
        cancellable = store.loadTimezones()
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(list):
                    self?.timezones = list
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}

struct TimezonePickerSheet: View {
    @StateObject var viewModel: TimezonePickerViewModel
    let selected: TimezoneModel?
    let onSelect: (TimezoneModel) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    header

                    AppTextField(placeholder: "Search timezones", text: $viewModel.searchText)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    if viewModel.filtered.isEmpty {
                        EmptyStateView(icon: "clock.badge.questionmark",
                                       title: "No timezones",
                                       message: viewModel.timezones.isEmpty
                                           ? "The list could not be loaded. Close and try again."
                                           : "Nothing matches that search.")
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.filtered.enumerated()), id: \.element.code) { index, zone in
                                    Button {
                                        onSelect(zone)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(zone.name)
                                                    .font(AppFont.body(15))
                                                    .foregroundColor(AppColors.textPrimary)
                                                    .multilineTextAlignment(.leading)
                                                Text(zone.code)
                                                    .font(AppFont.caption(11))
                                                    .foregroundColor(AppColors.textSecondary)
                                            }
                                            Spacer()
                                            if zone.code == selected?.code {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(AppColors.primary)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .frame(minHeight: 58)
                                        .contentShape(Rectangle())
                                    }
                                    if index < viewModel.filtered.count - 1 { RowDivider() }
                                }
                            }
                            .background(AppColors.surface)
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
    }

    private var header: some View {
        HStack {
            Text("Timezone")
                .font(AppFont.heading(19))
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            Button("Close") { dismiss() }
                .font(AppFont.medium(15))
                .foregroundColor(AppColors.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
