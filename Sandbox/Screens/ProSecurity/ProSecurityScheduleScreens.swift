//
//  ProSecurityScheduleScreens.swift
//  Sandbox
//
//  Step 5 (optional): arm and disarm on a repeating weekly schedule.
//
//  Each entry is one action — arm or disarm — at one time, on a set of
//  weekdays. Arming and disarming are separate entries rather than a range,
//  because the two halves are usually wanted on different days.
//

import SwiftUI
import Combine
import IVSDK

extension ScheduledAlarmModel {
    var timeText: String {
        String(format: "%02d:%02d", timeSlot.hour, timeSlot.minute)
    }

    /// The API numbers days 0–6 starting on Sunday.
    var daysText: String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        if days.count == 7 { return "Every day" }
        if Set(days) == Set([1, 2, 3, 4, 5]) { return "Weekdays" }
        if Set(days) == Set([0, 6]) { return "Weekends" }
        return days.sorted().compactMap { names.indices.contains($0) ? names[$0] : nil }.joined(separator: ", ")
    }
}

// MARK: - Schedule list

final class SecurityScheduleViewModel: SecurityStepViewModel {
    @Published var schedules: [ScheduledAlarmModel] = []
    @Published var pendingDeleteId: String?

    private var loadCancellable: AnyCancellable?
    private var deleteCancellable: AnyCancellable?
    private var completeCancellable: AnyCancellable?

    func load() {
        result.update(data: .loading)
        loadCancellable = store.loadSchedules()
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case let .success(response):
                    self?.schedules = response.items
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    func delete(id: String) {
        result.update(data: .loading)
        deleteCancellable = store.deleteSchedules(ids: [id])
            .sink { [weak self] state in
                switch state {
                case .loading:
                    break
                case .success:
                    self?.schedules.removeAll { $0.id == id }
                    self?.result.update(data: .success)
                case let .error(error):
                    self?.result.update(data: .error(error: error))
                @unknown default:
                    break
                }
            }
    }

    /// Marks the step done. Schedules are optional, so this is reachable with
    /// an empty list — and the schedules themselves were already written by
    /// their own endpoint, so there is nothing to PATCH here.
    func finishStep() {
        completeStep(.scheduleSystem)
    }
}

struct SecurityScheduleScreen: View {
    @StateObject var viewModel: SecurityScheduleViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    private var isSetup: Bool { viewModel.advancesSetup }

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: "Schedule") { pilot.pop() }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Arm it automatically")
                                    .font(AppFont.title(26))
                                    .foregroundColor(AppColors.textPrimary)
                                Text("Most people arm overnight and disarm in the morning. You can still arm and disarm by hand at any time.")
                                    .font(AppFont.body(15))
                                    .foregroundColor(AppColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if viewModel.schedules.isEmpty {
                                EmptyStateView(icon: "calendar.badge.plus",
                                               title: "No schedules yet",
                                               message: "Add one to arm or disarm the system automatically.")
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(viewModel.schedules) { schedule in
                                        scheduleRow(schedule)
                                    }
                                }
                            }

                            SecondaryButton(title: "Add a schedule") {
                                pilot.push(.securityEditSchedule(schedule: nil,
                                                                 screenFrom: viewModel.screenFrom))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }

                    if isSetup {
                        VStack(spacing: 10) {
                            PrimaryButton(title: "Continue") { viewModel.finishStep() }
                            LinkButton(title: "Skip for now") { viewModel.finishStep() }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
        }, result: $viewModel.result)
        .onAppear { viewModel.load() }
        .overlay {
            if let id = viewModel.pendingDeleteId {
                AppAlertView(shown: Binding(get: { viewModel.pendingDeleteId != nil },
                                            set: { if !$0 { viewModel.pendingDeleteId = nil } }),
                             title: "Delete this schedule?",
                             okTitle: "Delete",
                             cancelTitle: "Cancel",
                             onOk: {
                    viewModel.delete(id: id)
                    viewModel.pendingDeleteId = nil
                })
            }
        }
        .onChange(of: viewModel.advanced) { advanced in
            guard advanced else { return }
            pilot.finishSecurityStep(screenFrom: viewModel.screenFrom,
                                     andPush: viewModel.nextDestination)
        }
    }

    private func scheduleRow(_ schedule: ScheduledAlarmModel) -> some View {
        let arming = schedule.type == .arm
        return Button {
            pilot.push(.securityEditSchedule(schedule: schedule, screenFrom: viewModel.screenFrom))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: arming ? "lock.shield.fill" : "lock.open.fill")
                    .font(.system(size: 17))
                    .foregroundColor(arming ? AppColors.error : AppColors.success)
                    .frame(width: 42, height: 42)
                    .background((arming ? AppColors.error : AppColors.success).opacity(0.14))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(arming ? "Arm" : "Disarm") at \(schedule.timeText)")
                        .font(AppFont.medium(15))
                        .foregroundColor(AppColors.textPrimary)
                    Text(schedule.daysText)
                        .font(AppFont.caption(12))
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Button {
                    viewModel.pendingDeleteId = schedule.id
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.error)
                        .padding(8)
                }
            }
            .padding(12)
            .background(AppColors.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        }
    }
}

