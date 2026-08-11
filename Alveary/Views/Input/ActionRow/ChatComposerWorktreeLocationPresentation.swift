import AppKit

extension ChatComposerActionRowView {
    struct WorktreeLocationOptionPresentation: Equatable {
        let value: String
        let title: String
        let symbolName: String
        let iconRotationRadians: CGFloat

        var usesWorktree: Bool {
            value == ChatComposerWorktreeLocationPresentation.worktreeValue
        }
    }
}

enum ChatComposerWorktreeLocationPresentation {
    static let localValue = "false"
    static let worktreeValue = "true"
    private static let branchSymbolName = "arrow.trianglehead.branch"
    private static let branchFallbackSymbolName = "arrow.triangle.branch"

    @MainActor
    static func options() -> [ChatComposerActionRowView.WorktreeLocationOptionPresentation] {
        [
            .init(
                value: localValue,
                title: ChatComposerTextSupport.worktreeLocationLabel(for: false),
                symbolName: "laptopcomputer",
                iconRotationRadians: 0
            ),
            .init(
                value: worktreeValue,
                title: ChatComposerTextSupport.worktreeLocationLabel(for: true),
                symbolName: resolvedSymbolName(preferred: branchSymbolName, fallback: branchFallbackSymbolName),
                iconRotationRadians: CGFloat.pi / 2
            )
        ]
    }

    @MainActor
    static func selectedOption(
        usesWorktree: Bool
    ) -> ChatComposerActionRowView.WorktreeLocationOptionPresentation {
        let selectedValue = usesWorktree ? worktreeValue : localValue
        return options().first { $0.value == selectedValue } ?? options()[0]
    }

    @MainActor
    static func resolvedSymbolName(preferred: String, fallback: String) -> String {
        NSImage(systemSymbolName: preferred, accessibilityDescription: nil) == nil
            ? fallback
            : preferred
    }
}

@MainActor
final class ComposerWorktreeLocationButton: ComposerIconTitleDropdownButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityLabel("Thread location")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityLabel("Thread location")
    }

    func configure(
        option: ChatComposerActionRowView.WorktreeLocationOptionPresentation,
        height: CGFloat,
        isEnabled: Bool,
        actionHandler: @escaping () -> Void
    ) {
        configure(
            presentation: .init(
                title: option.title,
                symbolName: option.symbolName,
                iconRotationRadians: option.iconRotationRadians
            ),
            height: height,
            isEnabled: isEnabled,
            actionHandler: actionHandler
        )
    }
}
