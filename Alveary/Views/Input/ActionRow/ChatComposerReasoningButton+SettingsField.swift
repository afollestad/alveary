import AppKit

extension ComposerReasoningButton {
    /// `composer` hugs its content in the action row. `settingsField` sits among `SettingsMenuPicker` rows, so it
    /// takes their fill, padding, width floor, regular-weight title, and trailing-pinned up/down chevron.
    enum Presentation {
        case composer
        case settingsField

        var chromeStyle: ChromeStyle {
            switch self {
            case .composer: .composer
            case .settingsField: .field
            }
        }

        @MainActor var minimumWidth: CGFloat {
            switch self {
            case .composer: ComposerReasoningButton.minWidth
            case .settingsField: SettingsScreenLayout.settingsPickerWidth
            }
        }

        @MainActor var maximumWidth: CGFloat {
            switch self {
            case .composer: ComposerReasoningButton.maxWidth
            case .settingsField: 320
            }
        }

        @MainActor var accessorySpacing: CGFloat {
            switch self {
            case .composer: ComposerReasoningButton.caretTextSpacing
            case .settingsField: 8
            }
        }

        /// `NSTextField` draws its glyphs 2pt inside its frame, so the field pulls the title back to line its glyphs up
        /// with `SettingsMenuPicker`'s padding.
        var titleLeadingOffset: CGFloat {
            switch self {
            case .composer: 0
            case .settingsField: -2
            }
        }

        var pinsTrailingAccessory: Bool {
            self == .settingsField
        }

        var chevronSymbolName: String {
            switch self {
            case .composer: "chevron.down"
            case .settingsField: "chevron.up.chevron.down"
            }
        }

        @MainActor var chevronPointSize: CGFloat {
            switch self {
            case .composer: ComposerReasoningButton.caretMaximumSize
            case .settingsField: 13
            }
        }

        var chevronWeight: NSFont.Weight {
            switch self {
            case .composer: .medium
            case .settingsField: .semibold
            }
        }
    }
}