// MARK: - Add / edit a schedule

final class SecurityEditScheduleViewModel: SecurityStepViewModel {
    @Published var isArming = true
    @Published var time = Date()
    @Published var selectedDays: Set<Int> = [1, 2, 3, 4, 5]
    @Published var saved = false

    let existing: ScheduledAlarmModel?
    private var saveCancellable: AnyCancellable?

    /// Sunday-first, matching the API's day numbering.
    static let dayNames = ["S", "M", "T", "W", "T", "F", "S"]

    init(store: ProSecurityStore, screenFrom: ScreenFrom, schedule: ScheduledAlarmModel?) {
        self.existing = schedule
        super.init(store: store, screenFrom: screenFrom)

        if let schedule {
            isArming = schedule.type == .arm
            selectedDays = Set(schedule.days)
            var components = DateComponents()
            components.hour = schedule.timeSlot.hour
            components.minute = schedule.timeSlot.minute
            time = Calendar.current.date(from: components) ?? Date()
        }
    }

    var isEditing: Bool { existing != nil }
    var canSubmit: Bool { !selectedDays.isEmpty }

    func toggleDay(_ day: Int) {
        if selectedDays.contains(day) { selectedDays.remove(day) } else { selectedDays.insert(day) }
    }

    func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let request = ScheduledAlarmRequest(
            days: selectedDays.sorted(),
            timeSlot: .init(hour: components.hour ?? 0, minute: components.minute ?? 0),
            type: (isArming ? AlarmActionType.arm : .disarm).rawValue,
            // The schedule fires in the property's timezone, not the phone's.
            timezone: profile?.timezone ?? TimeZone.current.identifier
        )
        result.update(data: .loading)

        let publisher = existing.map { store.updateSchedule(id: $0.id, request: request) }
            ?? store.addSchedule(request)

        saveCancellable = publisher.sink { [weak self] state in
            switch state {
            case .loading:
                break
            case .success:
                self?.result.update(data: .success)
                self?.saved = true
            case let .error(error):
                self?.result.update(data: .error(error: error))
            @unknown default:
                break
            }
        }
    }
}

struct SecurityEditScheduleScreen: View {
    @StateObject var viewModel: SecurityEditScheduleViewModel
    @EnvironmentObject private var pilot: UIPilot<Destination>

    var body: some View {
        BaseView(content: {
            ScreenBackground {
                VStack(spacing: 0) {
                    NavBar(title: viewModel.isEditing ? "Edit schedule" : "New schedule") { pilot.pop() }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            SectionCard(title: "Action") {
                                HStack(spacing: 0) {
                                    actionTab(title: "Arm", selected: viewModel.isArming) {
                                        viewModel.isArming = true
                                    }
                                    actionTab(title: "Disarm", selected: !viewModel.isArming) {
                                        viewModel.isArming = false
                                    }
                                }
                                .padding(6)
                            }

                            SectionCard(title: "Time") {
                                DatePicker("At",
                                           selection: $viewModel.time,
                                           displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .tint(AppColors.primary)
                                    .foregroundColor(AppColors.textPrimary)
                                    .padding(.horizontal, 16)
                                    .frame(height: 54)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("REPEAT")
                                    .font(AppFont.caption(11))
                                    .foregroundColor(AppColors.textSecondary)
                                    .padding(.leading, 4)
                                HStack(spacing: 8) {
                                    ForEach(0..<7, id: \.self) { day in
                                        let selected = viewModel.selectedDays.contains(day)
                                        Button {
                                            viewModel.toggleDay(day)
                                        } label: {
                                            Text(SecurityEditScheduleViewModel.dayNames[day])
                                                .font(AppFont.medium(14))
                                                .foregroundColor(selected ? .white : AppColors.textSecondary)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 42)
                                                .background(selected ? AppColors.primary : AppColors.surface)
                                                .cornerRadius(10)
                                                .overlay(RoundedRectangle(cornerRadius: 10)
                                                    .stroke(selected ? Color.clear : AppColors.border, lineWidth: 1))
                                        }
                                    }
                                }
                            }

                            InfoNote(text: "Scheduled arming still respects your exit delay, so you are not locked out the moment it fires.")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }

                    PrimaryButton(title: viewModel.isEditing ? "Save changes" : "Add schedule",
                                  enabled: viewModel.canSubmit) {
                        viewModel.save()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }, result: $viewModel.result)
        .onChange(of: viewModel.saved) { saved in
            if saved { pilot.pop() }
        }
    }

    private func actionTab(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.medium(15))
                .foregroundColor(selected ? .white : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(selected ? AppColors.primary : Color.clear)
                .cornerRadius(10)
        }
    }
}
