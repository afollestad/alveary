import AppKit

@MainActor
final class ComposerReasoningDragDirectionLabel: NSTextField {
    init(title: String) {
        super.init(frame: .zero)
        stringValue = title
        isEditable = false
        isBordered = false
        drawsBackground = false
        font = ComposerReasoningMenuMetrics.itemFont
        textColor = .secondaryLabelColor
        isHidden = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let size = stringValue.size(withAttributes: textAttributes)
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = intrinsicContentSize
        (stringValue as NSString).draw(
            in: NSRect(x: 0, y: floor((bounds.height - size.height) / 2), width: size.width, height: size.height),
            withAttributes: textAttributes
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font ?? ComposerReasoningMenuMetrics.itemFont,
            .foregroundColor: NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: 0.82)
        ]
    }
}

@MainActor
final class ComposerReasoningModelsSectionClipView: NSView {
    var allowsHitTesting = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard allowsHitTesting else {
            return nil
        }
        return super.hitTest(point)
    }
}

extension ChatComposerActionRowView.ReasoningSelection {
    func updatingEffort(_ option: ChatComposerActionRowView.MenuOption) -> Self {
        Self(
            providerID: providerID,
            providerTitle: providerTitle,
            modelID: modelID,
            modelTitle: modelTitle,
            effortValue: option.value,
            effortTitle: option.title,
            effortOptions: effortOptions,
            defaultEffortValue: defaultEffortValue,
            speedMode: speedMode,
            supportsSpeedMode: supportsSpeedMode
        )
    }

    func updatingSpeedMode(_ speedMode: AgentSpeedMode) -> Self {
        Self(
            providerID: providerID,
            providerTitle: providerTitle,
            modelID: modelID,
            modelTitle: modelTitle,
            effortValue: effortValue,
            effortTitle: effortTitle,
            effortOptions: effortOptions,
            defaultEffortValue: defaultEffortValue,
            speedMode: speedMode,
            supportsSpeedMode: supportsSpeedMode
        )
    }
}

extension Collection {
    subscript(reasoningMenuSafe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension NSView {
    func isReasoningMenuDescendant(of view: NSView) -> Bool {
        var ancestor = superview
        while let current = ancestor {
            if current === view {
                return true
            }
            ancestor = current.superview
        }
        return false
    }
}
