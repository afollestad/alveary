import SwiftUI

struct ScheduledTaskMenuOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String

    var id: Value { value }
}

struct ScheduledTaskMenuPicker<Value: Hashable>: View {
    let accessibilityLabel: String
    @Binding var selection: Value
    let options: [ScheduledTaskMenuOption<Value>]
    let placeholder: String?

    init(
        accessibilityLabel: String,
        selection: Binding<Value>,
        options: [ScheduledTaskMenuOption<Value>],
        placeholder: String? = nil
    ) {
        self.accessibilityLabel = accessibilityLabel
        _selection = selection
        self.options = options
        self.placeholder = placeholder
    }

    private var selectedLabel: String {
        options.first(where: { $0.value == selection })?.label ?? placeholder ?? "Select"
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(
                minHeight: SettingsScreenLayout.settingsControlSurfaceHeight,
                maxHeight: SettingsScreenLayout.settingsControlSurfaceHeight
            )
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(selectedLabel)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectedLabel)
    }
}
