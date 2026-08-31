//
//  EventsScreen.swift
//  Sandbox
//
//  Event history for the current space, filterable by camera and detection
//  type, paged as the user scrolls.
//

import SwiftUI
import IVSDK

struct EventsScreen: View {
    @StateObject var viewModel: EventsViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            VStack(spacing: 0) {
                header
                filterBar

                if viewModel.events.isEmpty && !viewModel.isLoadingPage {
                    EmptyStateView(icon: "clock.badge.questionmark",
                                   title: "No events yet",
                                   message: "Recordings from your cameras will appear here as they happen.")
                    .frame(maxHeight: .infinity)
                } else {
                    list
                }
            }
        }, result: $viewModel.result)
        .onAppear {
            if viewModel.events.isEmpty { viewModel.load(refresh: true) }
        }
        .overlay {
            if viewModel.showDeleteConfirm {
                AppAlertView(shown: $viewModel.showDeleteConfirm,
                             title: "Delete \(viewModel.selectedIds.count) event\(viewModel.selectedIds.count == 1 ? "" : "s")?",
                             message: "This cannot be undone.",
                             okTitle: "Delete",
                             cancelTitle: "Cancel", onOk: {
                    viewModel.deleteSelected()
                })
            }
        }
    }

    private var header: some View {
        HStack {
            Text(viewModel.isSelecting ? "\(viewModel.selectedIds.count) selected" : "Events")
                .font(AppFont.heading(20))
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            if viewModel.isSelecting {
                Button("Delete") { viewModel.showDeleteConfirm = true }
                    .font(AppFont.medium(14))
                    .foregroundColor(viewModel.selectedIds.isEmpty ? AppColors.textDisabled : AppColors.error)
                    .disabled(viewModel.selectedIds.isEmpty)
                Button("Done") { viewModel.endSelection() }
                    .font(AppFont.medium(14))
                    .foregroundColor(AppColors.primary)
                    .padding(.leading, 10)
            } else if !viewModel.events.isEmpty {
                Button("Select") { viewModel.isSelecting = true }
                    .font(AppFont.medium(14))
                    .foregroundColor(AppColors.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All",
                           selected: viewModel.deviceFilter == nil && viewModel.tagFilter == nil) {
                    viewModel.deviceFilter = nil
                    viewModel.tagFilter = nil
                }

                ForEach([EventTag.person, .vehicle, .animal, .doorbellRing], id: \.rawValue) { tag in
                    FilterChip(title: tag.title,
                               icon: tag.icon,
                               selected: viewModel.tagFilter == tag) {
                        viewModel.tagFilter = viewModel.tagFilter == tag ? nil : tag
                    }
                }

                ForEach(viewModel.devices, id: \.id) { device in
                    FilterChip(title: device.displayName,
                               selected: viewModel.deviceFilter == device.id) {
                        viewModel.deviceFilter = viewModel.deviceFilter == device.id ? nil : device.id
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.sections, id: \.title) { section in
                    Section {
                        VStack(spacing: 0) {
                            ForEach(Array(section.events.enumerated()), id: \.element.id) { index, event in
                                Button {
                                    if viewModel.isSelecting {
                                        viewModel.toggleSelection(event)
                                    } else {
                                        pilot.push(.eventPlayer(event: event))
                                    }
                                } label: {
                                    EventRow(event: event,
                                             selectable: viewModel.isSelecting,
                                             selected: viewModel.selectedIds.contains(event.id))
                                }
                                .onAppear { viewModel.loadNextPageIfNeeded(currentEvent: event) }

                                if index < section.events.count - 1 { RowDivider() }
                            }
                        }
                        .background(AppColors.surface)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
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

                if viewModel.isLoadingPage {
                    ProgressView()
                        .tint(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { viewModel.load(refresh: true) }
    }
}

struct FilterChip: View {
    let title: String
    var icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11))
                }
                Text(title).font(AppFont.medium(13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundColor(selected ? .white : AppColors.textSecondary)
            .background(selected ? AppColors.primary : AppColors.surface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? Color.clear : AppColors.border, lineWidth: 1))
        }
    }
}

struct EventRow: View {
    let event: EventModel
    var compact = false
    var selectable = false
    var selected = false

    var body: some View {
        HStack(spacing: 12) {
            if selectable {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? AppColors.primary : AppColors.textDisabled)
            }

            RemoteImage(url: event.snapshotURL)
                .frame(width: compact ? 52 : 64, height: compact ? 40 : 48)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let tag = event.primaryTag {
                        Image(systemName: tag.icon)
                            .font(.system(size: 11))
                            .foregroundColor(tag.color)
                        Text(tag.title)
                            .font(AppFont.medium(14))
                            .foregroundColor(AppColors.textPrimary)
                    } else {
                        Text("Event")
                            .font(AppFont.medium(14))
                            .foregroundColor(AppColors.textPrimary)
                    }
                }
                Text(event.deviceName ?? "Camera")
                    .font(AppFont.caption(12))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)

                // The compact row on the home screen has no space for this.
                if !compact, let context = event.context {
                    // Shown in full — a truncated description usually loses the
                    // detail that made it worth reading. Rows vary in height as
                    // a result.
                    Text(context)
                        .font(AppFont.caption(11))
                        .foregroundColor(AppColors.textSecondary.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(event.startDate.relativeEventLabel)
                    .font(AppFont.caption(11))
                    .foregroundColor(AppColors.textSecondary)
                if let duration = event.durationText {
                    Text(duration)
                        .font(AppFont.caption(10))
                        .foregroundColor(AppColors.textDisabled)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
