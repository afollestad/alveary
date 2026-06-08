import AppKit

@MainActor
class ComposerIconTitleDropdownButton: ComposerCompactDropdownButton {
    static let minWidth: CGFloat = 64
    static let maxWidth: CGFloat = 184

    private static let iconSlotSize: CGFloat = 16
    private static let iconTextSpacing: CGFloat = 5
    private static let iconPointSize: CGFloat = 13

    struct Presentation: Equatable {
        let title: String
        let symbolName: String
        let iconRotationRadians: CGFloat
        let isWarning: Bool

        init(
            title: String,
            symbolName: String,
            iconRotationRadians: CGFloat = 0,
            isWarning: Bool = false
        ) {
            self.title = title
            self.symbolName = symbolName
            self.iconRotationRadians = iconRotationRadians
            self.isWarning = isWarning
        }
    }

    private var presentation: Presentation?

    override var minimumDropdownWidth: CGFloat { Self.minWidth }
    override var maximumDropdownWidth: CGFloat { Self.maxWidth }
    override var chevronSlotWidth: CGFloat { Self.iconTextSpacing + chevronDrawingWidth }
    override var measuredContentWidth: CGFloat {
        guard let presentation else {
            return 0
        }
        return Self.iconSlotSize + Self.iconTextSpacing +
            presentation.title.size(withAttributes: [.font: titleFont]).width
    }

    func configure(
        presentation: Presentation,
        height: CGFloat,
        isEnabled: Bool,
        actionHandler: @escaping () -> Void
    ) {
        self.presentation = presentation
        configureBase(height: height, isEnabled: isEnabled, actionHandler: actionHandler)
        setAccessibilityValue(presentation.title)
    }

    #if DEBUG
    var debugTitle: String? { presentation?.title }
    var debugSymbolName: String? { presentation?.symbolName }
    var debugIconRotationRadians: CGFloat { presentation?.iconRotationRadians ?? 0 }
    var debugIsWarning: Bool { presentation?.isWarning == true }
    var debugIconTextSpacing: CGFloat { Self.iconTextSpacing }
    var debugTextChevronSpacing: CGFloat { chevronSlotWidth - chevronDrawingWidth }
    #endif

    override func drawContent(in rect: NSRect) {
        guard let presentation else {
            return
        }
        let foregroundColor = foregroundColor(for: presentation)
        if let image = permissionSymbolImage(
            named: presentation.symbolName,
            color: foregroundColor
        ) {
            let drawSize = symbolDrawingSize(for: image, maxSize: Self.iconSlotSize)
            drawImage(
                image,
                in: NSRect(
                    x: rect.minX + floor((Self.iconSlotSize - drawSize.width) / 2),
                    y: floor((bounds.height - drawSize.height) / 2),
                    width: drawSize.width,
                    height: drawSize.height
                ),
                rotationRadians: presentation.iconRotationRadians
            )
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: foregroundColor,
            .paragraphStyle: truncatingParagraphStyle
        ]
        let titleSize = presentation.title.size(withAttributes: attributes)
        let titleX = rect.minX + Self.iconSlotSize + Self.iconTextSpacing
        (presentation.title as NSString).draw(
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

    private func foregroundColor(for presentation: Presentation) -> NSColor {
        let color: NSColor = presentation.isWarning ? .systemOrange : .labelColor
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

    private func drawImage(_ image: NSImage, in rect: NSRect, rotationRadians: CGFloat) {
        guard rotationRadians != 0 else {
            image.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            return
        }

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byRadians: rotationRadians)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private var chevronDrawingWidth: CGFloat {
        guard let image = symbolImage(named: "chevron.down", pointSize: chevronMaxSize, color: .labelColor) else {
            return chevronMaxSize
        }
        return symbolDrawingSize(for: image, maxSize: chevronMaxSize).width
    }
}

@MainActor
final class ComposerPermissionButton: ComposerIconTitleDropdownButton {
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
        configure(
            presentation: .init(
                title: option.title,
                symbolName: option.symbolName,
                isWarning: option.isWarning
            ),
            height: height,
            isEnabled: isEnabled,
            actionHandler: actionHandler
        )
    }
}
