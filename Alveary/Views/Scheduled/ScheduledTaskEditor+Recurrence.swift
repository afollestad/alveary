import SwiftUI

struct ScheduledTaskEditorRecurrenceSection: View {
    @Binding var draft: ScheduledTaskEditorDraft

    var body: some View {
        SettingsFormSection("Schedule") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Repeats", horizontalControlSizing: .intrinsic) {
                    Picker("Repeats", selection: $draft.recurrenceKind) {
                        ForEach(ScheduledTaskRecurrence.Kind.allCases, id: \.rawValue) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .labelsHidden()
                }
            }

            recurrenceFields

            SettingsFormRow(showsDivider: false) {
                SettingsResponsiveControlRow(
                    "Time zone",
                    helpText: "Calendar schedules keep this local wall-clock time when daylight saving time changes."
                ) {
                    Picker("Time zone", selection: $draft.timeZoneIdentifier) {
                        ForEach(timeZoneIdentifiers, id: \.self) { identifier in
                            Text(identifier).tag(identifier)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    @ViewBuilder private var recurrenceFields: some View {
        switch draft.recurrenceKind {
        case .once:
            SettingsFormRow {
                SettingsResponsiveControlRow("Run at") {
                    DatePicker(
                        "Run at",
                        selection: $draft.onceOccurrenceAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(\.timeZone, selectedTimeZone)
                    .datePickerStyle(.field)
                    .labelsHidden()
                }
            }
        case .interval:
            SettingsFormRow {
                SettingsResponsiveControlRow("Interval", horizontalControlSizing: .intrinsicInline) {
                    HStack(spacing: 6) {
                        Text("Every")
                        TextField("Minutes", value: intervalMinutesBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .accessibilityLabel("Interval in minutes")
                        Text(draft.intervalMinutes == 1 ? "minute" : "minutes")
                    }
                }
            }
            SettingsFormRow {
                SettingsResponsiveControlRow("Anchor", horizontalControlSizing: .intrinsicInline) {
                    DatePicker(
                        "Anchor",
                        selection: $draft.intervalAnchorAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(\.timeZone, selectedTimeZone)
                    .datePickerStyle(.field)
                    .labelsHidden()
                }
            }
        case .daily:
            wallClockRow
        case .weekdays:
            weekdaySelectionRow
            wallClockRow
        case .weekly:
            SettingsFormRow {
                SettingsResponsiveControlRow("Weekday", horizontalControlSizing: .intrinsic) {
                    Picker("Weekday", selection: $draft.weeklyWeekday) {
                        ForEach(1 ... 7, id: \.self) { weekday in
                            Text(ScheduledTaskPresentationFormatting.weekdayName(weekday)).tag(weekday)
                        }
                    }
                    .labelsHidden()
                }
            }
            wallClockRow
        case .monthly:
            SettingsFormRow {
                SettingsResponsiveControlRow("Day of month", horizontalControlSizing: .intrinsic) {
                    Stepper(value: $draft.monthlyDay, in: 1 ... 31) {
                        Text("Day \(draft.monthlyDay)")
                    }
                }
            }
            wallClockRow
        }
    }

    private var wallClockRow: some View {
        SettingsFormRow {
            SettingsResponsiveControlRow("Time", horizontalControlSizing: .intrinsic) {
                HStack(spacing: 8) {
                    Picker("Hour", selection: $draft.wallClockHour) {
                        ForEach(0 ... 23, id: \.self) { hour in
                            Text(String(format: "%02d", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    Text(":")
                    Picker("Minute", selection: $draft.wallClockMinute) {
                        ForEach(0 ... 59, id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Scheduled time")
            }
        }
    }

    private var weekdaySelectionRow: some View {
        SettingsFormRow {
            SettingsResponsiveControlRow(
                "Days",
                helpText: "Choose one or more days for this task to run.",
                horizontalControlSizing: .intrinsic
            ) {
                HStack(spacing: 4) {
                    ForEach(1 ... 7, id: \.self) { weekday in
                        let name = ScheduledTaskPresentationFormatting.weekdayName(weekday)
                        Toggle(
                            isOn: weekdayBinding(weekday)
                        ) {
                            Text(ScheduledTaskPresentationFormatting.shortWeekdayName(weekday))
                                .frame(minWidth: 20)
                        }
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .fixedSize()
                        .accessibilityLabel(name)
                        .help(name)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Scheduled days")
            }
        }
    }

    private func weekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { draft.selectedWeekdays.contains(weekday) },
            set: { isSelected in
                if isSelected {
                    draft.selectedWeekdays.insert(weekday)
                } else {
                    draft.selectedWeekdays.remove(weekday)
                }
            }
        )
    }

    private var timeZoneIdentifiers: [String] {
        let current = draft.timeZoneIdentifier
        guard !TimeZone.knownTimeZoneIdentifiers.contains(current) else {
            return TimeZone.knownTimeZoneIdentifiers
        }
        return [current] + TimeZone.knownTimeZoneIdentifiers
    }

    private var selectedTimeZone: TimeZone {
        TimeZone(identifier: draft.timeZoneIdentifier) ?? .current
    }

    private var intervalMinutesBinding: Binding<Int> {
        Binding(
            get: { draft.intervalMinutes },
            set: { draft.intervalMinutes = max(1, $0) }
        )
    }
}

private extension ScheduledTaskRecurrence.Kind {
    var label: String {
        switch self {
        case .once:
            "Once"
        case .interval:
            "Interval"
        case .daily:
            "Daily"
        case .weekdays:
            "Weekdays"
        case .weekly:
            "Weekly"
        case .monthly:
            "Monthly"
        }
    }
}
