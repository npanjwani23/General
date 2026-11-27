import SwiftUI

/// List of schedules, pushed from Settings.
struct SchedulesView: View {
    @EnvironmentObject private var state: AppState
    @State private var alertText: String?

    var body: some View {
        List {
            if !SharedStore.isAppGroupAvailable {
                Section {
                    Label("Schedules are unavailable in this build", systemImage: "exclamationmark.triangle")
                } footer: {
                    Text("The app and its schedule extension need the App Groups capability (group.com.npanjwani.clarity) to share settings. See the README.")
                }
            }

            if !state.isAuthorized {
                Section {
                    Button("Allow Screen Time access") {
                        Task { await state.requestAuthorization() }
                    }
                } footer: {
                    Text("Schedules use Screen Time to lock on time, even when Clarity is closed.")
                }
            }

            Section {
                ForEach(state.schedules) { schedule in
                    NavigationLink {
                        ScheduleEditor(schedule: schedule)
                    } label: {
                        ScheduleRow(schedule: schedule, modeName: state.modeName(schedule.modeID))
                    }
                    .swipeActions(edge: .leading) {
                        Button(schedule.isEnabled ? "Turn off" : "Turn on") {
                            switch state.setScheduleEnabled(schedule.id, !schedule.isEnabled) {
                            case .saved: break
                            case .savedOff(let reason), .rejected(let reason): alertText = reason
                            }
                        }
                        .tint(schedule.isEnabled ? .gray : .orange)
                    }
                }
                .onDelete { state.deleteSchedules(at: $0) }

                NavigationLink {
                    if let mode = state.activeMode {
                        ScheduleEditor(schedule: Schedule(name: "", modeID: mode.id), isNew: true)
                    }
                } label: {
                    Label("New schedule", systemImage: "plus")
                }
                .disabled(!state.canAddSchedule || !state.isAuthorized || !SharedStore.isAppGroupAvailable)
            } footer: {
                Text("A schedule locks its mode when the window starts and unlocks when it ends. "
                     + "Unlocking early takes your tag, and that window then stays off until it ends. "
                     + "Swipe right to turn one off, left to delete.")
            }
        }
        .navigationTitle("Schedules")
        .navigationBarTitleDisplayMode(.inline)
        .localAlert($alertText)
    }
}

private struct ScheduleRow: View {
    let schedule: Schedule
    let modeName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(schedule.name.isEmpty ? "Schedule" : schedule.name)
                if !schedule.isEnabled {
                    Text("Off")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(schedule.timeText) · \(schedule.daysText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Locks \(modeName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .opacity(schedule.isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

/// Create or edit one schedule.
struct ScheduleEditor: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Schedule
    @State private var confirmDelete = false
    @State private var alertText: String?
    @State private var closeAfterAlert = false
    private let isNew: Bool

    init(schedule: Schedule, isNew: Bool = false) {
        _draft = State(initialValue: schedule)
        self.isNew = isNew
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Bedtime, Work hours…", text: $draft.name)
                    .textInputAutocapitalization(.words)
            }

            Section("Mode to lock") {
                Picker("Mode", selection: $draft.modeID) {
                    ForEach(state.modes) { mode in
                        Text(mode.name).tag(mode.id)
                    }
                }
            }

            Section {
                DatePicker("Starts", selection: time(\.startMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: time(\.endMinutes), displayedComponents: .hourAndMinute)
            } header: {
                Text("Time")
            } footer: {
                if let problem = draft.problem {
                    Text(problem).foregroundStyle(.red)
                } else if draft.crossesMidnight {
                    Text("Ends the next morning. Days below are the nights it starts.")
                }
            }

            Section {
                WeekdayPicker(selection: $draft.weekdays)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            } header: {
                Text("Days")
            } footer: {
                Text("If it is inside the window when you save, it can lock right away.")
            }

            Section {
                Toggle("On", isOn: $draft.isEnabled)
            }

            if !isNew {
                Section {
                    Button("Delete schedule", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(isNew ? "New schedule" : "Edit schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                .disabled(draft.problem != nil)
            }
        }
        .localAlert($alertText) {
            if closeAfterAlert { dismiss() }
        }
        .confirmationDialog("Delete this schedule?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let index = state.schedules.firstIndex(where: { $0.id == draft.id }) {
                    state.deleteSchedules(at: IndexSet(integer: index))
                }
                dismiss()
            }
        }
    }

    private func save() {
        switch state.saveSchedule(draft) {
        case .saved:
            dismiss()
        case .savedOff(let reason):
            // Saved but switched off: say why here, then close on OK.
            draft.isEnabled = false
            closeAfterAlert = true
            alertText = reason + " It was saved and turned off."
        case .rejected(let reason):
            alertText = reason
        }
    }

    /// Bridges minutes-after-midnight to the time picker.
    private func time(_ keyPath: WritableKeyPath<Schedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = draft[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                             second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

/// Seven round day toggles, Monday first.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let order = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(on ? Color.orange : Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(on ? Color.black : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

extension View {
    /// A plain OK alert driven by a local optional string.
    func localAlert(_ text: Binding<String?>, onDismiss: @escaping () -> Void = {}) -> some View {
        alert("Clarity", isPresented: Binding(
            get: { text.wrappedValue != nil },
            set: { if !$0 { text.wrappedValue = nil; onDismiss() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(text.wrappedValue ?? "")
        }
    }
}
