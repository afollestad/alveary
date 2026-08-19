import AppKit
import SwiftUI

/// Which of the shared action-button fills a `SplitActionButton` wears. Mirrors
/// `primaryActionButtonStyle()` / `secondaryActionButtonStyle()` /
/// `destructiveActionButtonStyle()` so a split button can sit beside a plain one
/// without a second accent voice in the row.
enum SplitActionButtonEmphasis {
    case primary
    case secondary
    case destructive

    var fill: Color {
        switch self {
        case .primary:
            return AppAccentFill.primary
        case .secondary:
            return ActionButtonTint.secondary
        case .destructive:
            return ActionButtonTint.destructive
        }
    }

    /// Destructive fills are opaque red, so their label goes white like the plain
    /// destructive style's; the other two read against `.primary`.
    var foreground: Color {
        self == .destructive ? .white : .primary
    }
}

struct SplitActionButton<Option: Hashable>: View {
    let title: String
    /// Optional: footer actions carry text alone.
    var icon: ActionIcon?
    var emphasis = SplitActionButtonEmphasis.primary
    /// Fills the available width, for the even-split pane footer rows.
    var expandsHorizontally = false
    /// Swaps the leading glyph for a spinner, then dims the pill and blocks the primary click
    /// while that work runs. Dimmed on purpose: this is not "hold on a second", it is "not until
    /// that finishes", and a fully-lit button invites a click it will swallow.
    ///
    /// **The caret dims with the pill but stays clickable.** It is the only way to put a different
    /// option on the face, so killing it would strand the user behind whichever one is running.
    var isBusy = false
    let selectedOption: Option
    let options: [Option]
    let optionTitle: (Option) -> String
    let action: () -> Void
    let selectOption: (Option) -> Void

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                label
                    .lineLimit(1)
                    .padding(.horizontal, horizontalPadding)
                    .frame(maxWidth: expandsHorizontally ? .infinity : nil)
                    .frame(height: controlHeight)
                    // The fill lives on the outer `HStack` so it can span the
                    // divider and caret, which leaves this label unbacked — and
                    // a `.plain` button hit-tests its label's own shape, so
                    // without this only the glyphs took clicks.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isActionEnabled)
            // Scoped to this half: the caret beside it is still clickable, so a blocked cursor
            // across the whole pill would lie about the menu.
            .blockedCursorOverlay(when: !isActionEnabled)
            // The spinner is decorative, so without this VoiceOver reads a busy button as
            // nothing but dimmed, with no word for what the dimming means.
            .accessibilityValue(isBusy ? "Working" : "")

            Rectangle()
                .fill(emphasis.foreground.opacity(isDimmed ? 0.08 : 0.16))
                .frame(width: 1)
                .padding(.vertical, 4)

            ZStack {
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .frame(width: menuWidth, height: controlHeight)

                SplitActionMenuTrigger(
                    selectedOption: selectedOption,
                    options: options,
                    optionTitle: optionTitle,
                    isEnabled: isEnabled,
                    selectOption: selectOption
                )
                .frame(width: menuWidth, height: controlHeight)
            }
            .frame(width: menuWidth, height: controlHeight)
        }
        .font(.body.weight(.semibold))
        .imageScale(.small)
        .foregroundStyle(emphasis.foreground.opacity(isDimmed ? 0.78 : 1))
        .frame(maxWidth: expandsHorizontally ? .infinity : nil)
        .frame(height: controlHeight)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
                // Hover leans toward the label color, like `ProminentActionButtonBody`.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(emphasis.foreground.opacity(0.06))
                    .opacity(showsHoverOverlay ? 1 : 0)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(borderOpacity), lineWidth: borderWidth)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var label: some View {
        if let icon {
            ActionButtonLabel(title: title, icon: icon, isBusy: isBusy, busyTint: emphasis.foreground)
        } else {
            Text(title)
        }
    }

    /// Busy blocks the primary click; only `.disabled(...)` blocks the caret with it.
    private var isActionEnabled: Bool {
        isEnabled && !isBusy
    }

    /// Disabled and busy paint the same, because they mean the same thing to the person looking at
    /// it: this button is not going to do anything if you press it.
    private var isDimmed: Bool {
        !isEnabled || isBusy
    }

    private var showsHoverOverlay: Bool {
        isHovering && isActionEnabled
    }

    private var backgroundColor: Color {
        isDimmed ? emphasis.fill.opacity(0.38) : emphasis.fill
    }

    /// The secondary fill is translucent, so it needs the same hairline border
    /// `secondaryActionButtonStyle()` draws to read as a control at all.
    private var borderWidth: CGFloat {
        emphasis == .secondary ? 1 : 0
    }

    private var borderOpacity: Double {
        guard emphasis == .secondary else {
            return 0
        }
        return isDimmed ? 0.06 : 0.12
    }

    private var horizontalPadding: CGFloat {
        ActionButtonMetrics.horizontalPadding(for: controlSize)
    }

    private var controlHeight: CGFloat {
        ActionButtonMetrics.controlHeight(for: controlSize)
    }

    private var cornerRadius: CGFloat {
        ActionButtonMetrics.cornerRadius
    }

    private var menuWidth: CGFloat {
        switch controlSize {
        case .mini:
            return 18
        case .small:
            return 22
        case .regular:
            return 26
        case .large:
            return 28
        case .extraLarge:
            return 32
        @unknown default:
            return 26
        }
    }
}

private struct SplitActionMenuTrigger<Option: Hashable>: NSViewRepresentable {
    let selectedOption: Option
    let options: [Option]
    let optionTitle: (Option) -> String
    let isEnabled: Bool
    let selectOption: (Option) -> Void

    // Use an invisible AppKit button to show NSMenu without SwiftUI Menu adding its own caret.
    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedOption: selectedOption,
            options: options,
            optionTitle: optionTitle,
            selectOption: selectOption
        )
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.openMenu(_:)))
        button.isBordered = false
        button.isTransparent = true
        button.setButtonType(.momentaryChange)
        button.focusRingType = .none
        button.setAccessibilityLabel("Show action options")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.selectedOption = selectedOption
        context.coordinator.options = options
        context.coordinator.optionTitle = optionTitle
        context.coordinator.selectOption = selectOption
        button.isEnabled = isEnabled && !options.isEmpty
    }

    @MainActor
    final class Coordinator: NSObject {
        var selectedOption: Option
        var options: [Option]
        var optionTitle: (Option) -> String
        var selectOption: (Option) -> Void

        init(
            selectedOption: Option,
            options: [Option],
            optionTitle: @escaping (Option) -> String,
            selectOption: @escaping (Option) -> Void
        ) {
            self.selectedOption = selectedOption
            self.options = options
            self.optionTitle = optionTitle
            self.selectOption = selectOption
        }

        @objc
        func openMenu(_ sender: NSButton) {
            guard !options.isEmpty else {
                return
            }

            let menu = NSMenu()
            for (index, option) in options.enumerated() {
                let item = NSMenuItem(
                    title: optionTitle(option),
                    action: #selector(selectMenuItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = index
                item.state = option == selectedOption ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
        }

        @objc
        func selectMenuItem(_ sender: NSMenuItem) {
            guard let index = sender.representedObject as? Int,
                  options.indices.contains(index) else {
                return
            }
            selectOption(options[index])
        }
    }
}
