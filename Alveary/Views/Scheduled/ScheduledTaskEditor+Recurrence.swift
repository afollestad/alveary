import SwiftUI

struct ScheduledTaskEditorRecurrenceSection: View {
    @Binding var draft: ScheduledTaskEditorDraft
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        SettingsFormSection("Schedule") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Repeats", horizontalControlSizing: .selectedContent) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Repeats",
                        selection: $draft.recurrenceKind,
                        options: ScheduledTaskRecurrence.Kind.allCases.map {
                            .init(value: $0, label: $0.label)
                        }
                    )
                }
            }

            recurrenceFields
        }
    }

    @ViewBuilder private var recurrenceFields: some View {
        switch draft.recurrenceKind {
        case .once:
            SettingsFormRow(showsDivider: false) {
                SettingsResponsiveControlRow("Run at", horizontalControlSizing: .intrinsicInline) {
                    DatePicker(
                        "Run at",
                        selection: $draft.onceOccurrenceAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .offset(y: -1 / max(displayScale, 1))
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
            SettingsFormRow(showsDivider: false) {
                SettingsResponsiveControlRow("Anchor", horizontalControlSizing: .intrinsicInline) {
                    DatePicker(
                        "Anchor",
                        selection: $draft.intervalAnchorAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .offset(y: -1 / max(displayScale, 1))
                }
            }
        case .daily:
            wallClockRow
        case .weekdays:
            weekdaySelectionRow
            wallClockRow
        case .weekly:
            SettingsFormRow {
                SettingsResponsiveControlRow("Weekday", horizontalControlSizing: .selectedContent) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Weekday",
                        selection: $draft.weeklyWeekday,
                        options: (1 ... 7).map {
                            .init(value: $0, label: ScheduledTaskPresentationFormatting.weekdayName($0))
                        }
                    )
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
        SettingsFormRow(showsDivider: false) {
            SettingsResponsiveControlRow("Time", horizontalControlSizing: .selectedContent) {
                HStack(spacing: 8) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Hour",
                        selection: $draft.wallClockHour,
                        options: (0 ... 23).map { .init(value: $0, label: String(format: "%02d", $0)) }
                    )
                    Text(":")
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Minute",
                        selection: $draft.wallClockMinute,
                        options: (0 ... 59).map { .init(value: $0, label: String(format: "%02d", $0)) }
                    )
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
