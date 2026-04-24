import AppKit
import SwiftUI

struct SplitActionButton<Option: Hashable>: View {
    let title: String
    let systemImage: String
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
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: controlHeight)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.primary.opacity(isEnabled ? 0.16 : 0.08))
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
        .foregroundStyle(.primary.opacity(isEnabled ? 1 : 0.78))
        .frame(height: controlHeight)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .opacity(showsHoverOverlay ? 1 : 0)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var showsHoverOverlay: Bool {
        isHovering && isEnabled
    }

    private var backgroundColor: Color {
        if isEnabled {
            return AppAccentFill.primary
        }
        return AppAccentFill.primary.opacity(0.38)
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini:
            return 8
        case .small:
            return 10
        case .regular:
            return 12
        case .large:
            return 14
        case .extraLarge:
            return 16
        @unknown default:
            return 12
        }
    }

    private var controlHeight: CGFloat {
        switch controlSize {
        case .mini:
            return 22
        case .small:
            return 24
        case .regular:
            return 30
        case .large:
            return 34
        case .extraLarge:
            return 38
        @unknown default:
            return 30
        }
    }

    private var cornerRadius: CGFloat {
        switch controlSize {
        case .mini:
            return 8
        case .small:
            return 9
        case .regular:
            return 10
        case .large:
            return 12
        case .extraLarge:
            return 14
        @unknown default:
            return 10
        }
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
