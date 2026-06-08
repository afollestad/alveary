import AppKit

@MainActor
final class ComposerPermissionButton: ComposerCompactDropdownButton {
    static let minWidth: CGFloat = 64
    static let maxWidth: CGFloat = 184

    private static let iconSlotSize: CGFloat = 16
    private static let iconTextSpacing: CGFloat = 5
    private static let iconPointSize: CGFloat = 13

    private var option: ChatComposerActionRowView.PermissionOptionPresentation?

    override var minimumDropdownWidth: CGFloat { Self.minWidth }
    override var maximumDropdownWidth: CGFloat { Self.maxWidth }
    override var chevronSlotWidth: CGFloat { Self.iconTextSpacing + chevronDrawingWidth }
    override var measuredContentWidth: CGFloat {
        guard let option else {
            return 0
        }
        return Self.iconSlotSize + Self.iconTextSpacing +
            option.title.size(withAttributes: [.font: titleFont]).width
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityLabel("Permissions")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityLabel("Permissions")
    }

    func configure(
        option: ChatComposerActionRowView.PermissionOptionPresentation,
        height: CGFloat,
        isEnabled: Bool,
        actionHandler: @escaping () -> Void
    ) {
        self.option = option
        configureBase(height: height, isEnabled: isEnabled, actionHandler: actionHandler)
        setAccessibilityValue(option.title)
    }

    #if DEBUG
    var debugTitle: String? { option?.title }
    var debugSymbolName: String? { option?.symbolName }
    var debugIsWarning: Bool { option?.isWarning == true }
    var debugIconTextSpacing: CGFloat { Self.iconTextSpacing }
    var debugTextChevronSpacing: CGFloat { chevronSlotWidth - chevronDrawingWidth }
    #endif

    override func drawContent(in rect: NSRect) {
        guard let option else {
            return
        }
        let foregroundColor = foregroundColor(for: option)
        if let image = permissionSymbolImage(
            named: option.symbolName,
            color: foregroundColor
        ) {
            let drawSize = symbolDrawingSize(for: image, maxSize: Self.iconSlotSize)
            image.draw(
                in: NSRect(
                    x: rect.minX + floor((Self.iconSlotSize - drawSize.width) / 2),
                    y: floor((bounds.height - drawSize.height) / 2),
                    width: drawSize.width,
                    height: drawSize.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: foregroundColor,
            .paragraphStyle: truncatingParagraphStyle
        ]
        let titleSize = option.title.size(withAttributes: attributes)
        let titleX = rect.minX + Self.iconSlotSize + Self.iconTextSpacing
        (option.title as NSString).draw(
            in: NSRect(
                x: titleX,
                y: floor((bounds.height - titleSize.height) / 2),
                width: max(0, rect.maxX - titleX),
                height: titleSize.height
            ),
            withAttributes: attributes
        )
    }

    private var titleFont: NSFont {
        NSFont.preferredFont(forTextStyle: .body)
    }

    private var truncatingParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    private func foregroundColor(for option: ChatComposerActionRowView.PermissionOptionPresentation) -> NSColor {
        let color: NSColor = option.isWarning ? .systemOrange : .labelColor
        return color.appKitResolvedColor(in: self, alpha: textAlpha)
    }

    private func permissionSymbolImage(named name: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: Self.iconPointSize,
            weight: .semibold
        ).applying(.init(paletteColors: [color, color, color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private var chevronDrawingWidth: CGFloat {
        guard let image = symbolImage(named: "chevron.down", pointSize: chevronMaxSize, color: .labelColor) else {
            return chevronMaxSize
        }
        return symbolDrawingSize(for: image, maxSize: chevronMaxSize).width
    }
}
