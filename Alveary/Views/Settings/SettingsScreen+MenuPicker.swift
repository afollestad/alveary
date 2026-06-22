import SwiftUI

struct SettingsMenuPicker<Value: Hashable>: View {
    let title: String
    let options: [Value]
    let placeholder: String?
    let isDisabled: Bool
    let label: (Value) -> String

    @Binding private var selection: Value

    init(
        _ title: String,
        selection: Binding<Value>,
        options: [Value],
        placeholder: String? = nil,
        isDisabled: Bool = false,
        label: @escaping (Value) -> String
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.placeholder = placeholder
        self.isDisabled = isDisabled
        self.label = label
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(placeholder ?? label(selection))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(
                minWidth: SettingsScreenLayout.settingsPickerWidth,
                maxWidth: .infinity,
                minHeight: SettingsScreenLayout.settingsControlSurfaceHeight,
                maxHeight: SettingsScreenLayout.settingsControlSurfaceHeight,
                alignment: .leading
            )
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || options.isEmpty)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(title)
        .accessibilityValue(placeholder ?? label(selection))
    }
}
