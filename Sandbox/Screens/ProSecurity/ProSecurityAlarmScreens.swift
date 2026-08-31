//
//  ProSecurityAlarmScreens.swift
//  Sandbox
//
//  The log of everything the security system has done.
//

import SwiftUI
import Combine
import IVSDK

// MARK: - Security log

final class SecurityLogsViewModel: ObservableObject {
    @Published var result = ResultWrapper()
    @Published var filter: SecurityLogType?

    let store: ProSecurityStore
    private var cancellable: AnyCancellable?
    private var storeCancellable: AnyCancellable?

    init(store: ProSecurityStore) {
        self.store = store
        storeCancellable = store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    var logs: [SecurityLogsModel] {
        guard let filter else { return store.securityLogs }
        return store.securityLogs.filter { $0.logType == filter }
    }

    /// Grouped by day, newest first.
    var sections: [(title: String, logs: [SecurityLogsModel])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.date) }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (title: Self.sectionTitle($0.key), logs: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }

    private static func sectionTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: day)
    }

    func load() {
        if store.securityLogs.isEmpty { result.update(data: .loading) }
        cancellable = store.loadSecurityLogs(limit: 100)
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }
}

struct SecurityLogsScreen: View {
    @StateObject var viewModel: SecurityLogsViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    private let filters: [SecurityLogType] = [.armed, .disarmed, .dispatch, .agentCall]

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Security log") { pilot.pop() }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "All", selected: viewModel.filter == nil) {
                                viewModel.filter = nil
                            }
                            ForEach(filters, id: \.rawValue) { type in
                                FilterChip(title: type.title,
                                           icon: type.icon,
                                           selected: viewModel.filter == type) {
                                    viewModel.filter = viewModel.filter == type ? nil : type
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 12)

                    if viewModel.logs.isEmpty {
                        EmptyStateView(icon: "list.bullet.rectangle",
                                       title: "Nothing logged",
                                       message: "Arming, disarming and alarm activity will show up here.")
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                                ForEach(viewModel.sections, id: \.title) { section in
                                    Section {
                                        VStack(spacing: 0) {
                                            ForEach(Array(section.logs.enumerated()), id: \.element.id) { index, log in
                                                SecurityLogRow(log: log)
                                                if index < section.logs.count - 1 { RowDivider() }
                                            }
                                        }
                                        .background(AppColors.surface)
                                        .cornerRadius(16)
                                        .overlay(RoundedRectangle(cornerRadius: 16)
                                            .stroke(AppColors.border, lineWidth: 1))
                                        .padding(.horizontal, 20)
                                    } header: {
                                        Text(section.title)
                                            .font(AppFont.caption(11))
                                            .foregroundColor(AppColors.textSecondary)
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(AppColors.background.opacity(0.95))
                                    }
                                }
                            }
                            .padding(.bottom, 24)
                        }
                        .refreshable { viewModel.load() }
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
    }
}
