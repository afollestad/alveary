import SwiftUI

struct ProjectSettingsActionIconPicker: View {
    let symbolName: String
    let onSelect: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        let currentOption = ProjectSettingsActionIconOption.resolved(for: symbolName)
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: currentOption.symbolName)
        }
        .iconActionButtonStyle()
        .help("Choose action icon (\(currentOption.label))")
        .accessibilityLabel("Action icon")
        .accessibilityValue(currentOption.label)
        .appKitPopover(isPresented: $isPresented) {
            ProjectSettingsActionIconGrid(symbolName: symbolName) { selectedIcon in
                isPresented = false
                onSelect(selectedIcon)
            }
            .onExitCommand { isPresented = false }
        }
    }
}

/// Separate content allows visual coverage without showing an NSPopover in the test host.
struct ProjectSettingsActionIconGrid: View {
    let symbolName: String
    let onSelect: (String) -> Void

    /// Let the popover choose initial focus; a constant `defaultFocus` overrides subsequent keyboard moves on host updates.
    @FocusState private var focusedSymbol: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: ProjectSettingsIconNavigation.columnCount)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(ProjectSettingsActionIconOption.supported) { option in
                let isSelected = option.symbolName == symbolName
                Button {
                    onSelect(option.symbolName)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 20))
                            .frame(height: 24)
                            .accessibilityHidden(true)
                        Text(option.label)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.standard))
                }
                .buttonStyle(ProjectSettingsIconOptionStyle(isSelected: isSelected, isKeyboardFocused: focusedSymbol == option.symbolName))
                // Explicit edit focus keeps keyboard selection available even when macOS's
                // optional keyboard navigation for ordinary buttons is disabled.
                .focusable(interactions: .edit)
                .focused($focusedSymbol, equals: option.symbolName)
                .focusEffectDisabled()
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(12)
        .frame(width: 318)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Action icons")
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .tab, .return, .space], action: handleKeyPress)
    }

    private var initialFocusedSymbol: String? {
        let options = ProjectSettingsActionIconOption.supported
        return options.first(where: { $0.symbolName == symbolName })?.symbolName ?? options.first?.symbolName
    }

    /// The popover owns key focus, so traversal stays inside this palette and never reaches the sidebar or composer.
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        let options = ProjectSettingsActionIconOption.supported
        guard let current = options.firstIndex(where: { $0.symbolName == (focusedSymbol ?? initialFocusedSymbol) }) else {
            return .ignored
        }
        let direction: ProjectSettingsIconNavigation.Direction
        switch press.key {
        case .return, .space:
            onSelect(options[current].symbolName)
            return .handled
        case .tab:
            direction = press.modifiers.contains(.shift) ? .previous : .next
        case .leftArrow:
            direction = .previous
        case .rightArrow:
            direction = .next
        case .upArrow:
            direction = .upward
        case .downArrow:
            direction = .downward
        default:
            return .ignored
        }
        guard let index = ProjectSettingsIconNavigation.destination(from: current, direction: direction, count: options.count) else {
            return .ignored
        }
        focusedSymbol = options[index].symbolName
        return .handled
    }
}

/// Vertical movement retains its column and skips the missing cell in the final three-column row.
enum ProjectSettingsIconNavigation {
    static let columnCount = 3

    enum Direction {
        case previous, next, upward, downward
    }

    static func destination(from index: Int, direction: Direction, count: Int) -> Int? {
        guard count > 0, (0..<count).contains(index) else { return nil }
        switch direction {
        case .previous:
            return (index + count - 1) % count
        case .next:
            return (index + 1) % count
        case .upward, .downward:
            let column = index % columnCount
            let row = index / columnCount
            let rowsInColumn = (count - column + columnCount - 1) / columnCount
            let offset = direction == .upward ? -1 : 1
            let nextRow = (row + offset + rowsInColumn) % rowsInColumn
            return nextRow * columnCount + column
        }
    }
}

/// A palette tile needs a taller surface than the shared single-line action buttons.
private struct ProjectSettingsIconOptionStyle: ButtonStyle {
    let isSelected: Bool
    let isKeyboardFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        ProjectSettingsIconOptionBody(configuration: configuration, isSelected: isSelected, isKeyboardFocused: isKeyboardFocused)
    }
}

private struct ProjectSettingsIconOptionBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let isKeyboardFocused: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                AppSelectionRowBackground(
                    isSelected: isSelected,
                    isPressed: configuration.isPressed,
                    isHovered: isHovered,
                    leadingInset: 0, trailingInset: 0, topInset: 0, bottomInset: 0
                )
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if isKeyboardFocused {
                    RoundedRectangle(cornerRadius: AppCornerRadius.standard)
                        .strokeBorder(isSelected ? Color.primary : AppAccentFill.primary, lineWidth: 2)
                }
            }
            .onHover { isHovered = $0 }
    }
}
